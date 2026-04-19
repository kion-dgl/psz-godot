import { createReadStream, statSync } from "fs";
import { TurboFactory } from "@ardrive/turbo-sdk";
import type { JWK } from "./wallet.js";

export interface UploadResult {
  id: string;
  urls: string[];
  sizeBytes: number;
}

// Three public gateways pointing at the same Arweave tx. Listed in the
// manifest so bootstrap.gd can try all of them if one lags propagation.
function gatewayUrls(txId: string): string[] {
  return [
    `https://arweave.net/${txId}`,
    `https://ar-io.dev/${txId}`,
    `https://permagate.io/${txId}`,
  ];
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
 * Upload a local file to Arweave via ArDrive Turbo. Streams from disk — the
 * previous impl loaded the full file into a Buffer which blew up RAM on the
 * 128 MB music pack. Returns the tx id and all three public gateway URLs.
 */
export async function uploadFileToArweave(
  filePath: string,
  contentType: string,
  wallet: JWK,
  extraTags: Array<{ name: string; value: string }> = [],
): Promise<UploadResult> {
  const turbo = createTurbo(wallet);
  const size = statSync(filePath).size;
  const result = await turbo.uploadFile({
    fileStreamFactory: () => createReadStream(filePath),
    fileSizeFactory: () => size,
    dataItemOpts: {
      tags: [
        { name: "Content-Type", value: contentType },
        ...extraTags,
      ],
    },
  });
  return { id: result.id, urls: gatewayUrls(result.id), sizeBytes: size };
}
