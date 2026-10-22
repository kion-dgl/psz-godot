#!/usr/bin/env python3
"""Python reference for the PSZ RNG port (scripts/utils/psz_rng.gd).

Mirrors pszm-decomp FUN_0203e874 / FUN_02045d84 / FUN_02045d5c exactly.
Use `--vectors` to print GDScript-ready test vectors consumed by
scripts/tools/psz_rng_check.gd.
"""
import sys

MASK64 = (1 << 64) - 1


class PszRngRef:
    def __init__(self, seed0=0, seed1=0, seed2=0):
        self.s = [seed0 & MASK64, seed1 & MASK64, seed2 & MASK64]

    def bounded(self, n):
        acc = (self.s[2] + self.s[1] * self.s[0]) & MASK64
        self.s[0] = acc
        if n == 0:
            return acc >> 32
        return ((acc >> 32) * n) >> 32

    def percent(self, pct):
        if pct >= 100:
            return True
        if pct <= 0:
            return False
        return self.bounded(100) < pct

    def range(self, lo, hi):
        return lo + self.bounded(hi - lo) if hi > lo else lo


VECTORS = [
    # (seed0, seed1, seed2, ops) — ops: ("b", n) | ("p", pct) | ("r", lo, hi)
    (0x12345678, 0x9ABCDEF0, 0x0F0F0F0F, [("b", 100)] * 8 + [("b", 0)] + [("b", 1000000)]),
    (1, 1, 1, [("b", 100)] * 6 + [("p", 50), ("p", 50), ("p", 50)]),
    (0xDEADBEEF, 0xCAFEBABE, 0x13579BDF, [("r", 158, 174), ("r", 0, 10), ("r", 10, 0)] + [("b", 100)] * 4),
    (0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, [("b", 100)] * 8),
    (0x00000000, 0x00000001, 0x00000000, [("b", 100)] * 8),
]


def run_vectors():
    out = []
    for seed0, seed1, seed2, ops in VECTORS:
        rng = PszRngRef(seed0, seed1, seed2)
        results = []
        for op in ops:
            if op[0] == "b":
                results.append(rng.bounded(op[1]))
            elif op[0] == "p":
                results.append(1 if rng.percent(op[1]) else 0)
            else:
                results.append(rng.range(op[1], op[2]))
        out.append((seed0, seed1, seed2, results))
    return out


if __name__ == "__main__":
    rows = run_vectors()
    if "--vectors" in sys.argv:
        print("const VECTORS := [")
        for (seed0, seed1, seed2, ops), (_, _, _, results) in zip(VECTORS, rows):
            ops_gd = "[" + ", ".join(f'["{o[0]}", {", ".join(str(x) for x in o[1:])}]' for o in ops) + "]"
            print(f"\t[0x{seed0:08X}, 0x{seed1:08X}, 0x{seed2:08X}, {ops_gd}, {results}],")
        print("]")
    else:
        for seed0, seed1, seed2, results in rows:
            print(f"seed 0x{seed0:08X}/0x{seed1:08X}/0x{seed2:08X}: {results}")
