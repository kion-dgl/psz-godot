// Build the assets.pck, upload to Arweave via ArDrive Turbo, and rewrite
// assets_manifest.json with the new version / sha / url.
//
//   cd scripts/publish && npm install     # first time
//   npm run upload-pack                   # build + upload + rewrite manifest
//   npm run upload-pack -- --skip-build   # reuse existing dist/assets.pck
//   npm run upload-pack -- --dry-run      # estimate cost, don't upload
//
// Run from anywhere — paths are resolved relative to the repo root.

import "./lib/env.js";
import { execSync } from "child_process";
import { readFileSync, writeFileSync, existsSync, statSync } from "fs";
import { createHash } from "crypto";
import { resolve, dirname } from "path";
import { fileURLToPath } from "url";
import { createInterface } from "readline/promises";
import { stdin as input, stdout as output } from "process";
import { loadWallet } from "./lib/wallet.js";
import {
  createTurbo,
  estimateCost,
  getBalanceWinc,
  uploadToArweave,
} from "./lib/ardrive.js";
import { loadR2Config, uploadFileToR2 } from "./lib/r2.js";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const REPO_ROOT = resolve(__dirname, "../..");

const PACK_OUT = resolve(REPO_ROOT, "dist/assets.pck");
const MANIFEST_OUT = resolve(REPO_ROOT, "assets_manifest.json");
const VERSION_FILE = resolve(REPO_ROOT, "VERSION");

const GODOT_VERSION = "4.5";
const BUILD_CMD =
  "godot --headless --script scripts/tools/build_assets_pack.gd -- --out dist/assets.pck";

interface CliArgs {
  skipBuild: boolean;
  skipArweave: boolean;
  dryRun: boolean;
  yes: boolean;
}

function parseArgs(): CliArgs {
  const args = process.argv.slice(2);
  return {
    skipBuild: args.includes("--skip-build"),
    skipArweave: args.includes("--skip-arweave"),
    dryRun: args.includes("--dry-run"),
    yes: args.includes("-y") || args.includes("--yes"),
  };
}

function getVersion(): string {
  return readFileSync(VERSION_FILE, "utf8").trim();
}

function buildPack(): void {
  console.log(`\n→ Building pack: ${BUILD_CMD}`);
  execSync(BUILD_CMD, { cwd: REPO_ROOT, stdio: "inherit" });
}

function sha256OfFile(path: string): { hex: string; size: number } {
  const buf = readFileSync(path);
  const hex = createHash("sha256").update(buf).digest("hex");
  return { hex, size: buf.length };
}

function formatBytes(n: number): string {
  const mb = n / 1024 / 1024;
  return `${mb.toFixed(2)} MB (${n.toLocaleString()} bytes)`;
}

function wincToAr(winc: string): string {
  // 1 AR = 1e12 winston (winc is credit-winston; same scale for display)
  const winston = BigInt(winc);
  const wholeAR = Number(winston / 1_000_000_000_000n);
  const fracAR = Number(winston % 1_000_000_000_000n) / 1e12;
  return (wholeAR + fracAR).toFixed(6);
}

async function confirm(prompt: string): Promise<boolean> {
  const rl = createInterface({ input, output });
  const answer = (await rl.question(`${prompt} [y/N] `)).trim().toLowerCase();
  rl.close();
  return answer === "y" || answer === "yes";
}

async function main(): Promise<void> {
  const args = parseArgs();

  if (!args.skipBuild) buildPack();

  if (!existsSync(PACK_OUT)) {
    throw new Error(
      `Pack not found at ${PACK_OUT}. Build first, or run without --skip-build.`,
    );
  }

  const { size: fileSize } = statSync(PACK_OUT);
  console.log(`\n→ Pack: ${PACK_OUT}`);
  console.log(`  size: ${formatBytes(fileSize)}`);

  process.stdout.write("  sha256: computing... ");
  const { hex: sha256, size } = sha256OfFile(PACK_OUT);
  console.log(sha256);

  const version = getVersion();
  console.log(`  version: ${version}`);

  let arweaveResultUrls: string[] = [];

  if (!args.skipArweave) {
    const wallet = loadWallet();
    const turbo = createTurbo(wallet);

    const [balance, estimate] = await Promise.all([
      getBalanceWinc(turbo),
      estimateCost(turbo, size),
    ]);
    const costAR = wincToAr(estimate.winc);
    const balanceAR = wincToAr(balance);
    console.log(`\n→ Turbo credit balance: ${balanceAR} AR-equiv`);
    console.log(`  estimated upload cost:  ${costAR} AR-equiv`);

    if (BigInt(balance) < BigInt(estimate.winc)) {
      console.error("\n✗ Insufficient credits. Top up at https://turbo-topup.com");
      process.exit(2);
    }

    if (args.dryRun) {
      console.log("\n--dry-run — skipping upload and manifest rewrite.");
      return;
    }

    if (!args.yes) {
      const ok = await confirm(
        `\nUpload ${formatBytes(size)} to Arweave (costs ~${costAR} AR-equiv)?`,
      );
      if (!ok) {
        console.log("aborted.");
        return;
      }
    }

    console.log("\n→ Uploading to Arweave (Turbo, streaming)...");
    const arStartMs = Date.now();
    const packBytes = readFileSync(PACK_OUT);
    const result = await uploadToArweave(
      packBytes,
      "application/octet-stream",
      wallet,
      [
        { name: "App-Name", value: "psz-godot" },
        { name: "App-Version", value: version },
        { name: "Pack-Name", value: "assets" },
        { name: "Pack-SHA256", value: sha256 },
      ],
    );
    console.log(`✓ Arweave upload in ${((Date.now() - arStartMs) / 1000).toFixed(1)}s`);
    console.log(`  tx id: ${result.id}`);
    console.log(`  url:   ${result.url}`);
    const txId = result.id;
    arweaveResultUrls = [
      `https://arweave.net/${txId}`,
      `https://ar-io.dev/${txId}`,
      `https://permagate.io/${txId}`,
    ];
  } else {
    console.log("\n(skipping Arweave — --skip-arweave passed)");
    // Preserve existing Arweave URLs ONLY if the previous manifest references
    // the same pack sha256 we just built. Otherwise those URLs point at a
    // different (stale) upload and would fail sha verification; drop them so
    // the R2 URL is the sole source of truth.
    if (existsSync(MANIFEST_OUT)) {
      const prev = JSON.parse(readFileSync(MANIFEST_OUT, "utf8"));
      const prevPack = prev?.packs?.find((p: any) => p.name === "assets");
      if (prevPack?.urls && prevPack.sha256 === sha256) {
        arweaveResultUrls = prevPack.urls.filter((u: string) =>
          /arweave\.net|ar-io\.dev|permagate\.io/.test(u),
        );
      }
    }
    if (args.dryRun) {
      console.log("\n--dry-run — skipping R2 upload and manifest rewrite.");
      return;
    }
  }

  const urls: string[] = [];
  // Cloudflare R2 (listed first in the manifest — fastest primary mirror).
  const r2 = loadR2Config();
  if (r2) {
    const r2Key = `packs/assets-${sha256.slice(0, 12)}.pck`;
    console.log(`\n→ Uploading to R2 (${r2.bucket}/${r2Key})...`);
    const r2StartMs = Date.now();
    let lastLog = 0;
    const r2Url = await uploadFileToR2(
      PACK_OUT,
      r2Key,
      "application/octet-stream",
      r2,
      (loaded, total) => {
        const now = Date.now();
        if (now - lastLog > 5000) {
          lastLog = now;
          const pct = total ? ` (${((loaded / total) * 100).toFixed(1)}%)` : "";
          const mb = (loaded / 1024 / 1024).toFixed(1);
          console.log(`  ${mb} MB uploaded${pct}`);
        }
      },
    );
    console.log(`✓ R2 upload in ${((Date.now() - r2StartMs) / 1000).toFixed(1)}s`);
    console.log(`  url: ${r2Url}`);
    urls.push(r2Url);
  } else {
    console.log("\n(skipping R2 — R2_* vars not set in .env)");
  }

  // Arweave URLs (from this run, or preserved from existing manifest on --skip-arweave).
  urls.push(...arweaveResultUrls);

  const manifest = {
    version,
    godot_version: GODOT_VERSION,
    packs: [
      {
        name: "assets",
        sha256,
        size,
        urls,
      },
    ],
  };
  writeFileSync(MANIFEST_OUT, JSON.stringify(manifest, null, 2) + "\n");
  console.log(`\n→ Wrote ${MANIFEST_OUT}`);
  console.log("Next: git add assets_manifest.json && git commit");
}

main().catch((err) => {
  console.error("\n✗ Publish failed:", err);
  process.exit(1);
});
