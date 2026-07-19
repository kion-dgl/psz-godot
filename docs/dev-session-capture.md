# Narrated dev play-test capture

A way to scale play-testing when there isn't time to sit and write up every
run: **play with dev mode on and just talk.** The tooling records your voice,
timestamps the game's debug output, and lines the two up so you (or Claude)
can read "what I said I saw" next to "what the game actually logged." Every
place they disagree is a candidate bug or spec/behaviour drift.

## TL;DR

```bash
# instead of `godot --path .`
scripts/tools/devsession/record_dev_session.sh --note "chaos sorcerer telegraph"
```

Play the window that opens, narrate what you notice out loud, then **quit the
game** to end the run. Output lands in `dev-sessions/<timestamp>/`. Hand the
whole folder to Claude:

> Compare `timeline.txt` — where does my narration disagree with the logs?

## What it produces

`dev-sessions/<timestamp>/`

| file | what it is |
|---|---|
| `timeline.txt` | **read this** — `session.log` + narration merged in wall-clock order, narration lines marked `>>> SAID:` |
| `narration.aligned.txt` | your narration, each segment stamped with the real wall-clock time it was spoken |
| `session.log` | Godot stdout, every line prefixed `[HH:MM:SS.mmm]` |
| `narration.wav` | the raw mic recording |
| `narration.txt` / `narration.json` | whisper transcript (plain + segment offsets) |
| `meta.json` | branch, sha, note, start/end, duration, model, mic |
| `whisper.log`, `ffmpeg.log` | tool output, for debugging the capture itself |

The trick is that `session.log` and the narration share **one wall clock**, so
`timeline.txt` interleaves them correctly. Example:

```
[14:57:27.480] >>> SAID: The chaos sorcerer telegraph did not fire.
[14:57:27.660] [Enemy] chaos_sorcerer cast gem_telegraph
```

You said it didn't fire; the log says it cast one 180 ms later — that's the
kind of contradiction the merge surfaces for free.

## How it works

`record_dev_session.sh` replaces your `godot --path .` launch and:

1. starts `ffmpeg` recording your mic (16 kHz mono — exactly what whisper wants);
2. runs Godot with stdout piped through a Perl filter that prepends a
   millisecond wall clock to every line (Godot flushes per-print, so the
   timestamps reflect real emission time — no pty needed);
3. when the game exits, stops the recording, runs `whisper-cli` on the wav,
   and calls `finalize_session.py` to shift whisper's segment offsets onto the
   wall clock and merge everything into `timeline.txt`.

No game code is touched — it's a launch wrapper.

## Prerequisites (one-time)

```bash
brew install ffmpeg whisper-cpp
# a whisper model (small.en is a good speed/accuracy balance on Apple Silicon):
mkdir -p ~/.cache/whisper-cpp
curl -L -o ~/.cache/whisper-cpp/ggml-small.en.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin
```

## Options

```
--note "text"     free-text focus for the run, saved into meta.json
--audio N         avfoundation audio device index (default: MacBook Pro Microphone)
--list-audio      print the available mics and exit
--model PATH      whisper ggml model (default ~/.cache/whisper-cpp/ggml-small.en.bin)
--pty             run Godot under a pty (escape hatch; not normally needed)
```

Env equivalents: `GODOT_BIN`, `WHISPER_MODEL`, `PSZ_AUDIO_DEVICE`, `PSZ_PTY`.

Pick a specific mic if the default isn't the one you talk into:

```bash
scripts/tools/devsession/record_dev_session.sh --list-audio
scripts/tools/devsession/record_dev_session.sh --audio 0   # e.g. a USB headset
```

## Tips & caveats

- **Quit the game to end cleanly.** That flushes the last logs and triggers
  transcription. `Ctrl-C` in the terminal stops the recording but skips the
  transcribe/merge step.
- **Narrate what you *observe*, with cause** — "the telegraph never showed
  before the hit", "gem cooldown feels stuck at two seconds". Concrete
  observations tied to a moment align against the logs far better than "hmm
  that felt off".
- **Domain words can mis-transcribe.** small.en heard "gem" as "gym", for
  instance. The wall-clock alignment still holds, and Claude reads through the
  homophones from context; bump to `ggml-medium.en.bin` via `--model` if it
  bothers you.
- **Transcription runs after the session** and is roughly real-time on
  Apple Silicon, so a long run takes a little to finish after you quit.
- **`dev-sessions/` is gitignored** — these are working artifacts, not
  committed. Copy one out if you want to keep it.

## Possible follow-up

In normal play the rich `[ValleyField]` cell-load / portal / spawn
diagnostics are off — `DebugConfig.verbose_field` only turns on under
`PSZ_AUTOPILOT`. Always-on logs (`[journey]`, `[Player]`, `[Enemy]`,
`[CellObjects]`, combat) still flow, so the comparison works today. If these
sessions would benefit from the field diagnostics too, a one-line change to
have `verbose_field` also read a `PSZ_DEBUG_VERBOSE` env would let the wrapper
export it without invoking the autopilot driver. Left out here to keep this a
tooling-only, non-Godot change.
