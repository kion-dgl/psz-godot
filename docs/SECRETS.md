# Secrets inventory

Every credential the project needs to publish, sign, or distribute. The
**values** live in LastPass; this file is the index — what each secret
is for, what depends on it, what happens if it leaks, and how to rotate.

The corresponding **GH Actions secret** column tells you what name to
look for under *Settings → Secrets and variables → Actions* on the repo.
Workflows that use a secret reference it by that exact name.

## The list

| Purpose | LastPass entry | GH Actions secret(s) | Used by | Blast radius if leaked | Rotation |
|---|---|---|---|---|---|
| Asset pack publishing to Arweave | `psz-godot / arweave-wallet` | `ARDRIVE_WALLET_JSON_B64` | `scripts/publish/lib/wallet.ts` (via `publish_assets.ts`, `recover_publish.ts`) | Attacker spends the wallet's $AR balance and can publish forged asset packs into your wallet's tx history. The in-repo manifest's pack sha256 still protects clients from loading the forgery, but reputational mess. | Generate new Arweave wallet, replace the secret, run a fresh `npm run upload-pack` (republishes pack from the new wallet). |
| Android APK release signing | `psz-godot / android-release-keystore` | `ANDROID_KEYSTORE_B64` + `ANDROID_KEYSTORE_PASSWORD` | `.github/workflows/release.yml` (Android export step) | Attacker can ship malicious updates to anyone with PSZ installed — Android trusts any APK signed with the keystore that signed the original install. | **Painful.** No rotation path for sideloaded apps; rotating means every existing user has to uninstall + reinstall (loses save data unless they back up). Treat this as a key you don't rotate unless it's actually compromised. The cert SHA-256 is pinned in `release.yml`; if the secret somehow doesn't match, CI fails before shipping. |
| (future) macOS notarization | `psz-godot / apple-notary` | `APPLE_ID_USERNAME`, `APPLE_NOTARY_PASS`, `APPLE_TEAM_ID` | (not yet wired) `release.yml` macOS export step | Attacker can submit malware for Apple notarization under your team ID. Apple revokes on detection, but reputational hit. | Trivial — generate a new app-specific password from appleid.apple.com, replace `APPLE_NOTARY_PASS`. |
| (future) Windows code signing | `psz-godot / azure-trusted-signing` | `AZURE_TRUSTED_SIGNING_*` (TBD) | (not yet wired) `release.yml` Windows export step | Attacker can ship malware signed by your identity — bypasses SmartScreen for downloaders. | Through Azure portal: revoke + reissue. Microsoft Trusted Signing keys are short-lived by design, less catastrophic than traditional EV certs. |

## Why a separate keystore for Android (and not just the Arweave wallet)

It's tempting to reuse the Arweave RSA JWK as the Android signing key
since they're both RSA. **Don't.** Different threat models:

- The Arweave wallet has to be hot in CI on every asset publish.
- The Android signing key only has to be hot on release cuts.
- Rotating the Arweave wallet is cheap (new wallet, republish).
- Rotating the Android signing key is catastrophic for users.

Coupling them means one compromise = both impacts, and you lose the
ability to migrate either system independently.

## Adding a new secret

1. Generate locally with strong randomness (`openssl rand -hex 32`,
   `keytool -genkeypair`, etc.). Don't let CI mint it — secrets that CI
   generates aren't backed up anywhere.
2. Stash the value + any binary artifacts in LastPass under
   `psz-godot / <descriptive-name>`. Attach binary files; put text
   values in the password field or notes.
3. Add the value to GH Actions secrets with a name that matches the
   convention (`SCREAMING_SNAKE_CASE`, prefixed by service if useful).
4. Update the table above with: LastPass entry, GH secret name(s), what
   uses it, blast radius, rotation procedure.
5. Reference the secret in the workflow via
   `${{ secrets.YOUR_SECRET }}`, never `echo` the value into logs, and
   never commit even a partial value to the repo.

## Onboarding a new dev machine

This is the migration checklist when you switch daily drivers:

1. Install LastPass, log in, find every entry under `psz-godot / *`.
2. For each entry, restore any required local files (e.g., write the
   Arweave JWK to a path and point `ARDRIVE_WALLET_PATH` at it; the
   Android keystore is needed only for local release exports, not for
   day-to-day dev).
3. Confirm GH Actions still has every secret in the table above. If
   any are missing, repaste from LastPass.
4. Try `npm run upload-pack -- --dry-run` (or whatever the dry path is)
   to confirm the wallet works end-to-end.

If a secret is in the table but missing from LastPass, **stop and
recover it before doing anything else** — the table is the source of
truth for what the project needs to function.
