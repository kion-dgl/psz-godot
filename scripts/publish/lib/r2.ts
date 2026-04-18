import { createReadStream } from "fs";
import { S3Client } from "@aws-sdk/client-s3";
import { Upload } from "@aws-sdk/lib-storage";

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
  const client = new S3Client({
    region: "auto",
    endpoint: cfg.endpoint,
    credentials: {
      accessKeyId: cfg.accessKeyId,
      secretAccessKey: cfg.secretAccessKey,
    },
  });

  const upload = new Upload({
    client,
    params: {
      Bucket: cfg.bucket,
      Key: key,
      Body: createReadStream(filePath),
      ContentType: contentType,
    },
    partSize: 50 * 1024 * 1024, // 50 MB parts
    queueSize: 4, // 4 parts in flight
  });

  if (onProgress) {
    upload.on("httpUploadProgress", (p) => onProgress(p.loaded ?? 0, p.total));
  }

  await upload.done();
  await client.destroy();
  return `${cfg.publicUrl}/${key}`;
}
