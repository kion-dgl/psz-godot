// One-off cleanup: delete every object in psz-godot-assets EXCEPT those under
// `assets/`. We're retiring the old per-category pack layout + a stray
// assets_tree.json sitting at the bucket root, and consolidating on a single
// `packs/assets-<sha>.pck` key written by publish_assets.ts.
//
//   cd scripts/publish && npx tsx cleanup_r2.ts --dry-run
//   cd scripts/publish && npx tsx cleanup_r2.ts --yes

import "./lib/env.js";
import { ListObjectsV2Command, DeleteObjectsCommand, S3Client } from "@aws-sdk/client-s3";
import { NodeHttpHandler } from "@smithy/node-http-handler";
import { Agent as HttpsAgent } from "https";
import { loadR2Config } from "./lib/r2.js";
import { createInterface } from "readline/promises";
import { stdin as input, stdout as output } from "process";

const KEEP_PREFIX = "assets/";

async function main() {
  const cfg = loadR2Config();
  if (!cfg) {
    console.error("R2 not configured in .env");
    process.exit(2);
  }
  const dryRun = process.argv.includes("--dry-run");
  const yes = process.argv.includes("--yes") || process.argv.includes("-y");

  const client = new S3Client({
    region: "auto",
    endpoint: cfg.endpoint,
    credentials: { accessKeyId: cfg.accessKeyId, secretAccessKey: cfg.secretAccessKey },
    requestHandler: new NodeHttpHandler({
      httpsAgent: new HttpsAgent({ keepAlive: true, family: 4 }),
    }),
  });

  const toDelete: string[] = [];
  let continuationToken: string | undefined;
  do {
    const res = await client.send(new ListObjectsV2Command({
      Bucket: cfg.bucket,
      ContinuationToken: continuationToken,
    }));
    for (const obj of res.Contents ?? []) {
      if (!obj.Key) continue;
      if (obj.Key.startsWith(KEEP_PREFIX)) continue;
      toDelete.push(obj.Key);
    }
    continuationToken = res.NextContinuationToken;
  } while (continuationToken);

  console.log(`Found ${toDelete.length} object(s) outside ${KEEP_PREFIX}`);
  for (const k of toDelete.slice(0, 20)) console.log(`  - ${k}`);
  if (toDelete.length > 20) console.log(`  ... and ${toDelete.length - 20} more`);

  if (dryRun) {
    console.log("--dry-run: not deleting.");
    return;
  }
  if (toDelete.length === 0) {
    console.log("nothing to delete.");
    return;
  }
  if (!yes) {
    const rl = createInterface({ input, output });
    const answer = (await rl.question(`\nDelete these ${toDelete.length} objects? [y/N] `)).trim().toLowerCase();
    rl.close();
    if (answer !== "y" && answer !== "yes") {
      console.log("aborted.");
      return;
    }
  }

  // DeleteObjects accepts up to 1000 keys per call.
  for (let i = 0; i < toDelete.length; i += 1000) {
    const batch = toDelete.slice(i, i + 1000);
    const res = await client.send(new DeleteObjectsCommand({
      Bucket: cfg.bucket,
      Delete: { Objects: batch.map((Key) => ({ Key })), Quiet: true },
    }));
    console.log(`  deleted batch ${i / 1000 + 1}: ${batch.length} keys${res.Errors?.length ? ` (${res.Errors.length} errors)` : ""}`);
    if (res.Errors?.length) {
      for (const e of res.Errors) console.error(`    ! ${e.Key}: ${e.Message}`);
    }
  }
  console.log("done.");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
