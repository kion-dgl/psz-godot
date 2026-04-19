import { createReadStream } from "fs";
import { S3Client } from "@aws-sdk/client-s3";
import { Upload } from "@aws-sdk/lib-storage";
import { NodeHttpHandler } from "@smithy/node-http-handler";
import { Agent as HttpsAgent } from "https";

export interface R2Config {
  accessKeyId: string;
  secretAccessKey: string;
  endpoint: string;
  bucket: string;
  publicUrl: string;
}

export function loadR2Config(): R2Config | null {
  const accessKeyId = process.env.R2_ACCESS_KEY_ID;
  const secretAccessKey = process.env.R2_SECRET_ACCESS_KEY;
  const endpoint = process.env.R2_S3_ENDPOINT;
  const bucket = process.env.CLOUDFLARE_R2_BUCKET;
  const publicUrl = process.env.CLOUDFLARE_R2_PUBLIC_URL;
  if (!accessKeyId || !secretAccessKey || !endpoint || !bucket || !publicUrl) {
    return null;
  }
  return {
    accessKeyId,
    secretAccessKey,
    endpoint,
    bucket,
    publicUrl: publicUrl.replace(/\/$/, ""),
  };
}

/**
 * Upload a local file to R2 using the S3-compatible API. Uses
 * @aws-sdk/lib-storage's `Upload` which auto-chunks (multipart) for any size
 * and uploads parts in parallel. Streams from disk — no in-memory copy.
 */
export async function uploadFileToR2(
  filePath: string,
  key: string,
  contentType: string,
  cfg: R2Config,
  onProgress?: (loaded: number, total: number | undefined) => void,
): Promise<string> {
  // Force IPv4 + keepalive — Node's dual-stack resolver will fall through
  // to IPv6 on Cloudflare endpoints on some networks and hang there, even
  // with --dns-result-order=ipv4first. See sync_tree.ts for the same
  // workaround.
  const httpsAgent = new HttpsAgent({
    keepAlive: true,
    maxSockets: 10,
    family: 4,
  });
  const client = new S3Client({
    region: "auto",
    endpoint: cfg.endpoint,
    credentials: {
      accessKeyId: cfg.accessKeyId,
      secretAccessKey: cfg.secretAccessKey,
    },
    requestHandler: new NodeHttpHandler({
      httpsAgent,
      connectionTimeout: 15000,
      // Per-part request budget. Generous to absorb slow links — total
      // upload is bounded by partSize × queueSize / upstream-bandwidth.
      requestTimeout: 600000,
    }),
    maxAttempts: 5,
  });

  const upload = new Upload({
    client,
    params: {
      Bucket: cfg.bucket,
      Key: key,
      Body: createReadStream(filePath),
      ContentType: contentType,
    },
    // 10 MB parts × 2 concurrent. On a saturated home upstream a 50 MB part
    // routinely exceeded the per-request timeout and caused EPIPE. Smaller
    // parts complete faster and recover better from transient resets.
    partSize: 10 * 1024 * 1024,
    queueSize: 2,
  });

  if (onProgress) {
    upload.on("httpUploadProgress", (p) => onProgress(p.loaded ?? 0, p.total));
  }

  await upload.done();
  await client.destroy();
  return `${cfg.publicUrl}/${key}`;
}
