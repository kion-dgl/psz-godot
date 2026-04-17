#!/usr/bin/env python3
"""
SSEQ Renderer — Renders NDS SSEQ sequences to WAV using SWAR instrument samples.

The NDS sound system works like a MIDI synth:
- SWAR (Wave Archive) contains short PCM/ADPCM samples (instruments)
- SBNK (Sound Bank) maps program/note numbers to SWAR samples with pitch/envelope info
- SSEQ (Sound Sequence) contains playback commands (note on/off, pitch, volume, tempo)

This renderer reads SSEQ commands, looks up samples from SBNK→SWAR, and mixes
them into a WAV file at the correct pitch, volume, and timing.
"""

import struct
import array
import wave
import os
import sys
from dataclasses import dataclass, field
from pathlib import Path

import ndspy.soundArchive
import ndspy.soundBank
import ndspy.soundSequenceArchive

# ── Constants ──

SAMPLE_RATE = 32768  # NDS mixing rate
MAX_RENDER_SECONDS = 10  # Cap render length for SFX
MASTER_VOLUME = 0.8

# IMA-ADPCM tables
IMA_INDEX_TABLE = [-1, -1, -1, -1, 2, 4, 6, 8, -1, -1, -1, -1, 2, 4, 6, 8]
IMA_STEP_TABLE = [
    7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31,
    34, 37, 41, 45, 50, 55, 60, 66, 73, 80, 88, 97, 107, 118, 130, 143,
    157, 173, 190, 209, 230, 253, 279, 307, 337, 371, 408, 449, 494, 544,
    598, 658, 724, 796, 876, 963, 1060, 1166, 1282, 1411, 1552, 1707, 1878,
    2066, 2272, 2499, 2749, 3024, 3327, 3660, 4026, 4428, 4871, 5358, 5894,
    6484, 7132, 7845, 8630, 9493, 10442, 11487, 12635, 13899, 15289, 16818,
    18500, 20350, 22385, 24623, 27086, 29794, 32767,
]


def decode_adpcm(data: bytes) -> list[int]:
    """Decode IMA-ADPCM to PCM16 samples."""
    if len(data) < 4:
        return []
    predictor = struct.unpack_from('<h', data, 0)[0]
    step_index = min(data[2], 88)
    samples = [predictor]
    for byte_idx in range(4, len(data)):
        byte = data[byte_idx]
        for nibble_shift in (0, 4):
            nibble = (byte >> nibble_shift) & 0x0F
            step = IMA_STEP_TABLE[step_index]
            diff = step >> 3
            if nibble & 1: diff += step >> 2
            if nibble & 2: diff += step >> 1
            if nibble & 4: diff += step
            if nibble & 8: diff = -diff
            predictor = max(-32768, min(32767, predictor + diff))
            step_index = max(0, min(88, step_index + IMA_INDEX_TABLE[nibble]))
            samples.append(predictor)
    return samples


def decode_pcm16(data: bytes) -> list[int]:
    """Decode PCM16 data."""
    samples = []
    for i in range(0, len(data) - 1, 2):
        samples.append(struct.unpack_from('<h', data, i)[0])
    return samples


def decode_pcm8(data: bytes) -> list[int]:
    """Decode PCM8 data (signed)."""
    return [(b - 128) * 256 if b >= 128 else b * 256 for b in data]


def decode_swav(swav) -> list[int]:
    """Decode an SWAV to PCM16 samples."""
    if swav.waveType.value == 0:
        return decode_pcm8(swav.data)
    elif swav.waveType.value == 1:
        return decode_pcm16(swav.data)
    elif swav.waveType.value == 2:
        return decode_adpcm(swav.data)
    return []


# ── SSEQ Command Parser ──

@dataclass
class NoteEvent:
    """A note to be rendered."""
    wave_id: int          # Wave index in SWAR
    warc_id: int          # Wave archive index
    base_rate: int        # Sample's native sample rate
    base_note: int        # Base pitch of the sample
    note: int             # MIDI note number (target pitch)
    velocity: int         # 0-127
    duration_ticks: int   # Duration in ticks
    start_tick: int       # When the note starts
    volume: int = 127     # Channel volume
    pan: int = 64         # 0=left, 64=center, 127=right


@dataclass
class Channel:
    volume: int = 127
    pan: int = 64
    program: int = 0
    tick: int = 0


def parse_sseq_events(data: bytes, bank, wave_archives) -> list[NoteEvent]:
    """Parse SSEQ binary data into NoteEvent list."""
    events = []
    pos = 0
    tick = 0
    channel = Channel()
    call_stack = []
    loop_count = {}
    max_ticks = int(MAX_RENDER_SECONDS * 120 * 2)  # Rough tick limit

    def read_var_len() -> int:
        nonlocal pos
        result = 0
        while pos < len(data):
            b = data[pos]
            pos += 1
            result = (result << 7) | (b & 0x7F)
            if not (b & 0x80):
                break
        return result

    while pos < len(data) and tick < max_ticks:
        cmd = data[pos]
        pos += 1

        if cmd < 0x80:
            # Note on: cmd = note, next bytes = velocity, duration
            note = cmd
            if pos >= len(data):
                break
            velocity = data[pos]
            pos += 1
            duration = read_var_len()

            # Look up sample from bank
            sample_info = _lookup_sample(bank, channel.program, note, wave_archives)
            if sample_info:
                wave_id, warc_id, base_rate, base_note = sample_info
                events.append(NoteEvent(
                    wave_id=wave_id,
                    warc_id=warc_id,
                    base_rate=base_rate,
                    base_note=base_note,
                    note=note,
                    velocity=min(velocity, 127),
                    duration_ticks=duration,
                    start_tick=tick,
                    volume=channel.volume,
                    pan=channel.pan,
                ))
            tick += duration

        elif cmd == 0x80:
            # Rest
            duration = read_var_len()
            tick += duration

        elif cmd == 0x81:
            # Program change
            program = read_var_len()
            channel.program = program

        elif cmd == 0x93:
            # Open track (multi-track) — skip track number + offset
            if pos + 3 <= len(data):
                pos += 4  # track num (1) + offset (3)

        elif cmd == 0x94:
            # Jump
            if pos + 2 < len(data):
                offset = struct.unpack_from('<I', data, pos - 1)[0] & 0xFFFFFF
                pos += 3
                # Avoid infinite loops
                if offset in loop_count:
                    loop_count[offset] += 1
                    if loop_count[offset] > 2:
                        break
                else:
                    loop_count[offset] = 1
                pos = offset

        elif cmd == 0x95:
            # Call
            if pos + 2 < len(data):
                offset = struct.unpack_from('<I', data, pos - 1)[0] & 0xFFFFFF
                pos += 3
                call_stack.append(pos)
                pos = offset

        elif cmd == 0xA0:
            # Random (skip 4 bytes)
            pos += 4

        elif cmd == 0xA1:
            # Variable (skip 2 bytes)
            pos += 2

        elif cmd == 0xB0:
            # If (skip)
            pass

        elif cmd == 0xC0:
            # Pan
            if pos < len(data):
                channel.pan = data[pos]
                pos += 1

        elif cmd == 0xC1:
            # Volume
            if pos < len(data):
                channel.volume = data[pos]
                pos += 1

        elif cmd == 0xC2:
            # Master volume (skip)
            pos += 1

        elif cmd == 0xC3:
            # Transpose (skip)
            pos += 1

        elif cmd == 0xC4:
            # Pitch bend (skip)
            pos += 1

        elif cmd == 0xC5:
            # Pitch bend range (skip)
            pos += 1

        elif cmd == 0xC6:
            # Priority (skip)
            pos += 1

        elif cmd == 0xC7:
            # Note wait (mono/poly mode)
            pos += 1

        elif cmd == 0xC8:
            # Tie (skip)
            pos += 1

        elif cmd == 0xC9:
            # Portamento control (skip)
            pos += 1

        elif cmd == 0xCA:
            # Modulation depth (skip)
            pos += 1

        elif cmd == 0xCB:
            # Modulation speed (skip)
            pos += 1

        elif cmd == 0xCC:
            # Modulation type (skip)
            pos += 1

        elif cmd == 0xCD:
            # Modulation range (skip)
            pos += 1

        elif cmd == 0xCE:
            # Portamento on/off (skip)
            pos += 1

        elif cmd == 0xCF:
            # Portamento time (skip)
            pos += 1

        elif cmd == 0xD0:
            # Attack rate (skip)
            pos += 1

        elif cmd == 0xD1:
            # Decay rate (skip)
            pos += 1

        elif cmd == 0xD2:
            # Sustain rate (skip)
            pos += 1

        elif cmd == 0xD3:
            # Release rate (skip)
            pos += 1

        elif cmd == 0xD4:
            # Loop start
            if pos < len(data):
                pos += 1  # loop count

        elif cmd == 0xD5:
            # Expression (skip)
            pos += 1

        elif cmd == 0xD6:
            # Print variable (skip)
            pos += 1

        elif cmd == 0xE0:
            # Modulation delay (skip)
            pos += 2

        elif cmd == 0xE1:
            # Tempo
            if pos + 1 < len(data):
                pos += 2  # tempo value

        elif cmd == 0xE3:
            # Sweep pitch (skip)
            pos += 2

        elif cmd == 0xFC:
            # Loop end — jump back handled by loop tracking
            pass

        elif cmd == 0xFD:
            # Return from call
            if call_stack:
                pos = call_stack.pop()

        elif cmd == 0xFF:
            # End of track
            break

        else:
            # Unknown command — try to skip gracefully
            pass

    return events


# Cache for decoded wave samples
_wave_cache: dict[tuple, list[int]] = {}


def _lookup_sample(bank, program: int, note: int, wave_archives) -> tuple[int, int, int, int] | None:
    """Look up which SWAR sample to use for a given program + note.
    NDS SFX banks often use note number as instrument index.
    Returns (wave_id, wave_archive_id, base_sample_rate, base_note) or None."""
    if bank is None:
        return None

    instruments = bank.instruments if hasattr(bank, 'instruments') else []

    # Strategy 1: Use note number as instrument index (standard for NDS SFX banks)
    inst = None
    if note < len(instruments) and instruments[note] is not None:
        inst = instruments[note]

    # Strategy 2: Use program number as instrument index
    if inst is None and program < len(instruments) and instruments[program] is not None:
        inst = instruments[program]

    # No fallback — if neither matches, this note has no valid instrument
    if inst is None:
        return None

    nd = inst.noteDefinition if hasattr(inst, 'noteDefinition') else None
    if nd is None:
        return None

    wave_id = nd.waveID
    warc_id_id = nd.waveArchiveIDID
    base_note = nd.pitch

    # Resolve wave archive ID through bank's waveArchiveIDs table
    warc_id = 0
    if hasattr(bank, 'waveArchiveIDs') and warc_id_id < len(bank.waveArchiveIDs):
        warc_id = bank.waveArchiveIDs[warc_id_id]

    # Get sample rate from the actual wave
    sample_rate = 22050
    if warc_id < len(wave_archives) and wave_archives[warc_id] is not None:
        _, swar = wave_archives[warc_id]
        if swar and wave_id < len(swar.waves):
            sample_rate = swar.waves[wave_id].sampleRate

    return (wave_id, warc_id, sample_rate, base_note)


def get_decoded_sample(wave_archives, swar_id: int, swav_id: int) -> list[int]:
    """Get decoded PCM16 samples, with caching."""
    key = (swar_id, swav_id)
    if key in _wave_cache:
        return _wave_cache[key]

    if swar_id >= len(wave_archives) or wave_archives[swar_id] is None:
        return []
    _, swar = wave_archives[swar_id]
    if swar is None or swav_id >= len(swar.waves):
        return []

    samples = decode_swav(swar.waves[swav_id])
    _wave_cache[key] = samples
    return samples


def render_events(events: list[NoteEvent], wave_archives, bank, tempo_bpm: int = 120) -> list[int]:
    """Render NoteEvent list to PCM16 samples."""
    if not events:
        return []

    # Calculate total duration
    ticks_per_beat = 48  # NDS default
    samples_per_tick = SAMPLE_RATE * 60.0 / (tempo_bpm * ticks_per_beat)

    max_end_tick = max(e.start_tick + e.duration_ticks for e in events)
    total_samples = int(max_end_tick * samples_per_tick) + SAMPLE_RATE  # + 1s padding
    total_samples = min(total_samples, SAMPLE_RATE * MAX_RENDER_SECONDS)

    output = [0.0] * total_samples

    for event in events:
        pcm = get_decoded_sample(wave_archives, event.warc_id, event.wave_id)
        if not pcm:
            continue

        # Semitone difference → playback rate
        semitone_diff = event.note - event.base_note
        rate_ratio = 2.0 ** (semitone_diff / 12.0) * (event.base_rate / SAMPLE_RATE)
        swar_id = event.warc_id

        # Volume
        vol = (event.velocity / 127.0) * (event.volume / 127.0) * MASTER_VOLUME

        # Render into output buffer
        start_sample = int(event.start_tick * samples_per_tick)
        duration_samples = int(event.duration_ticks * samples_per_tick)

        src_pos = 0.0
        for i in range(duration_samples):
            out_idx = start_sample + i
            if out_idx >= total_samples:
                break

            src_idx = int(src_pos)
            if src_idx >= len(pcm):
                # Check if sample loops
                swav = None
                if swar_id < len(wave_archives) and wave_archives[swar_id]:
                    _, swar = wave_archives[swar_id]
                    if swar and event.wave_id < len(swar.waves):
                        swav = swar.waves[event.wave_id]
                if swav and swav.isLooped and swav.loopOffset > 0:
                    loop_start = swav.loopOffset
                    loop_len = len(pcm) - loop_start
                    if loop_len > 0:
                        src_idx = loop_start + ((src_idx - loop_start) % loop_len)
                    else:
                        break
                else:
                    break

            if src_idx < len(pcm):
                # Simple envelope: quick attack, sustain, release at end
                env = 1.0
                release_samples = min(500, duration_samples // 4)
                remaining = duration_samples - i
                if remaining < release_samples:
                    env = remaining / release_samples

                output[out_idx] += pcm[src_idx] * vol * env

            src_pos += rate_ratio

    # Normalize and convert to int16
    peak = max(abs(s) for s in output) if output else 1.0
    if peak < 1.0:
        peak = 1.0
    scale = 32000.0 / peak

    # Trim trailing silence
    end = len(output) - 1
    while end > 0 and abs(output[end]) < 1.0:
        end -= 1
    end = min(end + int(SAMPLE_RATE * 0.1), len(output))  # 100ms tail

    result = [max(-32768, min(32767, int(s * scale))) for s in output[:end]]
    return result


## Cache for extracted SSAR event data (keyed by seqarc_idx)
_ssar_data_cache: dict[int, bytes] = {}
_ssar_seq_offsets: dict[int, list[tuple[int, int, int]]] = {}  # seqarc_idx → [(offset, bankID, vol)]


def _extract_ssar_data(sdat, seqarc_idx: int) -> tuple[bytes, list[tuple[int, int, int]]]:
    """Extract raw event data and sequence offsets from an SSAR."""
    if seqarc_idx in _ssar_data_cache:
        return _ssar_data_cache[seqarc_idx], _ssar_seq_offsets[seqarc_idx]

    _, seqarc = sdat.sequenceArchives[seqarc_idx]
    raw_data, _, _ = seqarc.save()

    # Parse SSAR header
    header_size = struct.unpack_from('<H', raw_data, 12)[0]
    data_start = header_size + 8  # Skip DATA block header
    data_offset = struct.unpack_from('<I', raw_data, data_start)[0]
    seq_count = struct.unpack_from('<I', raw_data, data_start + 4)[0]

    event_data = bytes(raw_data[data_start + data_offset:])

    seq_info = []
    for i in range(seq_count):
        entry_base = data_start + 8 + i * 12
        offset = struct.unpack_from('<I', raw_data, entry_base)[0]
        bank_id = struct.unpack_from('<H', raw_data, entry_base + 4)[0]
        volume = raw_data[entry_base + 6]
        seq_info.append((offset, bank_id, volume))

    _ssar_data_cache[seqarc_idx] = event_data
    _ssar_seq_offsets[seqarc_idx] = seq_info
    return event_data, seq_info


def render_sseq_to_wav(sdat, seqarc_idx: int, seq_idx: int, out_path: str) -> bool:
    """Render a single SSEQ sequence to WAV."""
    sa_entry = sdat.sequenceArchives[seqarc_idx]
    if sa_entry is None:
        return False
    _, seqarc = sa_entry

    seq_entry = seqarc.sequences[seq_idx]
    if seq_entry is None:
        return False
    seq_name, seq = seq_entry

    # Get raw event data and sequence offset
    event_data, seq_info = _extract_ssar_data(sdat, seqarc_idx)
    if seq_idx >= len(seq_info):
        return False

    offset, bank_id, seq_vol = seq_info[seq_idx]
    data = event_data[offset:]

    # Find the bank
    bank = None
    if bank_id < len(sdat.banks) and sdat.banks[bank_id] is not None:
        _, bank_data = sdat.banks[bank_id]
        if bank_data:
            bank = bank_data

    # Parse and render
    events = parse_sseq_events(data, bank, sdat.waveArchives)
    if not events:
        return False

    # Apply sequence volume
    for ev in events:
        ev.volume = int(ev.volume * seq_vol / 127)

    samples = render_events(events, sdat.waveArchives, bank)
    if not samples or len(samples) < 100:
        return False

    # Write WAV
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    pcm_data = array.array('h', samples).tobytes()
    with wave.open(out_path, 'wb') as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SAMPLE_RATE)
        wf.writeframes(pcm_data)

    return True


def render_all(sdat_path: str, out_dir: str):
    """Render all sequences from an SDAT file."""
    sdat = ndspy.soundArchive.SDAT.fromFile(sdat_path)
    total = 0
    success = 0

    for i, sa_entry in enumerate(sdat.sequenceArchives):
        if sa_entry is None:
            continue
        arc_name, seqarc = sa_entry

        for j, seq_entry in enumerate(seqarc.sequences):
            if seq_entry is None:
                continue
            seq_name, _ = seq_entry
            total += 1

            out_path = os.path.join(out_dir, f"{seq_name}.wav")
            try:
                if render_sseq_to_wav(sdat, i, j, out_path):
                    dur = os.path.getsize(out_path) / (SAMPLE_RATE * 2)
                    print(f"  OK: {seq_name} ({dur:.1f}s)")
                    success += 1
                else:
                    print(f"  SKIP: {seq_name} (no events)")
            except Exception as e:
                print(f"  ERR: {seq_name}: {e}")

    return total, success


def main():
    sound_dir = Path(__file__).resolve().parent.parent.parent.parent / "psz-asset-viewer" / "raw" / "sound"
    out_base = Path("/tmp/psz_sfx_rendered")

    sdat_files = {
        "se": "sound_data_se.sdat",
        "se_arm": "sound_data_se_arm.sdat",
        "se_enemy": "sound_data_se_enemy.sdat",
    }

    grand_total = 0
    grand_success = 0

    for label, fname in sdat_files.items():
        path = sound_dir / fname
        if not path.exists():
            print(f"SKIP: {path} not found")
            continue

        out_dir = out_base / label
        print(f"\n=== {label}: {path} ===")
        total, success = render_all(str(path), str(out_dir))
        print(f"  {success}/{total} rendered")
        grand_total += total
        grand_success += success

    print(f"\n=== TOTAL: {grand_success}/{grand_total} rendered to {out_base} ===")


if __name__ == "__main__":
    main()
