import { readFileSync } from "fs";

export type JWK = Record<string, unknown>;

export function loadWallet(): JWK {
  const path = process.env.ARDRIVE_WALLET_PATH;
  const b64 = process.env.ARDRIVE_WALLET_JSON_B64;
  if (path) {
    const raw = readFileSync(path, "utf8");
    return JSON.parse(raw) as JWK;
  }
  if (b64) {
    return JSON.parse(Buffer.from(b64, "base64").toString("utf8")) as JWK;
  }
  throw new Error(
    "No Arweave wallet configured. Set ARDRIVE_WALLET_PATH or ARDRIVE_WALLET_JSON_B64 in .env (see .env.example).",
  );
}
