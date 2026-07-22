# PSZ Godot — repo conventions

Project-specific conventions enforced by CI. Anything else lives in code or
git history.

## Beta working agreement (full text: spec /engineering)

- **Hierarchies**: shared behavior lives in base classes (`Enemy` →
  `WolfEnemy`); leaf classes only where behavior genuinely diverges, and
  the PR must say why. Data variation goes in resources, not scripts.
  Every hierarchy gets an Astro spec page defining the base contract.
  Exception: lazily-loaded 2D screens use preloaded-helper composition,
  never cross-script inheritance (Android export breaks — docs/shop-dedup.md).
- **Debt is loud**: growing any `code_*_baseline.json` count fails CI
  unless a commit carries `Debt-Accepted: <reason>`. Deliberate debt
  belongs at the END of beta; mid-beta acceptance should answer "why now?".
- **Two test layers** for anything frame/timing/combat-driven: a seeded
  unit test in test_runner AND a post-build autopilot probe (matrix
  phase / smoke / sanity checkpoint). One layer is not done planning.
- **Definitions and tests are aligned before implementation.** Spec the
  behavior (an Astro `/states` or `/engineering` page — the normative,
  RFC-2119 contract) and pin/align the tests against it *first*, then
  implement. A new definition MUST NOT contradict an existing one: if it
  does, reconcile them (or mark the conflict an explicit open question)
  before merging. Implementation then points at the doc + the tests:
  "this is how it's expected to work." Spec/test drift is a bug.

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

**The only blocker for a PR is testing and verification.** Batch freely.
Multiple unrelated changes in one PR is fine, and more than one PR open at a
time is fine — the gate is that every change in a PR is verified, not how many
PRs exist or how topically pure they are. Don't hold work back to keep a
single-PR queue. Versioning is auto-stamped at build time (see "Versioning"
below), so parallel PRs never conflict on version files.

**Testing is the unit of a PR.** Bundle freely *as long as the bundle can
be tested and verified together*. If several changes are exercised by the
same build/test pass (same autopilot run, same manual round on the Mac),
putting them in one PR is good — it's one verification, one review, one
release. A change that's "basically free" (small, low-risk) is fine to fold
into a larger related PR. The line to watch is *verifiability*, not topical
purity: split only when a change needs its own distinct test/verification path,
or is risky enough that you want it isolated so a revert is clean. When unsure,
ask which way to package.

## Feature flow — spec-first, Godot-implemented, human-tested

The standard path for a behavior change or feature:

1. **Define the expected behavior in Astro first** — a `/states` /
   `/engineering` page or a shop/screen **mock** under `spec/` is the
   normative contract (RFC-2119 for `/states`). It says how it *should*
   work, independent of the current code. Reconcile it with any existing
   definition (see "definitions aligned before implementation" above).
2. **Implement it in Godot** so the runtime matches the spec/mock.
3. **Add/update tests to confirm it** — the two-layer rule: a seeded
   `test_runner` unit test AND an autopilot probe.
4. **Open the PR; run the autopilot matrix** (Godot changes only — see
   the rule below).
5. **Kion pulls the branch and builds/tests on his Mac** (real hardware)
   before it lands; merge stays human (the branch/PR rule above).

A change can be at any stage of this. A **spec/mock-only PR** (step 1 with
no Godot yet) is legitimate and lands as the definition — the Godot
implementation that makes the runtime match is the *next* PR. Don't treat
a mock PR as incomplete for lacking Godot code; treat it as the contract
the Godot work will be tested against.

**Sanity-check and the regression matrix verify Godot behavior — run them
only when the change touches `.gd`, scenes, or quest data.** A spec-only
(`spec/`), docs, or `CLAUDE.md` PR does NOT need the godot autopilot; CI's
`spec` build + `version-check` cover it. Running sanity on a non-Godot PR
just burns ~3 min of autopilot and can flake on a loaded box. (The
`merge_gate.sh` hook still asks for a `.sanity-pass` on a *local CLI*
merge regardless — pointless for a non-Godot diff; relaxing it to skip
diffs with no `.gd`/scene/quest changes is a reasonable follow-up.)

## Orphan / superseded files → `/archive/`, not `rm`

When working files turn up that look orphaned (untracked, no references
in source or scene files, never in git history), don't `git clean` or
`rm` them. Move them to `/archive/<original/path>` instead. The
`archive/` directory is gitignored, so the move quarantines the files
without losing them, and they're easy to inspect or restore if the
"unused" call was wrong.

Use the original repo-relative path inside `archive/` so the
relationship to where the files came from is obvious — e.g.
`assets/npcs/item_shop/orphan.png` becomes
`archive/assets/npcs/item_shop/orphan.png`.

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

### DO pack host (dev channel) — `npm run upload-pack-do`

Arweave is permanent but slow + billed, which is painful when you just
need to ship one changed/added asset during development. So there's a
self-hosted alternative: a DigitalOcean droplet running Caddy at
**`https://pck.psz.onl`** (auto-HTTPS), serving content-addressed packs
out of `/srv/packs/<sha256>.pck` with a matching `<sha256>.sidecar.json`.

- **`npm run upload-pack-do`** (`scripts/publish/publish_do.ts`) builds
  the pack, `rsync`s it + the sidecar to the droplet over SSH (your
  existing key — no secrets), verifies the host serves the `GDPC` magic,
  prunes old packs, and rewrites `assets_manifest.json` to point at the
  DO URLs. Then commit `assets_manifest.json` + `asset_tree.txt` like any
  publish. Flags: `--skip-build`, `--dry-run`. Config (with droplet
  defaults) in `.env`: `DO_PACK_SSH`, `DO_PACK_DIR`, `DO_PACK_BASE`,
  `DO_PACK_KEEP`.
- **Rotation:** 25 GB disk, so only the newest `DO_PACK_KEEP` (default
  15) packs are retained — the publish prunes, and a daily server cron
  (`/usr/local/bin/prune-packs.sh`) is the safety net. Content-addressed
  names make this safe: the in-repo manifest always points at the newest
  pack, which is never pruned. **Caveat:** reverting the manifest to an
  old sha whose pack was already rotated away → re-publish it.
- **Use DO for dev iteration; use Arweave (`upload-pack`) for tagged
  releases** — the droplet isn't permanent, so a shipped build's manifest
  should point at Arweave. The same CI checks (`verify-assets` range-probe
  + sidecar, `check-asset-refs`) pass against either host; Caddy serves
  HTTP range requests (206) and the sidecar JSON.
- **TLS: Caddy must serve an RSA cert (`tls { key_type rsa2048 }`).**
  Godot's bundled mbedTLS *cannot* handshake Caddy's default ECDSA /
  ISRG-Root-X2 cert — it fails with `TLS handshake error -30592` and the
  bootstrap blacklists the host. curl/Python/CI all speak ECDSA fine, so
  this is invisible unless tested through Godot's actual downloader (a
  seeded pack cache also hides it). The Caddyfile pins `key_type rsa2048`.
- **HTTP fallback:** Caddy also serves the packs over plain `http://`
  (explicit `http://pck.psz.onl` block — no 308 redirect). `bootstrap.gd`
  retries a pack URL over `http://` when the `https://` attempt gets no
  HTTP reply (TLS handshake / connection failure). Safe because the pack
  is sha256-verified after download (manifest is the trust anchor) and the
  `GDPC` magic check rejects junk — HTTP only drops the TLS layer. (Desktop
  only: Android's prebuilt export template blocks cleartext, so mobile
  relies on the RSA HTTPS path.)

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

This is the same pattern as `version-check` (which fails CI when a
PR hand-edits the stamped-at-build-time version placeholders): the
check exists to force the human to take a step the toolchain can't
safely take for them.

### `check-asset-refs`

`scripts/tools/check_asset_refs.py` greps source for `res://assets/...`
references and verifies each path exists in `asset_tree.txt`
(committed alongside the manifest). Catches the "added a new asset
file but didn't republish" case where the source references a path
that's not actually in the pack.

### `r2-mirror-check`

`scripts/tools/check_r2_mirror.sh` runs on every PR. It diffs `assets/*`
and `web/public/assets/psobb_sfx/*` between the PR base and head, then
HEAD-probes each added/modified path against the R2 public URL
(`pub-8bb0622759a042aa9dbd9cb4bd1f21e6.r2.dev`). Any 404 fails the job.

Excludes (kept in sync with `scripts/publish/sync_tree.ts`):

- `assets/kenney_input-prompts/`, `assets/kenney_nature-pack/` — vendored
  in-repo, never on R2
- `assets/npcs/cowgirl/` — pack-only license
- `*.import`, `*.uid` — Godot bookkeeping, not asset content

Covers the R2/web side. The Arweave/pack side is `verify-assets`.

## Asset pipeline split: Arweave .pck vs R2 raw mirror

The repo ships assets through **two** separate distribution channels.
A PR that adds asset files must update both, or one of the CI checks
will catch it:

| Channel | Consumer | Updated by | Verified by |
|---|---|---|---|
| Arweave `.pck` | Godot game (desktop / mobile / web export) | `cd scripts/publish && npm run upload-pack` — commits `assets_manifest.json` + `asset_tree.txt` | `verify-assets` + `check-asset-refs` |
| R2 raw mirror | Vite web tools (quest editor, storybook, retarget viewers) — fetch individual files via `VITE_ASSETS_BASE` | `cd scripts/publish && npm run sync-tree` — uploads to R2, **no commit** | `r2-mirror-check` |

**If your PR adds files under `assets/` or `web/public/assets/psobb_sfx/`:**

1. Run `cd scripts/publish && npm run sync-tree` (uploads to R2 — no commit needed).
2. If the Godot game needs the new files in the pack: also run `npm run upload-pack`, commit `assets_manifest.json` and `asset_tree.txt`.
3. Push the PR. `r2-mirror-check` probes the new R2 paths; `verify-assets` probes the pack.

R2 credentials live in `.env`: `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`,
`R2_S3_ENDPOINT`, `CLOUDFLARE_R2_BUCKET`, `CLOUDFLARE_R2_PUBLIC_URL`.

## Why these layers (pack range-probe + sidecar + asset_tree + r2-mirror)

| Mistake | Caught by |
|---|---|
| Dev added a new asset file, forgot to republish the pack | `check-asset-refs` (path missing from `asset_tree.txt`) |
| Dev published the pack, but Arweave upload silently failed | `verify-assets` reachability probe (pack URL 404s) |
| Dev edited an existing asset, forgot to republish (path-stable change) | `verify-assets` sidecar check (sidecar's pack.sha256 ≠ what's in-repo, OR sidecar missing entirely on a fresh sha) |
| Dev rolled back the manifest after publish | `verify-assets` sidecar check (versions diverge) |
| Dev manually edited `assets_manifest.json` to lie about sha | `verify-assets` sidecar check (sidecar disagrees) |
| Dev added a new asset, forgot to run `sync-tree` for the R2 mirror | `r2-mirror-check` (R2 URL 404s for the new path) |

The full sha256 re-stream on every PR was previously the integrity
check, but Arweave's gateway can't reliably serve the full 264 MB
(connection drops at ~50 MB), and that check was redundant with what
the sidecar proves at sub-KB cost.

## Versioning — auto-stamped build numbers (NEVER bump by hand)

The version is a flat build number (400, 401, 402, …) computed at
build time — **no PR bumps anything**, so version merge conflicts are
structurally impossible. The three committed sources stay at the
literal placeholder `dev`:

1. `VERSION`
2. `project.godot` `config/version`
3. `export_presets.cfg` `version/name` (Android `dumpsys` reads this)

CI's `version-check` **fails if any of them is edited away from
`dev`**. `scripts/tools/stamp_version.sh` computes
`build = 95 + first-parent commit count` (+1 per merged PR; offset
aligns with the retired 0.39.x semver line) and stamps all three plus
Android `version/code` (same integer → APK upgrades always install
over older builds). Release CD tags `v<build>`; PR playtest builds
stamp `<build>-pr<N>.<shortsha>`. Local/dev runs show `dev` unless you
run the stamp script yourself (then `git checkout` the three files —
never commit a stamp). The publish scripts' pack sidecar `version`
field reads `VERSION` too — `dev` from a dev box is fine there, the
sha256 is the integrity anchor.

## "Dev mode with transcription" — what the user means

When the user says **"dev mode with transcription"** (or "start a dev
session with transcription", "record a narrated play-test"), they mean:
launch a real play session where they narrate observations out loud, so
the transcript can be diffed against the game's debug logs. This is the
project's main way to scale play-testing — see `docs/dev-session-capture.md`.

What to do:

1. Run `scripts/tools/devsession/record_dev_session.sh` **in the
   background** (`run_in_background: true`). Pass `--note "<focus>"` if the
   user named one ("dev mode with transcription on the chaos sorcerer" →
   `--note "chaos sorcerer"`). The script opens the game window on the
   Mac, records the mic, and stamps Godot stdout to a timestamped log.
   The user plays and narrates; the dev-mode toggles themselves are theirs
   to flip in-game (PSO start menu / F-keys) — the wrapper only captures.
2. **Do not poll.** The background task runs until the user quits the
   game, then transcribes (whisper) and writes
   `dev-sessions/<timestamp>/`. You're notified on completion.
3. On completion, **read `dev-sessions/<latest>/timeline.txt` and report
   drift automatically** — every place a `>>> SAID:` narration line
   contradicts the adjacent log lines is a candidate bug or spec/behaviour
   drift. That analysis is the payoff; produce it without being asked
   again. `meta.json` has the branch/sha/note for context.

Prereqs (ffmpeg, whisper-cpp, `ggml-small.en` model) are installed on the
Mac. If the script errors on a missing prereq, see the runbook's
"Prerequisites" section rather than improvising.

## "Run autopilot" — what the user means

When the user says **"run autopilot"** (or "run autopilot on
\<quest_id>", "play through \<quest_id>", "drive the autopilot",
"run the matrix"), they mean: launch the headless Godot game with
`PSZ_AUTOPILOT=1`, point it at a quest, and watch its `[sanity]`
log lines for `DONE ok` (pass) or a stuck-walk / timeout (fail).

There is **no single CLI command** — you have to assemble it from
env vars + a save-state stage. The standing entry points:

| Need | Script |
|---|---|
| Boot → title → character creation only | `scripts/tools/autoplay/record_boot.sh` |
| Search and Rescue (first quest, from a fresh save) | `scripts/tools/autoplay/record_first_mission.sh` |
| Full regression chain (Boot → SR → PP → AS → DOE → FO → SIS) | `scripts/tools/autoplay/run_regression_matrix.sh` |
| Per-quest matrix (older, smaller scope) | `scripts/tools/autoplay/run_quest_matrix.sh` |

For **one-off quests not covered by those scripts** (heretic,
control_system, the_broken_seal, dark_castle, investigate_tower,
static_in_the_snow, etc.) you have to launch godot directly. The
shape:

```bash
# 1. Override assets_manifest.json so the game loads the LOCAL pack
#    instead of downloading from Arweave. Always back it up + restore.
MANIFEST_BAK=$(mktemp); cp assets_manifest.json "$MANIFEST_BAK"
PACK_SIZE=$(stat -c %s dist/assets.pck)
PACK_SHA=$(sha256sum dist/assets.pck | cut -d' ' -f1)
cat > assets_manifest.json <<JSON
{ "version": "sanity", "godot_version": "4.5", "pack": { "sha256": "$PACK_SHA", "size": $PACK_SIZE, "urls": ["file://LOCAL_DIST/assets.pck"] } }
JSON
trap 'cp "$MANIFEST_BAK" assets_manifest.json; rm -f "$MANIFEST_BAK"' EXIT

# 2. Stage a userdir from a save state that has the quest UNLOCKED
#    (the parent quest must be completed). Snapshots live in
#    /tmp/quest_matrix_scratch/post-<quest_tag>/ after each matrix run.
USERDIR=/tmp/some_scratch/userdir
rm -rf "$USERDIR"; mkdir -p "$USERDIR/godot/app_userdata"
cp -r /tmp/quest_matrix_scratch/post-<parent_quest> "$USERDIR/godot/app_userdata/PSZ Godot"

# 3. Launch headless godot with autopilot env vars.
env PSZ_AUTOPILOT=1 \
    PSZ_AUTOPILOT_PHASE=first-mission \
    PSZ_AUTOPILOT_NO_OBSTACLES=1 \
    PSZ_AUTOPILOT_NO_BOXES=1 \
    PSZ_AUTOPILOT_QUEST=<quest_id> \
    XDG_DATA_HOME="$USERDIR" \
    LIBGL_ALWAYS_SOFTWARE=1 \
    xvfb-run -a -s "-screen 0 640x360x24" \
    timeout 1500 godot --write-movie out.avi --fixed-fps 30 \
    --disable-vsync --audio-driver Dummy --path . \
    > out.sanity.log 2>&1

# 4. Pass = grep -qF '[sanity] DONE ok' out.sanity.log
#    Fail = grep 'stuck-walk\|FAIL:\|author waypoints' out.sanity.log
#    Timeout (rc=124) = stuck in an unproductive loop
```

### Save-state chaining

Each quest's autopilot resume save lives at
`/tmp/quest_matrix_scratch/post-<tag>/`. The matrix harness
snapshots them in chain order. A child quest must start from its
parent's post-save, or the guild counter won't surface it and the
autopilot hangs at "guild accept limit reached" until the 1800s
timeout. See `feedback_test_chain_must_make_unlocks_reachable`
auto-memory.

### Sanity log conventions

The autopilot prints `[sanity] …` checkpoints throughout the run.
The diagnostic vocabulary:

- `[sanity] checkpoint: <name>` — milestone reached
- `[sanity] cell-load <sec>:<pos> visit=<n> stage=<sid> … plan label='…' do=[…] exit='…'` — step transition
- `[sanity] action <i>/<n>: <name>` — executing an action from the cell's do[] list
- `[sanity] walk to exit '<dir>' via <n> waypoint(s):` — pathfinding through the stage's waypoint graph
- `[sanity] waypoint <i>/<n> reached` — navigation progress
- `[sanity] stuck-walk diagnostic: player=… target=… dir=… dist=…` — walk primitive hasn't moved the player toward the target; about to fail
- `[sanity] FAIL: walk stuck at dist=… in cell … — author waypoints for this stage` — the actionable error; the stage's waypoint graph needs hand-authoring
- `[sanity] DONE ok` — quest cleared end-to-end; this is the success oracle

### Waypoint authoring URLs

When a stage needs hand-authored waypoints, the stage editor is
at `http://<host>:5173/psz-godot/#/stage-editor?stage=<sid>&quest=<qid>`
(LAN host `192.168.10.36`, Tailscale `100.89.189.126`). Note the
`/psz-godot/` base path — Vite serves the SPA there, omitting it
loads a blank page.
