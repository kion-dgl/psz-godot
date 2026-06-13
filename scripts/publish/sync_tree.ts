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

// Subdirectory names (relative to a SYNC_ROOTS entry) that are vendored
// in-tree and must never be re-uploaded to R2. Match against the relative
// path's first segment when walking. Keep in sync with the LOCAL_ONLY_PREFIXES
// in web/src/utils/assets.ts.
const VENDORED_SKIPS = new Set<string>([
  "kenney_input-prompts",
  "kenney_nature-pack",
  "cc0_textures", // ambientCG CC0 — vendored in-repo, ships with the exe, never on R2 (#356)
]);

// Relative-path prefixes (under each SYNC_ROOTS entry) that are licensed
// for pack-embedded use only. The model goes into the published .pck on
// Arweave (incorporated into a larger project — allowed) but the raw files
// must not be mirrored to R2 (= public CDN of the raw model file).
const RESTRICTED_REL_PREFIXES: string[] = [
  "npcs/cowgirl/",  // Booth.pm — see assets/npcs/cowgirl/LICENSE_booth.md
];

// (local dir → R2 key prefix) pairs. Each root is walked, hashed, diffed,
// and uploaded into its R2 prefix. Adding a new root here is the only
// code-side change needed to pull another tree into the pipeline.
//
// Keep the prefix list in sync with web/src/utils/assets.ts CDN_PREFIXES
// and scripts/tools/fetch_assets_dev.sh's dest_dir_for().
const SYNC_ROOTS: Array<{ localDir: string; r2Prefix: string }> = [
  { localDir: resolve(REPO_ROOT, "assets"), r2Prefix: "assets/" },
  { localDir: resolve(REPO_ROOT, "web/public/assets/psobb_sfx"), r2Prefix: "assets/psobb_sfx/" },
  // The PSZ weapon catalog (wbac01/, wbah01/, …) used to be sourced from a
  // sibling kion-dgl/psz-sketch checkout. It now lives in-tree under
  // assets/weapons/w*/ (see .gitignore), so it's picked up by the first root
  // above and ships in the Godot .pck — no sibling clone required.
];

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

async function* walkFiles(dir: string, depth = 0): AsyncGenerator<string> {
  const entries = await readdir(dir, { withFileTypes: true });
  for (const e of entries) {
    if (depth === 0 && e.isDirectory() && VENDORED_SKIPS.has(e.name)) continue;
    const p = join(dir, e.name);
    if (e.isDirectory()) yield* walkFiles(p, depth + 1);
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

interface Local {
  key: string;
  prefix: string;
  path: string;
  size: number;
  md5: string;
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
  const activeRoots: typeof SYNC_ROOTS = [];
  for (const root of SYNC_ROOTS) {
    try {
      await stat(root.localDir);
      activeRoots.push(root);
    } catch {
      console.warn(`skipping missing source: ${root.localDir}`);
    }
  }
  if (activeRoots.length === 0) {
    console.error("No SYNC_ROOTS resolved — nothing to do");
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

  // 1. Walk each local tree, compute md5 per file. Track the source prefix
  //    so the tree manifest records which local root each file belongs to.
  const locals: Local[] = [];
  for (const root of activeRoots) {
    console.log(`→ Scanning ${root.localDir}`);
    let count = 0;
    for await (const p of walkFiles(root.localDir)) {
      const rel = relative(root.localDir, p).split(/[/\\]/).join("/");
      if (RESTRICTED_REL_PREFIXES.some((pre) => rel.startsWith(pre))) continue;
      const key = `${root.r2Prefix}${rel}`;
      const s = await stat(p);
      locals.push({ key, prefix: root.r2Prefix, path: p, size: s.size, md5: "" });
      count++;
    }
    console.log(`  ${count} files`);
  }

  console.log(`→ Hashing ${locals.length} local files`);
  await mapLimit(locals, args.concurrency, async (f) => {
    f.md5 = await md5Hex(f.path);
  }, (done, total) => {
    if (done % 1000 === 0 || done === total) {
      process.stdout.write(`\r  ${done}/${total}`);
    }
  });
  process.stdout.write("\n");

  // 2. List R2 per prefix — scopes orphan detection to each tree separately.
  const remote = new Map<string, { size: number; etag: string }>();
  for (const root of activeRoots) {
    console.log(`→ Listing s3://${r2.bucket}/${root.r2Prefix}`);
    const chunk = await listR2(client, r2.bucket, root.r2Prefix);
    for (const [k, v] of chunk) remote.set(k, v);
    console.log(`  ${chunk.size} remote objects`);
  }

  // 3. Diff.
  const toUpload: Local[] = [];
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
  //    enumerate everything without S3 creds and pull via plain HTTP. Each
  //    file entry uses its full R2 key — dev fetch looks up the source
  //    prefix to decide the on-disk destination.
  const tree = {
    generated_at: new Date().toISOString(),
    base_url: r2.publicUrl,
    prefixes: activeRoots.map((r) => r.r2Prefix),
    files: locals
      .map((f) => ({ key: f.key, size: f.size, md5: f.md5 }))
      .sort((a, b) => a.key.localeCompare(b.key)),
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
