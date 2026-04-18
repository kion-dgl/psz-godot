// Sync the repo's /assets/ tree to R2 as raw individual files — used by the
// web editor (each GLB fetched by URL) and by fresh-clone dev setup.
//
//   cd scripts/publish && npm install
//   npm run sync-tree                # diff + upload changed files
//   npm run sync-tree -- --delete    # also remove R2 objects not in local tree
//   npm run sync-tree -- --dry-run   # print diffs, upload nothing
//
// Differencing uses md5 (R2 ETag for simple PUTs = md5). Files already at
// the right hash are skipped, so incremental syncs are cheap.

import "./lib/env.js";
import {
  S3Client,
  ListObjectsV2Command,
  PutObjectCommand,
  DeleteObjectsCommand,
} from "@aws-sdk/client-s3";
import { NodeHttpHandler } from "@smithy/node-http-handler";
import { Agent as HttpsAgent } from "https";
import { readFile, readdir, stat } from "fs/promises";
import { createHash } from "crypto";
import { join, relative } from "path";
import { fileURLToPath } from "url";
import { dirname, resolve } from "path";
import { loadR2Config } from "./lib/r2.js";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const REPO_ROOT = resolve(__dirname, "../..");
const ASSETS_DIR = resolve(REPO_ROOT, "assets");
const R2_PREFIX = "assets/"; // object-key prefix in the bucket

interface CliArgs {
  dryRun: boolean;
  delete: boolean;
  concurrency: number;
}

function parseArgs(): CliArgs {
  const argv = process.argv.slice(2);
  const getNum = (name: string, fallback: number): number => {
    const i = argv.indexOf(name);
    if (i === -1) return fallback;
    return parseInt(argv[i + 1] ?? `${fallback}`, 10);
  };
  return {
    dryRun: argv.includes("--dry-run"),
    delete: argv.includes("--delete"),
    concurrency: getNum("--concurrency", 16),
  };
}

function contentTypeFor(path: string): string {
  const ext = path.slice(path.lastIndexOf(".")).toLowerCase();
  switch (ext) {
    case ".glb": return "model/gltf-binary";
    case ".gltf": return "model/gltf+json";
    case ".png": return "image/png";
    case ".jpg":
    case ".jpeg": return "image/jpeg";
    case ".webp": return "image/webp";
    case ".svg": return "image/svg+xml";
    case ".wav": return "audio/wav";
    case ".ogg": return "audio/ogg";
    case ".mp3": return "audio/mpeg";
    case ".json":
    case ".tres":
    case ".tscn":
    case ".import": return "text/plain; charset=utf-8";
    case ".ttf": return "font/ttf";
    case ".otf": return "font/otf";
    default: return "application/octet-stream";
  }
}

async function* walkFiles(dir: string): AsyncGenerator<string> {
  const entries = await readdir(dir, { withFileTypes: true });
  for (const e of entries) {
    const p = join(dir, e.name);
    if (e.isDirectory()) yield* walkFiles(p);
    else if (e.isFile()) yield p;
  }
}

async function md5Hex(path: string): Promise<string> {
  const buf = await readFile(path);
  return createHash("md5").update(buf).digest("hex");
}

async function listR2(
  client: S3Client,
  Bucket: string,
  Prefix: string,
): Promise<Map<string, { size: number; etag: string }>> {
  const out = new Map<string, { size: number; etag: string }>();
  let ContinuationToken: string | undefined;
  do {
    const r = await client.send(
      new ListObjectsV2Command({ Bucket, Prefix, ContinuationToken }),
    );
    for (const obj of r.Contents ?? []) {
      if (!obj.Key) continue;
      out.set(obj.Key, {
        size: Number(obj.Size ?? 0),
        etag: (obj.ETag ?? "").replace(/^"|"$/g, "").toLowerCase(),
      });
    }
    ContinuationToken = r.IsTruncated ? r.NextContinuationToken : undefined;
  } while (ContinuationToken);
  return out;
}

async function mapLimit<T, R>(
  items: T[],
  concurrency: number,
  worker: (t: T) => Promise<R>,
  onProgress?: (done: number, total: number) => void,
): Promise<R[]> {
  const results: R[] = new Array(items.length);
  let next = 0;
  let completed = 0;
  async function run(): Promise<void> {
    while (next < items.length) {
      const i = next++;
      results[i] = await worker(items[i]);
      completed++;
      if (onProgress) onProgress(completed, items.length);
    }
  }
  const pool = Array.from({ length: Math.min(concurrency, items.length) }, run);
  await Promise.all(pool);
  return results;
}

async function main(): Promise<void> {
  const args = parseArgs();
  const r2 = loadR2Config();
  if (!r2) {
    console.error(
      "R2 not configured — set R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_S3_ENDPOINT, CLOUDFLARE_R2_BUCKET in .env",
    );
    process.exit(2);
  }
  try {
    await stat(ASSETS_DIR);
  } catch {
    console.error(`No local /assets/ at ${ASSETS_DIR}`);
    process.exit(2);
  }

  // Force IPv4 at the socket level — Node's dual-stack behavior has been
  // seen to fall through to IPv6 (2606:4700::/32 for Cloudflare) even with
  // --dns-result-order=ipv4first, and some networks don't route IPv6. Also
  // reuse sockets via keepalive to avoid hammering connect().
  const httpsAgent = new HttpsAgent({
    keepAlive: true,
    maxSockets: 50,
    family: 4,
  });
  const client = new S3Client({
    region: "auto",
    endpoint: r2.endpoint,
    credentials: {
      accessKeyId: r2.accessKeyId,
      secretAccessKey: r2.secretAccessKey,
    },
    requestHandler: new NodeHttpHandler({
      httpsAgent,
      connectionTimeout: 15000,
      requestTimeout: 120000,
    }),
    maxAttempts: 5,
  });

  // 1. Walk local tree, compute md5 per file.
  console.log(`→ Scanning ${ASSETS_DIR}`);
  const locals: Array<{ key: string; path: string; size: number; md5: string }> = [];
  for await (const p of walkFiles(ASSETS_DIR)) {
    const rel = relative(ASSETS_DIR, p).split(/[/\\]/).join("/");
    const key = `${R2_PREFIX}${rel}`;
    const s = await stat(p);
    locals.push({ key, path: p, size: s.size, md5: "" });
  }
  console.log(`  ${locals.length} files`);

  console.log("→ Hashing local files");
  await mapLimit(locals, args.concurrency, async (f) => {
    f.md5 = await md5Hex(f.path);
  }, (done, total) => {
    if (done % 1000 === 0 || done === total) {
      process.stdout.write(`\r  ${done}/${total}`);
    }
  });
  process.stdout.write("\n");

  // 2. List R2 existing.
  console.log(`→ Listing s3://${r2.bucket}/${R2_PREFIX}`);
  const remote = await listR2(client, r2.bucket, R2_PREFIX);
  console.log(`  ${remote.size} remote objects`);

  // 3. Diff.
  const toUpload: typeof locals = [];
  for (const f of locals) {
    const existing = remote.get(f.key);
    if (!existing || existing.etag !== f.md5) {
      toUpload.push(f);
    }
  }

  const localKeys = new Set(locals.map((f) => f.key));
  const toDelete: string[] = [];
  for (const key of remote.keys()) {
    if (!localKeys.has(key)) toDelete.push(key);
  }

  console.log(`\n→ Plan:`);
  console.log(`  upload: ${toUpload.length}`);
  console.log(`  skip (unchanged): ${locals.length - toUpload.length}`);
  console.log(`  orphans: ${toDelete.length}${args.delete ? " (will delete)" : " (keeping — pass --delete to prune)"}`);

  if (args.dryRun) {
    if (toUpload.length > 0) {
      console.log("\n--dry-run upload preview (first 10):");
      for (const f of toUpload.slice(0, 10)) {
        console.log(`  ${f.key} ${f.size}`);
      }
    }
    if (args.delete && toDelete.length > 0) {
      console.log("\n--dry-run delete preview (first 10):");
      for (const k of toDelete.slice(0, 10)) {
        console.log(`  ${k}`);
      }
    }
    return;
  }

  // 4. Upload.
  if (toUpload.length > 0) {
    console.log(`\n→ Uploading ${toUpload.length} files (concurrency=${args.concurrency})`);
    const start = Date.now();
    let bytes = 0;
    let failures = 0;
    await mapLimit(toUpload, args.concurrency, async (f) => {
      // Read into memory so the SDK's retry middleware can resend the body
      // on transient connect errors (streams are not retryable).
      const body = await readFile(f.path);
      try {
        await client.send(
          new PutObjectCommand({
            Bucket: r2.bucket,
            Key: f.key,
            Body: body,
            ContentType: contentTypeFor(f.path),
            ContentLength: body.byteLength,
          }),
        );
        bytes += body.byteLength;
      } catch (err) {
        failures++;
        const msg = err instanceof Error ? err.message : String(err);
        process.stdout.write(`\n  ! ${f.key}: ${msg}\n`);
      }
    }, (done, total) => {
      if (done % 100 === 0 || done === total) {
        const mb = (bytes / 1024 / 1024).toFixed(1);
        const s = ((Date.now() - start) / 1000).toFixed(1);
        process.stdout.write(`\r  ${done}/${total} files, ${mb} MB in ${s}s`);
      }
    });
    process.stdout.write("\n");
    if (failures > 0) {
      console.error(`\n✗ ${failures} upload(s) failed — rerun to retry (diff will only re-upload missing keys)`);
      process.exit(1);
    }
  }

  // 5. Optional delete.
  if (args.delete && toDelete.length > 0) {
    console.log(`\n→ Deleting ${toDelete.length} orphans`);
    // Delete in batches of 1000 (S3 limit).
    for (let i = 0; i < toDelete.length; i += 1000) {
      const batch = toDelete.slice(i, i + 1000);
      await client.send(
        new DeleteObjectsCommand({
          Bucket: r2.bucket,
          Delete: { Objects: batch.map((Key) => ({ Key })) },
        }),
      );
      process.stdout.write(`\r  ${Math.min(i + 1000, toDelete.length)}/${toDelete.length}`);
    }
    process.stdout.write("\n");
  }

  // 6. Publish a tree manifest at a well-known key so anonymous devs can
  //    enumerate the tree without S3 creds and pull everything via plain HTTP.
  const tree = {
    generated_at: new Date().toISOString(),
    base_url: r2.publicUrl,
    asset_prefix: R2_PREFIX,
    files: locals
      .map((f) => ({
        path: f.key.slice(R2_PREFIX.length),
        size: f.size,
        md5: f.md5,
      }))
      .sort((a, b) => a.path.localeCompare(b.path)),
  };
  const treeBody = Buffer.from(JSON.stringify(tree, null, 0));
  const treeKey = "assets_tree.json";
  console.log(`\n→ Publishing tree manifest (${tree.files.length} entries) → ${treeKey}`);
  await client.send(
    new PutObjectCommand({
      Bucket: r2.bucket,
      Key: treeKey,
      Body: treeBody,
      ContentType: "application/json",
      ContentLength: treeBody.byteLength,
      CacheControl: "public, max-age=60",
    }),
  );
  console.log(`  url: ${r2.publicUrl}/${treeKey}`);

  await client.destroy();
  console.log("\n✓ sync complete");
}

main().catch((err) => {
  console.error("\n✗ sync_tree failed:", err);
  process.exit(1);
});
