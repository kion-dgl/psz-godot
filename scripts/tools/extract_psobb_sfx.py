#!/usr/bin/env python3
"""
Extract WAV sound effects from PSOBB .pac sound archives.

PAC format: repeated blocks of [28-byte padding] + [16-byte WAVEFORMATEX] + ['data' + size + PCM audio].
First block starts at offset 0 (no padding before the first WAVEFORMATEX).

Usage:
  python3 extract_psobb_sfx.py <pac_dir> <output_dir>

Defaults:
  pac_dir:    /tmp/ephinea/data/sound/
  output_dir: /tmp/psobb_sfx/
"""

import struct
import wave
import os
import sys


def extract_pac(pac_path: str, out_dir: str) -> int:
    """Extract WAV files from a PSOBB PAC sound archive."""
    with open(pac_path, 'rb') as f:
        data = f.read()

    os.makedirs(out_dir, exist_ok=True)
    basename = os.path.splitext(os.path.basename(pac_path))[0]

    pos = 0
    count = 0

    while pos + 24 < len(data):
        # Find WAVEFORMATEX: fmt_tag=1 (PCM), channels=1 or 2
        if data[pos:pos+2] == b'\x01\x00' and data[pos+2] in [1, 2] and data[pos+3] == 0:
            channels = struct.unpack_from('<H', data, pos+2)[0]
            sample_rate = struct.unpack_from('<I', data, pos+4)[0]
            block_align = struct.unpack_from('<H', data, pos+12)[0]
            bits = struct.unpack_from('<H', data, pos+14)[0]

            if 8000 <= sample_rate <= 48000 and bits in [8, 16] and block_align > 0:
                # Check for 'data' chunk right after 16-byte header
                if pos + 20 < len(data) and data[pos+16:pos+20] == b'data':
                    chunk_size = struct.unpack_from('<I', data, pos+20)[0]
                    audio_start = pos + 24

                    if chunk_size > 32 and audio_start + chunk_size <= len(data):
                        out_path = os.path.join(out_dir, f"{basename}_{count:03d}.wav")
                        with wave.open(out_path, 'wb') as wf:
                            wf.setnchannels(channels)
                            wf.setsampwidth(bits // 8)
                            wf.setframerate(sample_rate)
                            wf.writeframes(data[audio_start:audio_start+chunk_size])
                        count += 1
                        pos = audio_start + chunk_size
                        continue
        pos += 1

    return count


def main():
    pac_dir = sys.argv[1] if len(sys.argv) > 1 else '/tmp/ephinea/data/sound/'
    out_dir = sys.argv[2] if len(sys.argv) > 2 else '/tmp/psobb_sfx/'

    total = 0
    for f in sorted(os.listdir(pac_dir)):
        if not f.endswith('.pac'):
            continue
        pac_path = os.path.join(pac_dir, f)
        name = f.replace('.pac', '')
        count = extract_pac(pac_path, os.path.join(out_dir, name))
        total += count
        print(f"  {name}: {count} sounds")

    print(f"\nTotal: {total} sounds extracted to {out_dir}")


if __name__ == '__main__':
    main()
