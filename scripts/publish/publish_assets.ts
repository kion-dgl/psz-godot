// Build ONE universal asset pack via Godot's --export-pack, upload it to
// Arweave, and rewrite assets_manifest.json.
//
// Why Arweave-only: Godot's bundled mbedtls cannot handshake with
// Cloudflare's R2 dev URL TLS edge (closed #154), so the runtime would
// always fall through to Arweave anyway. Uploading the pack to R2 each
// publish was burning storage for URLs nobody could reach. R2 stays in
// use for per-file dev asset sync via scripts/tools/fetch_assets_dev.sh
// and the web storybook's VITE_ASSETS_BASE — that path doesn't go
// through Godot's mbedtls.
//
// Why one pack for all platforms: desktop x86 builds (Linux/Windows/macOS)
// all ship s3tc-compressed textures with byte-identical pack output; Android
// ships etc2. Shipping both variants in one ~500 MB pack costs less on
// Arweave than uploading 3× ~350 MB near-duplicates, and the runtime just
// picks whichever variant its GPU supports.
//
//   cd scripts/publish && npm install                # first time
//   npm run upload-pack                              # build + Arweave
//   npm run upload-pack -- --skip-build              # reuse existing dist/assets.pck
//   npm run upload-pack -- --skip-arweave            # no Arweave upload this run
//   npm run upload-pack -- --dry-run                 # plan only, no work
//   npm run upload-pack -- --yes                     # skip cost confirmation prompt

import "./lib/env.js";
import { execSync } from "child_process";
import { readFileSync, writeFileSync, existsSync, mkdirSync, statSync } from "fs";
import { createHash } from "crypto";
import { resolve, dirname, join } from "path";
import { fileURLToPath } from "url";
import { createInterface } from "readline/promises";
import { stdin as input, stdout as output } from "process";
import { loadWallet } from "./lib/wallet.js";
import { createTurbo, estimateCost, getBalanceWinc, uploadFileToArweave } from "./lib/ardrive.js";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const REPO_ROOT = resolve(__dirname, "../..");

const MANIFEST_OUT = resolve(REPO_ROOT, "assets_manifest.json");
const ASSET_TREE_OUT = resolve(REPO_ROOT, "asset_tree.txt");
const VERSION_FILE = resolve(REPO_ROOT, "VERSION");
const DIST_DIR = resolve(REPO_ROOT, "dist");
const PCK_OUT = join(DIST_DIR, "assets.pck");
const SIDECAR_OUT = join(DIST_DIR, "pack.manifest.json");

const GODOT_VERSION = "4.5";
const PRESET_NAME = "Asset Pack";

// Asset dirs that ship in the pack (i.e. NOT bundled with the main exe).
// Must match the exclude_filter on every binary preset in export_presets.cfg
// and the exclude_filter inverse on the "Asset Pack" preset. Kenney CC0 packs
// live in-repo and ride along in the main exe, so they're excluded here.
const ASSET_DIRS = [
  "assets/enemies",
  "assets/fonts",
  "assets/hud",
  "assets/icons",
  "assets/images",
  "assets/mags",
  "assets/music",
  "assets/npcs",
  "assets/objects",
  "assets/player",
  "assets/sfx",
  "assets/stages",
  "assets/title",
  "assets/weapons",
];

const ARWEAVE_URL_RE = /arweave\.net|ar-io\.dev|permagate\.io/;

interface CliArgs {
  skipBuild: boolean;
  skipArweave: boolean;
  dryRun: boolean;
  yes: boolean;
}

interface Manifest {
  version: string;
  godot_version: string;
  pack: {
    sha256: string;
    size: number;
    urls: string[];
  };
  sidecar?: {
    urls: string[];
  };
}

function parseArgs(): CliArgs {
  const args = process.argv.slice(2);
  return {
    skipBuild: args.includes("--skip-build"),
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

function loadPreviousManifest(): Manifest | null {
  if (!existsSync(MANIFEST_OUT)) return null;
  try {
    const raw = JSON.parse(readFileSync(MANIFEST_OUT, "utf8"));
    // Only return it if it has the new single-pack shape. Old multi-pack
    // manifests are ignored (fresh upload, but prev-Arweave URL reuse below
    // still scans them by sha).
    if (raw?.pack?.sha256) return raw as Manifest;
    return null;
  } catch {
    return null;
  }
}

/**
 * Walk every previous-manifest shape (single-pack new format, multi-pack old
 * format with optional per-platform branches) and index every Arweave URL by
 * sha256. Lets a re-publish reuse an existing Arweave tx when pack bytes
 * haven't changed — we don't pay twice for the same content.
 */
function seedArweaveCache(): Map<string, string[]> {
  const cache = new Map<string, string[]>();
  if (!existsSync(MANIFEST_OUT)) return cache;
  let raw: unknown;
  try { raw = JSON.parse(readFileSync(MANIFEST_OUT, "utf8")); } catch { return cache; }
  const entries: Array<{ sha256?: string; urls?: string[] }> = [];
  const r = raw as Record<string, unknown>;
  // New shape: { pack: { sha256, urls } }
  if (r.pack && typeof r.pack === "object") {
    entries.push(r.pack as { sha256?: string; urls?: string[] });
  }
  // Old shape: { packs: [{ sha256?, urls?, platforms? }] }
  if (Array.isArray(r.packs)) {
    for (const p of r.packs as Array<Record<string, unknown>>) {
      if (p.sha256 && p.urls) entries.push(p as { sha256?: string; urls?: string[] });
      if (p.platforms && typeof p.platforms === "object") {
        for (const e of Object.values(p.platforms as Record<string, unknown>)) {
          entries.push(e as { sha256?: string; urls?: string[] });
        }
      }
    }
  }
  for (const e of entries) {
    if (!e.sha256 || !e.urls) continue;
    const arweave = e.urls.filter((u) => ARWEAVE_URL_RE.test(u));
    if (arweave.length === 0) continue;
    if (!cache.has(e.sha256)) cache.set(e.sha256, arweave);
  }
  return cache;
}

function getVersion(): string {
  return readFileSync(VERSION_FILE, "utf8").trim();
}

function sha256OfFile(path: string): { hex: string; size: number } {
  const buf = readFileSync(path);
  const hex = createHash("sha256").update(buf).digest("hex");
  return { hex, size: buf.length };
}

function formatBytes(n: number): string {
  return `${(n / 1024 / 1024).toFixed(1)} MB`;
}

function buildPack(): { sha256: string; size: number } {
  mkdirSync(DIST_DIR, { recursive: true });
  const cmd = `godot --headless --path . --export-pack "${PRESET_NAME}" ${PCK_OUT}`;
  console.log(`\n→ Building ${PCK_OUT}`);
  console.log(`  ${cmd}`);
  execSync(cmd, { cwd: REPO_ROOT, stdio: "inherit" });
  if (!existsSync(PCK_OUT)) {
    throw new Error(`godot --export-pack claimed success but ${PCK_OUT} doesn't exist`);
  }
  return sha256OfFile(PCK_OUT);
}

/**
 * List every asset path that the published pack covers. Committed alongside
 * the manifest so CI can diff it against `res://assets/<dir>/...` string
 * references in source — a reference to a path not in this file means the
 * dev added an asset without republishing the pack.
 */
function writeAssetTree(): void {
  const lines: string[] = [];
  for (const dir of ASSET_DIRS) {
    const abs = join(REPO_ROOT, dir);
    if (!existsSync(abs)) {
      console.warn(`⚠ missing asset dir ${dir} — will be empty in the pack`);
      continue;
    }
    // Use git-style listing: everything on disk, sorted, rooted at repo.
    const raw = execSync(`find "${dir}" -type f -not -name "*.md5" -not -name "*.import" | sort`, {
      cwd: REPO_ROOT,
      encoding: "utf8",
    });
    for (const line of raw.split("\n")) {
      if (line.trim()) lines.push(line.trim());
    }
  }
  writeFileSync(ASSET_TREE_OUT, lines.join("\n") + "\n");
  console.log(`→ Wrote ${ASSET_TREE_OUT} (${lines.length} files)`);
}

async function main(): Promise<void> {
  const args = parseArgs();
  const prev = loadPreviousManifest();
  const arweaveCache = seedArweaveCache();

  console.log(`Plan: build 1 universal asset pack`);
  if (args.dryRun) {
    console.log("\n--dry-run: stopping before build/upload.");
    return;
  }

  // 1. Build (or reuse existing .pck)
  let sha256: string;
  let size: number;
  if (args.skipBuild && existsSync(PCK_OUT)) {
    ({ hex: sha256, size } = sha256OfFile(PCK_OUT));
    console.log(`\n• Reusing ${PCK_OUT} (${formatBytes(size)}, sha=${sha256.slice(0, 12)})`);
  } else {
    ({ hex: sha256, size } = buildPack());
    console.log(`  built: ${formatBytes(size)}, sha=${sha256.slice(0, 12)}`);
  }

  writeAssetTree();

  const urls: string[] = [];
  const shortSha = sha256.slice(0, 12);

  // 2. Arweave upload
  if (!args.skipArweave) {
    const wallet = loadWallet();
    const turbo = createTurbo(wallet);
    const balance = await getBalanceWinc(turbo);

    if (arweaveCache.has(sha256)) {
      console.log(`  = Arweave reused (sha=${shortSha})`);
      urls.push(...arweaveCache.get(sha256)!);
    } else {
      const est = await estimateCost(turbo, size);
      const totalWinc = BigInt(est.winc);
      console.log(`\n→ Arweave plan:`);
      console.log(`  uploading ${formatBytes(size)}`);
      console.log(`  estimated cost: ${wincToAr(totalWinc)} AR-equiv`);
      console.log(`  current balance: ${wincToAr(balance)} AR-equiv`);
      if (BigInt(balance) < totalWinc) {
        console.error("\n✗ Insufficient Turbo credits. Top up at https://turbo-topup.com");
        process.exit(2);
      }
      if (!args.yes) {
        const ok = await confirm(`\nProceed with Arweave upload (${wincToAr(totalWinc)} AR-equiv)?`);
        if (!ok) { console.log("aborted."); return; }
      }
      console.log(`  → uploading ${formatBytes(size)} to Arweave...`);
      const result = await uploadFileToArweave(
        PCK_OUT,
        "application/octet-stream",
        wallet,
        [
          { name: "App-Name", value: "psz-godot" },
          { name: "App-Version", value: getVersion() },
          { name: "Pack-Name", value: "assets" },
          { name: "Pack-SHA256", value: sha256 },
        ],
      );
      console.log(`    tx: ${result.id}`);
      urls.push(...result.urls);
    }
  } else if (arweaveCache.has(sha256)) {
    urls.push(...arweaveCache.get(sha256)!);
  }

  // 3. Sidecar manifest upload — a tiny JSON describing the pack uploaded
  //    above. CI fetches this from Arweave and cross-checks against the
  //    in-repo manifest, so a publish that bumps the manifest but doesn't
  //    actually upload the pack (or where the sidecar's metadata diverges
  //    from the in-repo manifest) fails CI. This is the integrity check
  //    that replaces re-streaming the full 264 MB pack through the Arweave
  //    gateway.
  let sidecarUrls: string[] = [];
  const prevSidecarStillValid =
    prev?.pack.sha256 === sha256 &&
    prev.version === getVersion() &&
    Array.isArray(prev.sidecar?.urls) &&
    prev!.sidecar!.urls.length > 0;
  if (prevSidecarStillValid) {
    console.log(`  = Sidecar reused (pack sha + version unchanged)`);
    sidecarUrls = [...prev!.sidecar!.urls];
  } else if (!args.skipArweave) {
    const wallet = loadWallet();
    const sidecarBody = {
      version: getVersion(),
      godot_version: GODOT_VERSION,
      pack: { sha256, size, urls: [...urls] },
    };
    writeFileSync(SIDECAR_OUT, JSON.stringify(sidecarBody, null, 2) + "\n");
    console.log(`\n→ Uploading sidecar manifest (${formatBytes(statSync(SIDECAR_OUT).size)}) to Arweave...`);
    const sidecarResult = await uploadFileToArweave(
      SIDECAR_OUT,
      "application/json",
      wallet,
      [
        { name: "App-Name", value: "psz-godot" },
        { name: "App-Version", value: getVersion() },
        { name: "Pack-Name", value: "assets" },
        { name: "Pack-SHA256", value: sha256 },
        { name: "Sidecar-Of", value: "assets_manifest.json" },
      ],
    );
    console.log(`    tx: ${sidecarResult.id}`);
    sidecarUrls = sidecarResult.urls;
  }

  // 4. Write manifest (only if we have at least one URL)
  if (urls.length === 0) {
    console.log(`\n⚠ Skipping manifest write: no URLs available.`);
    console.log(`  built pack at ${PCK_OUT} (sha=${sha256}, ${formatBytes(size)})`);
    console.log(`  (Run without --skip-arweave to upload + populate urls.)`);
    return;
  }
  const manifest: Manifest = {
    version: getVersion(),
    godot_version: GODOT_VERSION,
    pack: { sha256, size, urls },
    ...(sidecarUrls.length ? { sidecar: { urls: sidecarUrls } } : {}),
  };
  writeFileSync(MANIFEST_OUT, JSON.stringify(manifest, null, 2) + "\n");
  console.log(`\n→ Wrote ${MANIFEST_OUT}`);
  console.log("Next: git diff assets_manifest.json && git commit");
}

main().catch((err) => {
  console.error("\n✗ Publish failed:", err);
  process.exit(1);
});
