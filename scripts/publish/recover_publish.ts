// Recovery script for the Turbo SDK chunked-upload-without-tx-id failure mode.
//
// When `npm run upload-pack` charges credits but the SDK returns `{}` instead
// of `{ id }`, the bytes ARE on Arweave but the publish script has no tx id
// to write to the manifest. This recovery flow:
//   1. Caller provides the pack tx id (looked up by Pack-SHA256 tag on
//      arweave.net/graphql once the bundler propagates).
//   2. Recompute pack sha + size from dist/assets.pck.
//   3. Build the sidecar JSON locally and upload it (small, doesn't hit the
//      chunked-upload bug).
//   4. Write assets_manifest.json with both URL sets.
//
//   npm run recover-publish -- --pack-tx <txid>

import "./lib/env.js";
import { readFileSync, writeFileSync, existsSync } from "fs";
import { createHash } from "crypto";
import { resolve, dirname, join } from "path";
import { fileURLToPath } from "url";
import { loadWallet } from "./lib/wallet.js";
import { uploadFileToArweave } from "./lib/ardrive.js";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const REPO_ROOT = resolve(__dirname, "../..");

const MANIFEST_OUT = resolve(REPO_ROOT, "assets_manifest.json");
const VERSION_FILE = resolve(REPO_ROOT, "VERSION");
const DIST_DIR = resolve(REPO_ROOT, "dist");
const PCK_OUT = join(DIST_DIR, "assets.pck");
const SIDECAR_OUT = join(DIST_DIR, "pack.manifest.json");

const GODOT_VERSION = "4.5";

function gatewayUrls(txId: string): string[] {
  return [
    `https://arweave.net/${txId}`,
    `https://ar-io.dev/${txId}`,
    `https://permagate.io/${txId}`,
  ];
}

function parsePackTx(): string {
  const i = process.argv.indexOf("--pack-tx");
  const id = i >= 0 ? process.argv[i + 1] : "";
  if (!id || id.length < 30) throw new Error("Missing or invalid --pack-tx <txid>");
  return id;
}

async function main() {
  const packTx = parsePackTx();
  if (!existsSync(PCK_OUT)) throw new Error(`${PCK_OUT} missing — rebuild first`);

  const buf = readFileSync(PCK_OUT);
  const sha256 = createHash("sha256").update(buf).digest("hex");
  const size = buf.length;
  const version = readFileSync(VERSION_FILE, "utf8").trim();

  console.log(`pack: sha=${sha256.slice(0, 12)} size=${size} version=${version}`);
  console.log(`pack tx: ${packTx}`);

  const packUrls = gatewayUrls(packTx);

  // Sidecar
  const sidecar = {
    version,
    godot_version: GODOT_VERSION,
    pack: { sha256, size, urls: packUrls },
  };
  writeFileSync(SIDECAR_OUT, JSON.stringify(sidecar, null, 2) + "\n");

  console.log(`\n→ Uploading sidecar (${Buffer.byteLength(JSON.stringify(sidecar))} B)...`);
  const wallet = loadWallet();
  const sidecarRes = await uploadFileToArweave(
    SIDECAR_OUT,
    "application/json",
    wallet,
    [
      { name: "App-Name", value: "psz-godot" },
      { name: "App-Version", value: version },
      { name: "Pack-Name", value: "assets" },
      { name: "Pack-SHA256", value: sha256 },
      { name: "Sidecar-Of", value: "assets_manifest.json" },
    ],
  );
  console.log(`  sidecar tx: ${sidecarRes.id}`);

  // Manifest
  const manifest = {
    version,
    godot_version: GODOT_VERSION,
    pack: { sha256, size, urls: packUrls },
    sidecar: { urls: sidecarRes.urls },
  };
  writeFileSync(MANIFEST_OUT, JSON.stringify(manifest, null, 2) + "\n");
  console.log(`\n→ Wrote ${MANIFEST_OUT}`);
}

main().catch((e) => { console.error("recover-publish failed:", e); process.exit(1); });
