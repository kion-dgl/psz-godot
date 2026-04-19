// Build the per-platform asset pack matrix, upload to R2, and rewrite
// assets_manifest.json. Arweave upload is intentionally not wired in this
// path — verifying R2 with releases comes first; an Arweave step can be
// added later as a separate command.
//
//   cd scripts/publish && npm install                # first time
//   npm run upload-pack                              # build + upload all packs
//   npm run upload-pack -- --packs=stages,chars      # only those packs
//   npm run upload-pack -- --skip-build              # reuse existing dist/*.pck
//   npm run upload-pack -- --skip-r2                 # build only, don't upload
//   npm run upload-pack -- --dry-run                 # plan only, no work
//
// All paths resolve relative to the repo root regardless of CWD.

import "./lib/env.js";
import { execSync } from "child_process";
import { readFileSync, writeFileSync, existsSync, statSync, readdirSync, unlinkSync } from "fs";
import { createHash } from "crypto";
import { resolve, dirname, join } from "path";
import { fileURLToPath } from "url";
import { loadR2Config, uploadFileToR2 } from "./lib/r2.js";

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
  dryRun: boolean;
}

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
    dryRun: args.includes("--dry-run"),
  };
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

  // 2. Diff against previous manifest, upload only changed packs
  const r2 = args.skipR2 ? null : loadR2Config();
  if (!args.skipR2 && !r2) {
    console.error("\n✗ R2 not configured (set R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_S3_ENDPOINT, CLOUDFLARE_R2_BUCKET, CLOUDFLARE_R2_PUBLIC_URL in scripts/publish/.env)");
    process.exit(2);
  }

  const newPacks: ManifestPack[] = [];
  // Index built outputs by (pack, platform) for assembly.
  const buildIndex = new Map<string, BuildOutput>();
  for (const b of built) {
    buildIndex.set(`${b.packName}\u0000${b.platform ?? ""}`, b);
  }

  // Walk every pack in packs.json (so the manifest stays complete even when
  // --packs filtered some). For unfiltered packs that we DIDN'T rebuild,
  // copy the previous entry verbatim — DOES require previous manifest.
  for (const pack of cfg.packs) {
    if (pack.per_platform) {
      const platforms: Record<string, ManifestPackPlatformEntry> = {};
      for (const platform of cfg.platforms) {
        const built = buildIndex.get(`${pack.name}\u0000${platform}`);
        if (built) {
          const prevEntry = previousEntryFor(prev, pack.name, platform);
          if (prevEntry && prevEntry.sha256 === built.sha256) {
            console.log(`  = ${pack.name}/${platform}: unchanged (sha=${built.sha256.slice(0, 12)}); preserving urls`);
            platforms[platform] = { sha256: built.sha256, size: built.size, urls: prevEntry.urls };
          } else if (r2) {
            const key = r2KeyFor(pack.name, platform, built.sha256);
            console.log(`  → ${pack.name}/${platform}: uploading ${formatBytes(built.size)} → r2://${r2.bucket}/${key}`);
            const url = await uploadFileToR2(built.pckPath, key, "application/octet-stream", r2,
              throttledProgress(`${pack.name}/${platform}`));
            platforms[platform] = { sha256: built.sha256, size: built.size, urls: [url] };
          } else {
            // skipR2: keep what was there (or empty if new pack)
            platforms[platform] = { sha256: built.sha256, size: built.size, urls: prevEntry?.urls ?? [] };
          }
        } else {
          // Not in this build's filter — preserve previous entry verbatim
          const prevEntry = previousEntryFor(prev, pack.name, platform);
          if (!prevEntry) {
            throw new Error(`No previous entry for ${pack.name}/${platform} and not in current build — manifest would be incomplete`);
          }
          platforms[platform] = { sha256: prevEntry.sha256, size: 0, urls: prevEntry.urls };
        }
      }
      newPacks.push({ name: pack.name, platforms });
    } else {
      const built = buildIndex.get(`${pack.name}\u0000`);
      if (built) {
        const prevEntry = previousEntryFor(prev, pack.name, null);
        if (prevEntry && prevEntry.sha256 === built.sha256) {
          console.log(`  = ${pack.name}: unchanged (sha=${built.sha256.slice(0, 12)}); preserving urls`);
          newPacks.push({ name: pack.name, sha256: built.sha256, size: built.size, urls: prevEntry.urls });
        } else if (r2) {
          const key = r2KeyFor(pack.name, null, built.sha256);
          console.log(`  → ${pack.name}: uploading ${formatBytes(built.size)} → r2://${r2.bucket}/${key}`);
          const url = await uploadFileToR2(built.pckPath, key, "application/octet-stream", r2,
            throttledProgress(pack.name));
          newPacks.push({ name: pack.name, sha256: built.sha256, size: built.size, urls: [url] });
        } else {
          newPacks.push({ name: pack.name, sha256: built.sha256, size: built.size, urls: prevEntry?.urls ?? [] });
        }
      } else {
        const prevEntry = previousEntryFor(prev, pack.name, null);
        if (!prevEntry) {
          throw new Error(`No previous entry for ${pack.name} and not in current build`);
        }
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
