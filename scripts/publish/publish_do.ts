// Publish the asset pack to the self-hosted DigitalOcean pack host
// (pck.psz.onl) instead of Arweave — fast iteration without the Arweave
// round-trip. DO is the DEV host; tagged releases still use `npm run
// upload-pack` (Arweave) for permanent/decentralized hosting. See CLAUDE.md
// "Asset pack publishing".
//
//   npm run upload-pack-do                  # build pack, rsync to DO, rewrite manifest
//   npm run upload-pack-do -- --skip-build  # reuse an existing dist/assets.pck
//   npm run upload-pack-do -- --dry-run     # plan only, no upload / no manifest write
//
// Config via env (.env); defaults target the current droplet:
//   DO_PACK_SSH   = root@159.223.133.93   # ssh target rsync/ssh use
//   DO_PACK_DIR   = /srv/packs            # remote dir Caddy serves
//   DO_PACK_BASE  = https://pck.psz.onl   # public base URL (Caddy auto-HTTPS)
//   DO_PACK_KEEP  = 15                    # how many packs to retain on rotate
//
// Packs are content-addressed: served at <BASE>/<sha256>.pck with a sidecar at
// <BASE>/<sha256>.sidecar.json. The bootstrap verifies sha256 after download,
// and CI verify-assets range-probes the URL + checks the sidecar — both work
// against this host (Caddy serves HTTP range requests as 206).

import { execSync } from "child_process";
import { createHash } from "crypto";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "fs";
import { dirname, join, resolve } from "path";
import { fileURLToPath } from "url";
import { config as loadEnv } from "dotenv";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const REPO_ROOT = resolve(__dirname, "../..");
loadEnv({ path: resolve(__dirname, ".env") });

const MANIFEST_OUT = resolve(REPO_ROOT, "assets_manifest.json");
const ASSET_TREE_OUT = resolve(REPO_ROOT, "asset_tree.txt");
const VERSION_FILE = resolve(REPO_ROOT, "VERSION");
const DIST_DIR = resolve(REPO_ROOT, "dist");
const PCK_OUT = join(DIST_DIR, "assets.pck");

const GODOT_VERSION = "4.5";
const PRESET_NAME = "Asset Pack";
// Kept in sync with publish_assets.ts (the Arweave flow).
const ASSET_DIRS = [
  "assets/enemies", "assets/fonts", "assets/hud", "assets/icons", "assets/images",
  "assets/mags", "assets/music", "assets/npcs", "assets/objects", "assets/player",
  "assets/sfx", "assets/stages", "assets/title", "assets/weapons",
];

const SSH = process.env.DO_PACK_SSH ?? "root@159.223.133.93";
const REMOTE_DIR = process.env.DO_PACK_DIR ?? "/srv/packs";
const BASE_URL = (process.env.DO_PACK_BASE ?? "https://pck.psz.onl").replace(/\/$/, "");
const KEEP = process.env.DO_PACK_KEEP ?? "15";

interface Args { skipBuild: boolean; dryRun: boolean; }

function parseArgs(): Args {
  const a = process.argv.slice(2);
  return { skipBuild: a.includes("--skip-build"), dryRun: a.includes("--dry-run") };
}

function getVersion(): string {
  return readFileSync(VERSION_FILE, "utf8").trim();
}

function sha256OfFile(path: string): { hex: string; size: number } {
  const buf = readFileSync(path);
  return { hex: createHash("sha256").update(buf).digest("hex"), size: buf.length };
}

function formatBytes(n: number): string {
  return n >= 1 << 20 ? `${(n / (1 << 20)).toFixed(1)} MB` : `${n} bytes`;
}

function buildPack(): { hex: string; size: number } {
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

// Mirrors publish_assets.ts: CI's check-asset-refs diffs this against the
// res://assets/... references in source, so it must be regenerated on publish.
function writeAssetTree(): void {
  const lines: string[] = [];
  for (const dir of ASSET_DIRS) {
    if (!existsSync(join(REPO_ROOT, dir))) {
      console.warn(`⚠ missing asset dir ${dir} — will be empty in the pack`);
      continue;
    }
    const raw = execSync(`find "${dir}" -type f -not -name "*.md5" -not -name "*.import" | sort`, {
      cwd: REPO_ROOT,
      encoding: "utf8",
    });
    for (const l of raw.split("\n")) if (l.trim()) lines.push(l.trim());
  }
  writeFileSync(ASSET_TREE_OUT, lines.join("\n") + "\n");
  console.log(`→ Wrote ${ASSET_TREE_OUT} (${lines.length} files)`);
}

function sh(cmd: string): void {
  console.log(`  $ ${cmd}`);
  execSync(cmd, { stdio: "inherit" });
}

async function main(): Promise<void> {
  const args = parseArgs();
  const version = getVersion();
  console.log(`psz-godot → DO pack host ${BASE_URL} (ssh ${SSH}:${REMOTE_DIR}), version ${version}`);

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

  const packName = `${sha256}.pck`;
  const sidecarName = `${sha256}.sidecar.json`;
  const packUrl = `${BASE_URL}/${packName}`;
  const sidecarUrl = `${BASE_URL}/${sidecarName}`;

  // Sidecar: same shape verify-assets validates (its version/sha256/size MUST
  // match the in-repo manifest we write below).
  const sidecar = { version, godot_version: GODOT_VERSION, pack: { sha256, size, urls: [packUrl] } };
  const sidecarPath = join(DIST_DIR, sidecarName);
  writeFileSync(sidecarPath, JSON.stringify(sidecar, null, 2) + "\n");

  if (args.dryRun) {
    console.log(`\n[dry-run] rsync ${PCK_OUT} → ${SSH}:${REMOTE_DIR}/${packName}`);
    console.log(`[dry-run] rsync ${sidecarPath} → ${SSH}:${REMOTE_DIR}/${sidecarName}`);
    console.log(`[dry-run] prune remote to newest ${KEEP}`);
    console.log(`[dry-run] write ${MANIFEST_OUT} → pack.urls=[${packUrl}]`);
    return;
  }

  // Upload (rsync = resumable, only sends changed bytes).
  console.log(`\n→ Uploading pack + sidecar to ${SSH}:${REMOTE_DIR}`);
  sh(`rsync -av --progress -e ssh "${PCK_OUT}" "${SSH}:${REMOTE_DIR}/${packName}"`);
  sh(`rsync -av -e ssh "${sidecarPath}" "${SSH}:${REMOTE_DIR}/${sidecarName}"`);

  // Guard: confirm the host serves the pack's GDPC magic over a range request
  // (the same thing CI verify-assets probes) BEFORE rewriting the manifest, so
  // we never commit a manifest pointing at an unreachable pack.
  console.log(`\n→ Verifying ${packUrl}`);
  let magic = "";
  try {
    magic = execSync(`curl -fsS -H 'Range: bytes=0-3' "${packUrl}"`, { encoding: "utf8" });
  } catch (e) {
    throw new Error(`could not fetch ${packUrl} (DNS/cert not ready yet?) — manifest NOT written. ${e}`);
  }
  if (!magic.startsWith("GDPC")) {
    throw new Error(`${packUrl} did not serve GDPC magic (got ${JSON.stringify(magic.slice(0, 8))}) — manifest NOT written`);
  }
  console.log(`  ok: GDPC magic served`);

  // Rotate old packs (server cron also does this daily; this keeps it tidy now).
  sh(`ssh ${SSH} '/usr/local/bin/prune-packs.sh ${KEEP}'`);

  const manifest = {
    version,
    godot_version: GODOT_VERSION,
    pack: { sha256, size, urls: [packUrl] },
    sidecar: { urls: [sidecarUrl] },
  };
  writeFileSync(MANIFEST_OUT, JSON.stringify(manifest, null, 2) + "\n");
  console.log(`\n→ Wrote ${MANIFEST_OUT} (pointing at DO)`);
  console.log("Next: git add assets_manifest.json asset_tree.txt && git commit");
}

main().catch((err) => {
  console.error("\n✗ DO publish failed:", err);
  process.exit(1);
});
