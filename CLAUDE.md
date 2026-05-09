# PSZ Godot — repo conventions

Project-specific conventions enforced by CI. Anything else lives in code or
git history.

## Always work on a branch + open a PR — never push direct to `main`

Even when the change looks trivial, even when "commit and merge" sounds
like authorization to fast-forward straight onto `main`. Don't.

`main` is protected by the **"Merge to Main"** ruleset — it requires:

- A pull request (so the diff shows up for review)
- A Copilot code review (auto-runs on PR open / push to PR)
- Plus the standard CI: `verify-assets`, `check-asset-refs`,
  `version-check`, the Godot test runner

Admin-tier accounts have `bypass_mode: pull_request` — meaning they
can self-merge once the rule's met, but **the PR + Copilot review step
is not skippable**. Do not look for a way around it; it is load-bearing.

Merging the PR also kicks off **release CD** (APK signing, Arweave
publish if assets changed, etc.). Pushing to `main` directly skips
both the review *and* the release pipeline — the build never ships
to anyone.

Workflow when the user asks to land changes:

1. Create a feature branch (`feature/<short-name>` is the convention).
2. Commit and push the branch.
3. `gh pr create` — write a real summary that explains *why*, not just
   *what*. The summary is the thing the human reviewer reads first.
4. Wait for Copilot's automatic review and address its comments.
5. Either the user merges (typical), or — if they explicitly authorize
   "merge it for me" *after* Copilot has signed off — `gh pr merge`.
   Even then, default to merge-commit (or rebase if the user prefers
   linear history); never force-push to merge.

If the user's exact words are "commit and merge", interpret it as
"commit and open the PR for me" unless they've also said something
like "skip the PR" or "force-push, I'll deal with it." When in doubt,
ask — opening a PR is cheap, undoing a direct-merge is expensive.

## Asset pack publishing

The game ships its bulk assets (~250 MB of stages, music, NPCs, weapons,
etc.) in a single Godot `.pck` published to Arweave. The runtime
bootstrap downloads the pack on first launch and verifies its sha256.
The in-repo `assets_manifest.json` is the source of truth for which
pack the game expects to load.

**Publishing flow** (`scripts/publish/publish_assets.ts`):

1. `godot --export-pack` builds `dist/assets.pck` from the asset dirs.
2. The pack is uploaded to Arweave (and optionally R2 — currently
   disabled by default due to TLS issues with the public R2 dev URL).
3. A tiny **sidecar** `pack.manifest.json` is written to `dist/` and
   uploaded to Arweave. It carries `{ version, godot_version, pack: {
   sha256, size, urls } }` — basically a snapshot of the in-repo
   manifest as it would be written by this publish run.
4. `assets_manifest.json` is rewritten with the pack URLs **and**
   `sidecar.urls` pointing at the sidecar's Arweave gateways.
5. Commit `assets_manifest.json` (and `asset_tree.txt`) and open a PR.

If the pack content hasn't changed (sha matches previous manifest)
**and** the previous manifest already has a sidecar with the same
version, the publish script reuses both — no double-billing on Arweave
for identical bytes.

## Asset CI checks (the forcing function)

Two CI jobs guard against publishing one half of the pair (manifest or
upload) without the other:

### `verify-assets`

`scripts/tools/verify_assets_manifest.py` runs on every PR:

1. **Pack reachability**: range-GET `bytes=0-15` against each pack URL,
   confirm the response starts with the Godot pack magic `GDPC`. We
   don't HEAD because Arweave's AO-backed gateway strips
   Content-Length, and we don't full-stream because the same gateway
   `IncompleteRead`s at ~50 MB on long downloads.
2. **Sidecar consistency**: download the sidecar JSON from
   `manifest.sidecar.urls`, assert its `version`, `pack.sha256`, and
   `pack.size` exactly match the in-repo `assets_manifest.json`.

Both checks fail-closed: missing sidecar URL field, missing sidecar on
Arweave, or any field mismatch fails CI. **CI does not auto-fix** — a
failure means the dev needs to re-run the publish script and commit
the updated manifest.

This is the same pattern as `version-check` (which fails CI when the
PR doesn't bump `VERSION`): the check exists to force the human to
take a step the toolchain can't safely take for them.

### `check-asset-refs`

`scripts/tools/check_asset_refs.py` greps source for `res://assets/...`
references and verifies each path exists in `asset_tree.txt`
(committed alongside the manifest). Catches the "added a new asset
file but didn't republish" case where the source references a path
that's not actually in the pack.

## Why three layers (pack range-probe + sidecar + asset_tree)

| Mistake | Caught by |
|---|---|
| Dev added a new asset file, forgot to publish | `check-asset-refs` (path missing from `asset_tree.txt`) |
| Dev published, but Arweave upload silently failed | `verify-assets` reachability probe (pack URL 404s) |
| Dev edited an existing asset, forgot to publish (path-stable change) | `verify-assets` sidecar check (sidecar's pack.sha256 ≠ what's in-repo, OR sidecar missing entirely on a fresh sha) |
| Dev rolled back the manifest after publish | `verify-assets` sidecar check (versions diverge) |
| Dev manually edited `assets_manifest.json` to lie about sha | `verify-assets` sidecar check (sidecar disagrees) |

The full sha256 re-stream on every PR was previously the integrity
check, but Arweave's gateway can't reliably serve the full 264 MB
(connection drops at ~50 MB), and that check was redundant with what
the sidecar proves at sub-KB cost.

## Version bumping

CI also requires `VERSION` and `project.godot` `config/version` to be
bumped on every PR. Patch bump (0.x.y → 0.x.y+1) is fine for most
changes; minor bump for notable features.
