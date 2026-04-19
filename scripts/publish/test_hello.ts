// Sanity check: upload a tiny text file to Arweave to confirm the wallet +
// Turbo SDK setup works before we try the 367 MB asset pack.
//
//   cd scripts/publish && npm install
//   npm run hello

import "./lib/env.js";
import { writeFileSync, unlinkSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { loadWallet } from "./lib/wallet.js";
import { uploadFileToArweave } from "./lib/ardrive.js";

async function main(): Promise<void> {
  const wallet = loadWallet();
  const stamp = new Date().toISOString();
  const tmp = join(tmpdir(), `psz-hello-${Date.now()}.txt`);
  writeFileSync(tmp, `hello world from psz-godot (${stamp})\n`);

  console.log(`Uploading ${tmp}...`);
  try {
    const result = await uploadFileToArweave(tmp, "text/plain", wallet);
    console.log("OK");
    console.log(`  tx id: ${result.id}`);
    console.log(`  urls:  ${result.urls.join(", ")}`);
  } finally {
    unlinkSync(tmp);
  }
}

main().catch((err) => {
  console.error("Upload failed:", err);
  process.exit(1);
});
