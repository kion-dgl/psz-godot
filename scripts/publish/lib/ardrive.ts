import { TurboFactory } from "@ardrive/turbo-sdk";
import type { JWK } from "./wallet.js";

export interface UploadResult {
  id: string;
  url: string;
  sizeBytes: number;
}

/**
 * Get an authenticated Turbo client. Caller can reuse across cost estimates
 * and uploads within a single run.
 */
export function createTurbo(wallet: JWK) {
  return TurboFactory.authenticated({ privateKey: wallet as any });
}

/**
 * Estimate upload cost in winc (winston credits) and bytes for a given size.
 * Returns { winc, bytes } — divide winc by 1e12 to get AR; Turbo credit prices
 * approximate $2-5 per GB depending on market.
 */
export async function estimateCost(
  turbo: ReturnType<typeof createTurbo>,
  bytes: number,
): Promise<{ winc: string; bytes: number }> {
  const costs = await turbo.getUploadCosts({ bytes: [bytes] });
  return { winc: costs[0].winc.toString(), bytes };
}

/**
 * Get the authenticated wallet's remaining Turbo credit balance in winc.
 */
export async function getBalanceWinc(
  turbo: ReturnType<typeof createTurbo>,
): Promise<string> {
  const balance = await turbo.getBalance();
  return balance.winc.toString();
}

/**
 * Upload a Uint8Array to Arweave via ArDrive Turbo. Returns the transaction
 * ID and the public gateway URL.
 */
export async function uploadToArweave(
  data: Uint8Array,
  contentType: string,
  wallet: JWK,
  extraTags: Array<{ name: string; value: string }> = [],
): Promise<UploadResult> {
  const turbo = createTurbo(wallet);
  const result = await turbo.uploadFile({
    fileStreamFactory: () => Buffer.from(data),
    fileSizeFactory: () => data.byteLength,
    dataItemOpts: {
      tags: [
        { name: "Content-Type", value: contentType },
        ...extraTags,
      ],
    },
  });
  return {
    id: result.id,
    url: `https://arweave.net/${result.id}`,
    sizeBytes: data.byteLength,
  };
}
