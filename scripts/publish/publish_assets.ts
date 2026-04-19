// Build the per-platform asset pack matrix, upload to R2 + Arweave, and
// rewrite assets_manifest.json. Arweave is permanent and paid (Turbo
// credits); R2 is cheap and mutable. Both run by default — skip-if-sha-
// unchanged keeps iteration costs low.
//
//   cd scripts/publish && npm install                # first time
//   npm run upload-pack                              # build + R2 + Arweave
//   npm run upload-pack -- --packs=stages,chars      # only those packs
//   npm run upload-pack -- --skip-build              # reuse existing dist/*.pck
//   npm run upload-pack -- --skip-r2                 # no R2 upload this run
//   npm run upload-pack -- --skip-arweave            # no Arweave upload this run
//   npm run upload-pack -- --dry-run                 # plan only, no work
//   npm run upload-pack -- --yes                     # skip cost confirmation prompt
//
// All paths resolve relative to the repo root regardless of CWD.

import "./lib/env.js";
import { execSync } from "child_process";
import { readFileSync, writeFileSync, existsSync, statSync, readdirSync, unlinkSync } from "fs";
import { createHash } from "crypto";
import { resolve, dirname, join } from "path";
import { fileURLToPath } from "url";
import { createInterface } from "readline/promises";
import { stdin as input, stdout as output } from "process";
import { loadR2Config, uploadFileToR2 } from "./lib/r2.js";
import { loadWallet } from "./lib/wallet.js";
import { createTurbo, estimateCost, getBalanceWinc, uploadFileToArweave } from "./lib/ardrive.js";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const REPO_ROOT = resolve(__dirname, "../..");

const PACKS_CONFIG = resolve(__dirname, "packs.json");
const MANIFEST_OUT = resolve(REPO_ROOT, "assets_manifest.json");
const VERSION_FILE = resolve(REPO_ROOT, "VERSION");
const DIST_DIR = resolve(REPO_ROOT, "dist");
const BUILD_SCRIPT = "scripts/tools/build_assets_pack.gd";

const GODOT_VERSION = "4.5";

interface PackConfig {
  name: string;
  per_platform: boolean;
  include: string[];
}

interface PacksFile {
  platforms: string[];
  packs: PackConfig[];
}

interface CliArgs {
  packsFilter: Set<string> | null;
  skipBuild: boolean;
  skipR2: boolean;
  skipArweave: boolean;
  dryRun: boolean;
  yes: boolean;
}

const ARWEAVE_URL_RE = /arweave\.net|ar-io\.dev|permagate\.io/;
const R2_URL_RE = /r2\.dev/;

interface BuildOutput {
  packName: string;
  platform: string | null; // null for universal
  pckPath: string;
  sha256: string;
  size: number;
}

interface ManifestPackPlatformEntry {
  sha256: string;
  size: number;
  urls: string[];
}

interface ManifestPack {
  name: string;
  // Either flat (universal) or platforms map (per-platform). Mutually exclusive.
  sha256?: string;
  size?: number;
  urls?: string[];
  platforms?: Record<string, ManifestPackPlatformEntry>;
}

interface Manifest {
  version: string;
  godot_version: string;
  packs: ManifestPack[];
}

function parseArgs(): CliArgs {
  const args = process.argv.slice(2);
  let packsFilter: Set<string> | null = null;
  for (const a of args) {
    if (a.startsWith("--packs=")) {
      packsFilter = new Set(a.slice("--packs=".length).split(",").filter(Boolean));
    }
  }
  return {
    packsFilter,
    skipBuild: args.includes("--skip-build"),
    skipR2: args.includes("--skip-r2"),
    skipArweave: args.includes("--skip-arweave"),
    dryRun: args.includes("--dry-run"),
    yes: args.includes("--yes") || args.includes("-y"),
  };
}

async function confirm(prompt: string): Promise<boolean> {
  const rl = createInterface({ input, output });
  const answer = (await rl.question(`${prompt} [y/N] `)).trim().toLowerCase();
  rl.close();
  return answer === "y" || answer === "yes";
}

function wincToAr(winc: string | bigint): string {
  const n = typeof winc === "bigint" ? winc : BigInt(winc);
  const whole = Number(n / 1_000_000_000_000n);
  const frac = Number(n % 1_000_000_000_000n) / 1e12;
  return (whole + frac).toFixed(4);
}

function loadPacksConfig(): PacksFile {
  const raw = JSON.parse(readFileSync(PACKS_CONFIG, "utf8")) as PacksFile;
  if (!Array.isArray(raw.platforms) || raw.platforms.length === 0) {
    throw new Error(`${PACKS_CONFIG} missing platforms[]`);
  }
  if (!Array.isArray(raw.packs) || raw.packs.length === 0) {
    throw new Error(`${PACKS_CONFIG} missing packs[]`);
  }
  for (const p of raw.packs) {
    if (!p.name || typeof p.per_platform !== "boolean" || !Array.isArray(p.include)) {
      throw new Error(`${PACKS_CONFIG}: invalid pack entry ${JSON.stringify(p)}`);
    }
  }
  return raw;
}

function loadPreviousManifest(): Manifest | null {
  if (!existsSync(MANIFEST_OUT)) return null;
  try {
    return JSON.parse(readFileSync(MANIFEST_OUT, "utf8")) as Manifest;
  } catch {
    return null;
  }
}

function getVersion(): string {
  return readFileSync(VERSION_FILE, "utf8").trim();
}

function sha256OfFile(path: string): { hex: string; size: number } {
  // Stream-hash so we don't read 700 MB into memory.
  const buf = readFileSync(path);
  const hex = createHash("sha256").update(buf).digest("hex");
  return { hex, size: buf.length };
}

function formatBytes(n: number): string {
  return `${(n / 1024 / 1024).toFixed(1)} MB`;
}

/**
 * Plan = enumerate every (pack, platform) cell we'd build under the current
 * filter. Universal packs build once with platform=null.
 */
function planBuilds(cfg: PacksFile, filter: Set<string> | null): { pack: PackConfig; platform: string | null }[] {
  const out: { pack: PackConfig; platform: string | null }[] = [];
  for (const pack of cfg.packs) {
    if (filter && !filter.has(pack.name)) continue;
    if (pack.per_platform) {
      for (const platform of cfg.platforms) {
        out.push({ pack, platform });
      }
    } else {
      out.push({ pack, platform: null });
    }
  }
  return out;
}

function pckOutPath(packName: string, platform: string | null): string {
  return platform
    ? join(DIST_DIR, `${packName}-${platform}.pck`)
    : join(DIST_DIR, `${packName}.pck`);
}

function buildOne(pack: PackConfig, platform: string | null): BuildOutput {
  const out = pckOutPath(pack.name, platform);
  // For universal packs, platform doesn't matter (no multi-variant content
  // to transform), but the GDScript builder requires the flag — pass any
  // platform; linux-x86_64 is the cheapest default.
  const targetPlatform = platform ?? "linux-x86_64";
  const includeArgs = pack.include.map((p) => `"${p}"`).join(" ");
  const cmd = [
    "godot --headless --script",
    BUILD_SCRIPT,
    "--",
    "--pack", pack.name,
    "--platform", targetPlatform,
    "--include", includeArgs,
    "--out", out,
  ].join(" ");
  console.log(`\n→ Building ${pack.name}${platform ? ` (${platform})` : " (universal)"}`);
  console.log(`  ${cmd}`);
  execSync(cmd, { cwd: REPO_ROOT, stdio: "inherit" });
  if (!existsSync(out)) {
    throw new Error(`Builder claimed success but ${out} doesn't exist`);
  }
  const { hex, size } = sha256OfFile(out);
  return { packName: pack.name, platform, pckPath: out, sha256: hex, size };
}

function previousEntryFor(prev: Manifest | null, packName: string, platform: string | null): { sha256: string; urls: string[] } | null {
  if (!prev) return null;
  const p = prev.packs.find((x) => x.name === packName);
  if (!p) return null;
  if (platform) {
    const e = p.platforms?.[platform];
    return e ? { sha256: e.sha256, urls: e.urls } : null;
  }
  if (p.sha256 && p.urls) return { sha256: p.sha256, urls: p.urls };
  return null;
}

function r2KeyFor(packName: string, platform: string | null, sha256: string): string {
  const shortSha = sha256.slice(0, 12);
  return platform
    ? `packs/${packName}/${packName}-${platform}-${shortSha}.pck`
    : `packs/${packName}/${packName}-${shortSha}.pck`;
}

function buildKey(packName: string, platform: string | null): string {
  return `${packName}\u0000${platform ?? ""}`;
}

/**
 * Walk every entry in the previous manifest (both flat and per-platform)
 * and populate `cache` with sha256 → Arweave URLs. Lets subsequent runs
 * skip re-uploading packs whose bytes haven't changed.
 */
function seedArweaveCache(prev: Manifest | null, cache: Map<string, string[]>): void {
  if (!prev) return;
  for (const p of prev.packs) {
    const entries: Array<{ sha256?: string; urls?: string[] }> = [];
    if (p.platforms) {
      for (const e of Object.values(p.platforms)) entries.push(e);
    } else {
      entries.push(p);
    }
    for (const e of entries) {
      if (!e.sha256 || !e.urls) continue;
      const arweave = e.urls.filter((u) => ARWEAVE_URL_RE.test(u));
      if (arweave.length === 0) continue;
      // First sha wins; byte-identical entries share the same tx anyway.
      if (!cache.has(e.sha256)) cache.set(e.sha256, arweave);
    }
  }
}

/**
 * Produce the final urls[] for one (pack, platform) cell: R2 first (skip
 * upload if the specific prev entry matches sha), then Arweave (skip if
 * the sha is in the cross-pack cache, otherwise upload + cache).
 */
async function publishPack(
  b: BuildOutput,
  prev: Manifest | null,
  r2: ReturnType<typeof loadR2Config>,
  wallet: ReturnType<typeof loadWallet> | null,
  arweaveCache: Map<string, string[]>,
  args: CliArgs,
  version: string,
): Promise<string[]> {
  const label = `${b.packName}${b.platform ? `/${b.platform}` : ""}`;
  const urls: string[] = [];

  // R2 — keyed per (pack, platform, sha). Don't dedup by sha: storage cost
  // is trivial and per-platform keys keep the manifest URLs self-describing.
  if (r2) {
    const prevEntry = previousEntryFor(prev, b.packName, b.platform);
    const prevR2 = (prevEntry?.urls ?? []).find((u) => R2_URL_RE.test(u));
    if (prevEntry?.sha256 === b.sha256 && prevR2) {
      console.log(`  = ${label}: R2 unchanged (sha=${b.sha256.slice(0, 12)})`);
      urls.push(prevR2);
    } else {
      const key = r2KeyFor(b.packName, b.platform, b.sha256);
      console.log(`  → ${label}: uploading ${formatBytes(b.size)} → r2://${r2.bucket}/${key}`);
      const url = await uploadFileToR2(b.pckPath, key, "application/octet-stream", r2, throttledProgress(label));
      urls.push(url);
    }
  } else {
    // --skip-r2: preserve existing R2 URL if sha matches.
    const prevEntry = previousEntryFor(prev, b.packName, b.platform);
    if (prevEntry?.sha256 === b.sha256) {
      const prevR2 = (prevEntry.urls ?? []).find((u) => R2_URL_RE.test(u));
      if (prevR2) urls.push(prevR2);
    }
  }

  // Arweave — dedup across packs by sha. If sha is already in cache (either
  // from prev manifest or from an earlier upload this run), reuse URLs verbatim.
  if (wallet) {
    if (arweaveCache.has(b.sha256)) {
      console.log(`  = ${label}: Arweave reused (sha=${b.sha256.slice(0, 12)})`);
      urls.push(...arweaveCache.get(b.sha256)!);
    } else {
      console.log(`  → ${label}: uploading ${formatBytes(b.size)} to Arweave...`);
      const result = await uploadFileToArweave(
        b.pckPath,
        "application/octet-stream",
        wallet,
        [
          { name: "App-Name", value: "psz-godot" },
          { name: "App-Version", value: version },
          { name: "Pack-Name", value: b.packName },
          { name: "Pack-Platform", value: b.platform ?? "universal" },
          { name: "Pack-SHA256", value: b.sha256 },
        ],
      );
      console.log(`    tx: ${result.id}`);
      arweaveCache.set(b.sha256, result.urls);
      urls.push(...result.urls);
    }
  } else if (arweaveCache.has(b.sha256)) {
    // --skip-arweave: preserve existing Arweave URLs.
    urls.push(...arweaveCache.get(b.sha256)!);
  }

  return urls;
}

async function main(): Promise<void> {
  const args = parseArgs();
  const cfg = loadPacksConfig();
  const prev = loadPreviousManifest();
  const plan = planBuilds(cfg, args.packsFilter);

  console.log(`Plan: ${plan.length} pack build(s)`);
  for (const { pack, platform } of plan) {
    console.log(`  - ${pack.name}${platform ? ` (${platform})` : " (universal)"}`);
  }
  if (args.dryRun) {
    console.log("\n--dry-run: stopping before build/upload.");
    return;
  }

  // 1. Build (or reuse)
  const built: BuildOutput[] = [];
  for (const { pack, platform } of plan) {
    const out = pckOutPath(pack.name, platform);
    if (args.skipBuild && existsSync(out)) {
      const { hex, size } = sha256OfFile(out);
      console.log(`\n• Reusing ${out} (${formatBytes(size)}, sha=${hex.slice(0, 12)})`);
      built.push({ packName: pack.name, platform, pckPath: out, sha256: hex, size });
    } else {
      built.push(buildOne(pack, platform));
    }
  }

  // 2. Set up targets + sha-indexed URL caches populated from the previous
  // manifest. The Arweave cache dedupes across byte-identical packs (e.g.
  // world/linux-x86_64 + world/windows-x86_64 + world/macos all share the
  // same s3tc-only bytes → one Arweave tx, three manifest entries).
  const r2 = args.skipR2 ? null : loadR2Config();
  if (!args.skipR2 && !r2) {
    console.error("\n✗ R2 not configured (set R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_S3_ENDPOINT, CLOUDFLARE_R2_BUCKET, CLOUDFLARE_R2_PUBLIC_URL in .env)");
    process.exit(2);
  }

  const arweaveUrlsBySha = new Map<string, string[]>();
  seedArweaveCache(prev, arweaveUrlsBySha);

  // 3. Arweave cost estimate + confirmation. Only count packs whose sha is
  // absent from the cache (i.e. genuinely new bytes we'd be paying to upload).
  let wallet: ReturnType<typeof loadWallet> | null = null;
  if (!args.skipArweave) {
    wallet = loadWallet();
    const turbo = createTurbo(wallet);
    const balance = await getBalanceWinc(turbo);

    const needArweave = new Map<string, number>(); // sha → size
    for (const b of built) {
      if (!arweaveUrlsBySha.has(b.sha256)) needArweave.set(b.sha256, b.size);
    }
    let totalWinc = 0n;
    for (const size of needArweave.values()) {
      const est = await estimateCost(turbo, size);
      totalWinc += BigInt(est.winc);
    }
    const totalSize = [...needArweave.values()].reduce((a, b) => a + b, 0);
    const reuseCount = built.length - needArweave.size;
    console.log(`\n→ Arweave plan:`);
    console.log(`  unique new shas to upload: ${needArweave.size} (${formatBytes(totalSize)})`);
    console.log(`  reused from prev manifest or dedup: ${reuseCount}`);
    console.log(`  estimated cost: ${wincToAr(totalWinc)} AR-equiv`);
    console.log(`  current balance: ${wincToAr(balance)} AR-equiv`);
    if (BigInt(balance) < totalWinc) {
      console.error("\n✗ Insufficient Turbo credits. Top up at https://turbo-topup.com");
      process.exit(2);
    }
    if (needArweave.size > 0 && !args.yes) {
      const ok = await confirm(`\nProceed with Arweave upload (${wincToAr(totalWinc)} AR-equiv for ${needArweave.size} pack(s))?`);
      if (!ok) { console.log("aborted."); return; }
    }
  }

  // 4. Build + assemble each manifest entry.
  const newPacks: ManifestPack[] = [];
  const buildIndex = new Map<string, BuildOutput>();
  for (const b of built) buildIndex.set(buildKey(b.packName, b.platform), b);
  const version = getVersion();

  for (const pack of cfg.packs) {
    if (pack.per_platform) {
      const platforms: Record<string, ManifestPackPlatformEntry> = {};
      for (const platform of cfg.platforms) {
        const b = buildIndex.get(buildKey(pack.name, platform));
        if (b) {
          const urls = await publishPack(b, prev, r2, wallet, arweaveUrlsBySha, args, version);
          platforms[platform] = { sha256: b.sha256, size: b.size, urls };
        } else {
          const prevEntry = previousEntryFor(prev, pack.name, platform);
          if (!prevEntry) throw new Error(`No previous entry for ${pack.name}/${platform} and not in current build`);
          platforms[platform] = { sha256: prevEntry.sha256, size: 0, urls: prevEntry.urls };
        }
      }
      newPacks.push({ name: pack.name, platforms });
    } else {
      const b = buildIndex.get(buildKey(pack.name, null));
      if (b) {
        const urls = await publishPack(b, prev, r2, wallet, arweaveUrlsBySha, args, version);
        newPacks.push({ name: pack.name, sha256: b.sha256, size: b.size, urls });
      } else {
        const prevEntry = previousEntryFor(prev, pack.name, null);
        if (!prevEntry) throw new Error(`No previous entry for ${pack.name} and not in current build`);
        newPacks.push({ name: pack.name, sha256: prevEntry.sha256, size: 0, urls: prevEntry.urls });
      }
    }
  }

  // 3. Write manifest — only if every entry has at least one URL. Otherwise
  // we'd corrupt the manifest (e.g. a --skip-r2 first-time run produces
  // empty urls). Local builds with --skip-r2 print the would-be sha+size for
  // each pack so the user can manually decide what to do.
  const manifest: Manifest = {
    version: getVersion(),
    godot_version: GODOT_VERSION,
    packs: newPacks,
  };
  const incomplete = collectIncomplete(manifest);
  if (incomplete.length > 0) {
    console.log(`\n⚠ Skipping manifest write: ${incomplete.length} entry/entries have no URL:`);
    for (const e of incomplete) console.log(`    - ${e}`);
    console.log("(Run without --skip-r2 to upload + populate urls.)");
    return;
  }
  writeFileSync(MANIFEST_OUT, JSON.stringify(manifest, null, 2) + "\n");
  console.log(`\n→ Wrote ${MANIFEST_OUT}`);
  console.log("Next: git diff assets_manifest.json && git commit");
}

function collectIncomplete(m: Manifest): string[] {
  const out: string[] = [];
  for (const p of m.packs) {
    if (p.platforms) {
      for (const [plat, e] of Object.entries(p.platforms)) {
        if (!e.urls || e.urls.length === 0) out.push(`${p.name}/${plat}`);
      }
    } else if (!p.urls || p.urls.length === 0) {
      out.push(p.name);
    }
  }
  return out;
}

function throttledProgress(label: string): (loaded: number, total: number | undefined) => void {
  let last = 0;
  return (loaded, total) => {
    const now = Date.now();
    if (now - last < 5000 && (!total || loaded < total)) return;
    last = now;
    const pct = total ? ` (${((loaded / total) * 100).toFixed(1)}%)` : "";
    console.log(`    ${label}: ${(loaded / 1024 / 1024).toFixed(1)} MB${pct}`);
  };
}

main().catch((err) => {
  console.error("\n✗ Publish failed:", err);
  process.exit(1);
});
