#!/usr/bin/env python3
"""Reference implementation of the original PSZ field generator, and its
fixture tests.

The growth model (Rng/Room/Gen) is a direct port of psz-re's
tools/generate.py — the oracle that reproduces 7 of 9 savestate fields —
which itself implements the decompiled generation path (see
data/re_reference/level_generation_algorithm.json for the function-by-function
evidence). The transcription stage implements the draw model validated by
psz-re tools/forward.py (draw order per room: rotation, variant, key
shuffle, seed, layout category).

Validation modes (--check):
  growth        run Gen from each fixture's generation_start_state and
                compare the normalized cell set and room count. This is the
                oracle test; no gate-stage knowledge required.
  transcription for each growth-reproduced fixture, anchor the draw stream
                on the fixture's first per-room seed, then verify every later
                seed lands exactly where the per-room draw model predicts
                (gap test), and that predicted rotations / keys / layout
                categories match the recorded values.

The gate stage (params 4..8, FUN_020b2xxx) sits between growth and
transcription and is NOT modelled — its draw cost is absorbed by the
anchor search, which is why transcription validation starts from the first
seed rather than the generation state.

Usage:
  python3 scripts/tools/field_gen_reference.py --check
"""
from __future__ import annotations

import argparse
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
MASK = (1 << 64) - 1
M = 0x5D588B656C078965
C = 0x269EC3

GRID_W, GRID_H = 7, 10
DELTA = [(0, -1), (1, 0), (0, 1), (-1, 0)]      # 0x020f2ef8
OPPOSITE = [2, 3, 0, 1]                          # 0x020f2ee8
START_X = 3                                      # FUN_02081f98, params[9] >= 0
F_BLOCKED, F_OCCUPIED, F_START, F_GOAL = 1, 2, 4, 8

# variant table at 0x020f5978: shape -> (classId, digit) pairs
VARIANTS = {
    0: [(1, 1), (1, 2), (2, 1), (2, 3)],   # i: b1 b2 c1 c3
    1: [(1, 1), (1, 3), (2, 1), (2, 2)],   # l: b1 b3 c1 c2
    2: [(1, 3), (2, 3), (3, 1), (3, 2)],   # t: b3 c3 d1 d2
    3: [(1, 2)],                            # x: b2
    4: [(0, 1), (1, 2), (2, 2)],            # n: a1 b2 c2
    5: [(0, 1)],                            # s: a1
    6: [(0, 1)],                            # g: a1
}
SHAPE_LETTERS = "iltxnsg"
CLASS_LETTERS = "abcdr"
# layout (+0x31) weight rows by depth band, table 0x020f2e70
LAYOUT_BANDS = [(50, 20, 20, 10), (40, 20, 20, 20), (25, 25, 25, 25)]


class Lcg:
    def __init__(self, state: int):
        self.state = state & MASK

    def step(self) -> None:
        self.state = (self.state * M + C) & MASK

    def back(self) -> None:
        m_inv = pow(M, -1, 1 << 64)
        self.state = ((self.state - C) * m_inv) & MASK

    @staticmethod
    def value(state: int, rng: int) -> int:
        if rng == 0:
            return state >> 32
        return ((state >> 32) * rng) >> 32


class Rng:
    """psz-re's wrapper: the FIRST draw uses the given state without stepping
    (the passed state is already one step ahead of the last consumed value);
    every later draw steps first. Shuffles skip lists of <= 1 element."""

    def __init__(self, state: int):
        self.lcg = Lcg(state)
        self.first = True
        self.n = 0

    def draw(self, rng: int) -> int:
        if self.first:
            self.first = False
        else:
            self.lcg.step()
        self.n += 1
        return Lcg.value(self.lcg.state, rng)

    def shuffle(self, arr: list) -> None:
        if len(arr) <= 1:
            return
        for i in range(len(arr)):
            j = self.draw(len(arr))
            arr[i], arr[j] = arr[j], arr[i]


class Room:
    __slots__ = ("x", "y", "flags", "doors", "depth", "index", "adj", "wayback",
                 "shape", "rotation", "variant", "keys", "key_ids", "seed", "layout", "code")

    def __init__(self, x, y, index, depth):
        self.x, self.y = x, y
        self.flags = F_OCCUPIED
        self.doors = 0
        self.depth = depth
        self.index = index
        self.adj = [-1, -1, -1, -1]
        self.wayback = -1
        self.shape = self.rotation = self.variant = -1
        self.keys = 0
        self.key_ids = []
        self.seed = 0
        self.layout = -1
        self.code = ""


class Gen:
    """The 0x8a0 generator object — ported from psz-re tools/generate.py."""

    def __init__(self, rng: Rng, params=None):
        self.r = rng
        self.cells: dict = {}
        self.queue: list = []
        self.list: list = []
        self.counter = 0
        self.target = 0
        self.branch = 0
        self.linear = 0
        p = params or [10, 13, 1, 3, 50, 25, 50, 10, 75, 3, 0]
        self.p = list(p)
        self.area = (p[0], p[1], p[2], p[3])
        self.start_y = 9 - p[9]

    @property
    def actual(self) -> int:
        return len(self.list)

    def place(self, parent: Room, direction: int) -> bool:          # FUN_0208209c
        if parent.x < 0 or parent.y < 0:
            return False
        dx, dy = DELTA[direction]
        x, y = parent.x + dx, parent.y + dy
        if not (0 <= x < GRID_W and 0 <= y < GRID_H):
            return False
        if (x, y) in self.cells:
            return False
        child = Room(x, y, self.counter, parent.depth + 1)
        self.counter += 1
        child.doors = 1
        child.wayback = OPPOSITE[direction]
        child.adj[OPPOSITE[direction]] = parent.index
        parent.adj[direction] = child.index
        parent.doors += 1
        self.cells[(x, y)] = child
        self.queue.append(child)
        self.list.append(child)
        return True

    def child_count(self, remaining: int) -> int:                    # FUN_020833ac
        a, b = self.branch, self.linear
        if a + b == 0:
            return 0
        if self.r.draw(a + b) >= a:
            return 0
        if a * 2 < remaining:
            if a < 2:
                return 1
            return 2 if self.r.draw(100) < 30 else 1
        return 2 if a > 2 else a

    def spend(self, n: int) -> None:                                 # FUN_0208340c
        if n == 0:
            if self.linear:
                self.linear -= 1
        elif n <= self.branch:
            self.branch -= n

    def spawn(self, room: Room, want: int) -> int:                   # FUN_02082050
        bag = [0, 1, 2, 3]
        self.r.shuffle(bag)
        made = 0
        while bag:
            if self.target <= self.actual:
                break
            d = bag.pop()
            if self.place(room, d):
                made += 1
                if made >= want:
                    break
        return made

    def grow(self) -> None:                                          # FUN_020821d0
        while self.queue:
            self.r.shuffle(self.queue)
            room = self.queue.pop()
            if self.target <= self.actual:
                return
            n = self.child_count(self.target - self.actual)
            made = self.spawn(room, n + 1)
            if made:
                self.spend(made - 1)

    def extend(self) -> None:                                        # FUN_02082228
        self.r.shuffle(self.list)
        for room in self.list:
            if not (room.flags & F_START) and room.doors < 4:
                n = self.child_count(self.target - self.actual) or 1
                made = self.spawn(room, n)
                if made:
                    self.spend(made)
                    room.flags |= 0x10
                    return

    def run(self) -> None:                                           # FUN_02081ea8
        lo, hi = self.area[0], self.area[1]
        self.target = 10 if (lo < 2 or hi < lo or hi > 0x13) else lo + (
            self.r.draw(hi - lo) if hi != lo else 0)
        s_lo, s_hi = self.area[2], self.area[3]
        second = 0
        if 0 <= s_lo <= s_hi < 9:
            second = s_lo + (self.r.draw(s_hi - s_lo) if s_hi != s_lo else 0)
        self.branches_drawn = second
        self.branch = second
        self.linear = max(0, self.target - second * 2 - 1)           # FUN_02083378
        start = Room(START_X, self.start_y, self.counter, 0)         # FUN_02081f98
        self.counter += 1
        start.flags |= F_START
        self.cells[(start.x, start.y)] = start
        self.list.append(start)
        self.place(start, 0)   # the start's one deterministic north child, no bag
        self.grow()
        if self.actual < self.target:
            self.extend()
            self.grow()

    # ---- transcription (draw model from level_generation_algorithm.json /
    # ---- psz-re tools/forward.py). Gates are NOT modelled; the caller
    # ---- anchors the stream on the first recorded per-room seed.

    def normalized(self):
        ox = min(x for x, _ in self.cells)
        oy = min(y for _, y in self.cells)
        return {(x - ox, y - oy) for x, y in self.cells}, (ox, oy)

    def select_goal(self) -> Room | None:                            # FUN_020822ac, params[10]=0
        cands = [r for r in self.list
                 if not (r.flags & F_START) and r.doors == 1 and r.depth > 3]
        if not cands:
            cands = [r for r in self.list
                     if not (r.flags & F_START) and r.doors == 1]
            if not cands:
                return None
        return cands[self.r.draw(len(cands))]

    def shape_and_rotation(self, room: Room, goal: Room) -> None:    # FUN_020826ec
        if room.doors == 4:
            room.shape = 3
            room.rotation = self.r.draw(4)
        elif room.doors == 3:
            room.shape = 2
            room.rotation = next(d for d in range(4) if room.adj[d] < 0)
        elif room.doors == 2:
            dirs = [d for d in range(4) if room.adj[d] >= 0]
            if (dirs[0] + dirs[1]) % 2 == 0:      # opposite walls: i
                room.shape = 0
                north_free = room.adj[0] < 0
                room.rotation = self.r.draw(2) * 2 + (0 if north_free else 1)
            else:
                room.shape = 1                    # corner
                room.rotation = next(i for i in range(4)
                                     if room.adj[i] >= 0 and room.adj[(i + 1) % 4] >= 0)
        else:
            exit_dir = next(d for d in range(4) if room.adj[d] >= 0)
            if room.flags & F_GOAL:
                room.shape = 6
            elif room.flags & F_START:
                room.shape = 5
            else:
                room.shape = 4
            room.rotation = (exit_dir + 2) % 4

    def variant_for(self, room: Room, done: list) -> int:            # FUN_02082628
        cands = VARIANTS[room.shape]
        if len(cands) == 1:
            return 0
        used = set()
        for nb in done:
            for d in range(4):
                if room.adj[d] == nb.index:
                    used.add((nb.shape, nb.variant))
        pool = [i for i in range(len(cands))
                if (room.shape, i) not in used] or list(range(len(cands)))
        return pool[self.r.draw(len(pool))]

    def transcribe(self, order: list = None) -> None:
        goal = self.select_goal()
        if goal:
            goal.flags |= F_GOAL
        if order is None:
            order = list(self.list)
            self.r.shuffle(order)                 # FUN_020b2698's single shuffle
        for room in order:
            done = [r for r in order[:order.index(room)] if r.shape >= 0]
            self.shape_and_rotation(room, goal)
            if len(VARIANTS[room.shape]) > 1:
                room.variant = self.variant_for(room, done)
            else:
                room.variant = 0
            if room.keys:
                pair = [0, 1]
                for _ in range(2):                # Fisher-Yates over [0,1]
                    j = self.r.draw(2)
                    pair[0], pair[j] = pair[j], pair[0]
                room.key_ids = pair[:min(room.keys, 2)]
            room.seed = self.r.draw(0xFFFFFFFF)
            band = 0 if room.depth < 4 else (1 if room.depth < 7 else 2)
            w = LAYOUT_BANDS[band]
            roll = self.r.draw(100)
            acc = 0
            room.layout = 3
            for i, wi in enumerate(w):
                acc += wi
                if roll < acc:
                    room.layout = i
                    break

    def code_for(self, stage: str, room: Room) -> str:
        cls, digit = VARIANTS[room.shape][room.variant]
        return f"{stage}{CLASS_LETTERS[cls]}{digit}"


def run_growth(state: int, params):
    # generation_start_state is the state AT FUN_02081ea8's entry; the target
    # draw is generation's first draw, so it steps from this state. psz-re's
    # Rng does not step on the first draw, so hand it the stepped state.
    lcg = Lcg(state)
    lcg.step()
    g = Gen(Rng(lcg.state), params)
    g.run()
    return g


def check_growth(fixtures: list) -> int:
    ok = 0
    reproducible = []
    for f in fixtures:
        st = int(f["input"]["generation_start_state"], 16)
        params = f["input"]["params"]
        want_cells = {(r["xy"][0], r["xy"][1]) for r in f["rooms"]}
        want_n = len(f["rooms"])
        g = run_growth(st, params)
        got, _ = g.normalized()
        drawn = f["drawn"]
        t_ok = g.target == drawn["target"] and g.branches_drawn == drawn["branches"]
        if got == want_cells and g.actual == want_n and t_ok:
            ok += 1
            reproducible.append(f)
            print(f'  {f["id"]}: GROWTH OK (target {g.target}, {g.actual} rooms)')
        else:
            print(f'  {f["id"]}: growth mismatch (target {g.target} vs {drawn["target"]}, '
                  f'{g.actual} vs {want_n} rooms, {len(got & want_cells)}/{len(want_cells)} cells)')
    return ok, reproducible


def check_transcription(f: dict):
    """Anchor the stream on the first recorded seed (the gate stage between
    growth and transcription is unmodelled, so its draw cost is searched),
    then verify the whole per-room draw chain: each subsequent seed must land
    exactly layout-draw + pre-draws later, and the derived values (derived
    rotations, layout categories) must match the fixture."""
    st = int(f["input"]["generation_start_state"], 16)
    params = f["input"]["params"]
    order_idx = f.get("transcription_order")
    if not order_idx:
        return None
    rooms_by_index = {r["index"]: r for r in f["rooms"]}
    g = run_growth(st, params)
    base_state = g.r.lcg.state
    base_n = g.r.n

    def attempt(k: int, skip_variant=frozenset()):
        rng = Rng(_step_state(base_state, k))
        rng.first = False   # the stream is already positioned
        stats = {"seeds": 0, "layouts": 0}
        for idx in order_idx:
            rec = rooms_by_index[idx]
            room = next(r for r in g.list if r.index == idx)
            # pre-seed draws: rotation (x/i), variant (i/l/t/n), key shuffle.
            # Rooms the weighted picker assigned (+0x30 != 0xFF — r-class nr*
            # rooms and picker-slot na1/nc2) SKIP the variant draw; the search
            # below tries those skips when the plain chain fails.
            if rec["shape"] == "x":
                rng.draw(4)
            elif rec["shape"] == "i":
                rng.draw(2)
            if rec["shape"] in ("i", "l", "t", "n") and idx not in skip_variant:
                rng.draw(len(_variant_pool(room, rec, order_idx, rooms_by_index, g)))
            if rec.get("keys", 0):
                rng.draw(2)
                rng.draw(2)
            # the seed itself
            if rng.draw(0xFFFFFFFF) != int(rec["seed"], 16):
                return None
            stats["seeds"] += 1
            # layout category follows the seed
            roll = rng.draw(100)
            band = 0 if room.depth < 4 else (1 if room.depth < 7 else 2)
            w = LAYOUT_BANDS[band]
            acc, cat = 0, 3
            for i, wi in enumerate(w):
                acc += wi
                if roll < acc:
                    cat = i
                    break
            if cat == rec.get("layout"):
                stats["layouts"] += 1
        return stats

    def search(skip_variant=frozenset()):
        for k in range(0, 300):
            result = attempt(k, skip_variant)
            if result and result["seeds"] == len(order_idx):
                result["gate_draws"] = k
                return result
        return None

    result = search()
    if result:
        return result
    # picker-assigned rooms skip the variant draw; try the picker-code rooms
    import itertools
    cands = [r["index"] for r in f["rooms"]
             if r["code"].split("_")[1] in ("na1", "nc2", "nr1", "nr2", "nr3", "nr4", "nr5", "nr6")]
    for size in (1, 2):
        for combo in itertools.combinations(cands, size):
            result = search(frozenset(combo))
            if result:
                result["picker_rooms"] = list(combo)
                return result
    return None


def _step_state(state: int, n: int) -> int:
    lcg = Lcg(state)
    for _ in range(n):
        lcg.step()
    return lcg.state


def _variant_pool(room, rec, order_idx, rooms_by_index, g):
    shape = "iltxnsg".index(rec["shape"])
    cands = VARIANTS[shape]
    if len(cands) <= 1:
        return [0]
    seen = set()
    pos = order_idx.index(room.index)
    used = set()
    for earlier in order_idx[:pos]:
        other = next(r for r in g.list if r.index == earlier)
        erec = rooms_by_index[earlier]
        for d in range(4):
            if room.adj[d] == earlier:
                used.add(("iltxnsg".index(erec["shape"]), _variant_index(erec)))
    pool = [i for i in range(len(cands)) if (shape, i) not in used] or list(range(len(cands)))
    return pool


def _variant_index(rec) -> int:
    code = rec["code"]
    # code like s01a_sa1 -> variant part after shape char
    cls_digit = code.split("_")[1][1:]
    shape = "iltxnsg".index(rec["shape"])
    cls, digit = CLASS_LETTERS.index(cls_digit[0]) if cls_digit[0] in CLASS_LETTERS else 0, int(cls_digit[1])
    try:
        return [cv for cv in VARIANTS[shape]].index((cls, digit))
    except ValueError:
        return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", default="growth")
    args = ap.parse_args(argv)
    fixtures = json.loads((ROOT / "data/re_reference/field_fixtures.json").read_text())["fixtures"]
    if args.check == "growth":
        ok, _ = check_growth(fixtures)
        print(f"growth: {ok}/{len(fixtures)} fixtures reproduced")
    elif args.check == "transcription":
        _, repro = check_growth(fixtures)
        hits = sum(1 for f in repro if check_transcription(f))
        print(f"transcription: {hits}/{len(repro)} growth-reproduced fixtures seed-anchored")
    return 0


if __name__ == "__main__":
    sys.exit(main())
