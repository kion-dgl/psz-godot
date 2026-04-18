// Sanity check: upload a tiny text file to Arweave to confirm the wallet +
// Turbo SDK setup works before we try the 367 MB asset pack.
//
//   cd scripts/publish && npm install
//   npm run hello

import "./lib/env.js";
import { loadWallet } from "./lib/wallet.js";
import { uploadToArweave } from "./lib/ardrive.js";

async function main(): Promise<void> {
  const wallet = loadWallet();
  const stamp = new Date().toISOString();
  const data = new TextEncoder().encode(
    `hello world from psz-godot (${stamp})\n`,
  );

  console.log(`Uploading ${data.byteLength} bytes...`);
  const result = await uploadToArweave(data, "text/plain", wallet);
  console.log("OK");
  console.log(`  tx id: ${result.id}`);
  console.log(`  url:   ${result.url}`);
}

main().catch((err) => {
  console.error("Upload failed:", err);
  process.exit(1);
});
