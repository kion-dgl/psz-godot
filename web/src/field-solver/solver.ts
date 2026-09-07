/**
 * Field solver — the route a player walks through a generated section.
 *
 * A TypeScript port of the AUTOPILOT's planner (autopilot.gd
 * _plan_key_detours / _visit_walk / _emit_visit_step), not of the generator:
 * the field itself always comes from the GridGenerator dump, so there is no
 * second implementation to drift. The planner is the right thing to port
 * because it IS the spec of how a player routes: main path start→goal, a
 * detour out-and-back for each key whose gate sits on that path, fights and
 * gate spends in order.
 *
 * Solvability itself is checked independently by the same purse-walk the
 * Godot test uses (_section_is_solvable): reachability to a fixed point
 * where enemy-defeat doors are free and key doors cost their attribute.
 */

export interface FieldObject {
  type: string;
  enemy_id?: string;
  position?: [number, number, number];
  authored?: boolean;
}

export interface Cell {
  pos: string;
  stage_id: string;
  rotation: number;
  connections: Record<string, string>;
  portals?: Record<string, string>;
  objects?: FieldObject[];
  is_start: boolean;
  is_end: boolean;
  is_branch: boolean;
  has_key: boolean;
  key_for_cell: string;
  is_key_gate: boolean;
  key_gate_direction: string;
  warp_edge: string;
  path_order: number;
  door_attributes?: Record<string, number>;
  entry_warp_edge?: string;
  key_count?: number;
  required_keys?: number;
}

export interface Section {
  type: string;
  area: string;
  cells: Cell[];
  start_pos: string;
  end_pos: string;
}

export interface Roll {
  seed: number;
  sections: Section[];
}

export interface Area {
  area_id: string;
  display_name: string;
  prefix: string;
  rolls: Roll[];
}

export interface Dump {
  difficulty: string;
  grid_size: number;
  areas: Area[];
}

/** Door attributes, the original game's own values (GridGenerator.ATTR_*). */
export const ATTR_OPEN = 0;
export const ATTR_ONE_KEY = 1;
export const ATTR_TWO_KEY = 2;
export const ATTR_ENEMY_DEFEAT = 4;

export function attrOf(cell: Cell, dir: string): number {
  return cell.door_attributes?.[dir] ?? ATTR_OPEN;
}

export function enemyCount(cell: Cell): number {
  return (cell.objects ?? []).filter((o) => o.type === 'enemy').length;
}

export function keysHeldBy(cell: Cell): number {
  return cell.key_count ?? (cell.has_key ? 1 : 0);
}

// ── Graph helpers ───────────────────────────────────────────────────────────

type ByPos = Map<string, Cell>;

export function byPos(section: Section): ByPos {
  return new Map(section.cells.map((c) => [c.pos, c]));
}

function dirTo(cell: Cell, nextPos: string): string {
  for (const [dir, target] of Object.entries(cell.connections)) {
    if (target === nextPos) return dir;
  }
  return '';
}

/** BFS shortest path (inclusive of both ends), mirroring _bfs_path. */
export function bfsPath(map: ByPos, from: string, to: string): string[] {
  const prev = new Map<string, string>([[from, '']]);
  const frontier = [from];
  while (frontier.length) {
    const cur = frontier.shift() as string;
    if (cur === to) break;
    const cell = map.get(cur);
    if (!cell) continue;
    for (const next of Object.values(cell.connections)) {
      if (!prev.has(next) && map.has(next)) {
        prev.set(next, cur);
        frontier.push(next);
      }
    }
  }
  if (!prev.has(to)) return [];
  const path: string[] = [];
  let walk = to;
  while (prev.has(walk)) {
    path.unshift(walk);
    if (walk === from) break;
    walk = prev.get(walk) as string;
  }
  return path[0] === from ? path : [];
}

// ── Solvability (the purse-walk from test_runner's _section_is_solvable) ────

export interface Solvability {
  solvable: boolean;
  keysDemanded: number;
  keysPlaced: number;
  /** Rooms the purse-walk proves reachable before any routing decisions. */
  reachable: Set<string>;
}

export function checkSolvability(section: Section): Solvability {
  const map = byPos(section);
  const goal = section.cells.find((c) => c.is_end)?.pos ?? section.end_pos;
  let keysDemanded = 0;
  for (const cell of section.cells) {
    for (const a of Object.values(cell.door_attributes ?? {})) {
      if (a === ATTR_ONE_KEY || a === ATTR_TWO_KEY) keysDemanded += a;
    }
  }
  const keysPlaced = section.cells.reduce((n, c) => n + keysHeldBy(c), 0);

  const reached = new Set<string>([section.start_pos]);
  let changed = true;
  while (changed) {
    changed = false;
    let held = 0;
    for (const pos of reached) held += keysHeldBy(map.get(pos) as Cell);
    let spent = 0;
    for (const pos of [...reached]) {
      const cell = map.get(pos);
      if (!cell) continue;
      for (const [dir, next] of Object.entries(cell.connections)) {
        if (reached.has(next) || !map.has(next)) continue;
        const a = attrOf(cell, dir);
        const cost = a === ATTR_ONE_KEY || a === ATTR_TWO_KEY ? a : 0;
        if (cost > held - spent) continue;
        spent += cost;
        reached.add(next);
        changed = true;
      }
    }
  }
  return {
    solvable: !goal || reached.has(goal),
    keysDemanded,
    keysPlaced,
    reachable: reached,
  };
}

// ── Route planner (the autopilot's visit walk) ──────────────────────────────

export type StepKind = 'enter' | 'clear' | 'key' | 'gate' | 'warp' | 'boss';

export interface SolverStep {
  kind: StepKind;
  /** The room the step happens in. */
  pos: string;
  text: string;
  /** Keys in hand AFTER this step (gate steps spend, key steps gain). */
  keysAfter: number;
  enemies?: number;
  gateDir?: string;
  cost?: number;
}

export interface Route {
  steps: SolverStep[];
  /** The ordered room sequence (the visit walk, detour round-trips included). */
  walk: string[];
}

/**
 * Where to detour for keys: for each key room, the junction is the last
 * main-path room on start→key; detour there only when an on-path key gate
 * comes at or after that junction — keys for off-path gates are not needed
 * to finish, exactly the autopilot's rule.
 */
export function planKeyDetours(map: ByPos, main: string[], start: string): Map<string, string[]> {
  const mainIdx = new Map(main.map((p, i) => [p, i]));
  let lastGateIdx = -1;
  for (let i = 0; i + 1 < main.length; i++) {
    const cell = map.get(main[i]);
    if (cell?.is_key_gate && cell.key_gate_direction === dirTo(cell, main[i + 1])) {
      lastGateIdx = i;
    }
  }
  const detours = new Map<string, string[]>();
  for (const [pos, cell] of map) {
    if (keysHeldBy(cell) <= 0) continue;
    const path = bfsPath(map, start, pos);
    if (!path.length) continue;
    let junction = start;
    for (const p of path) if (mainIdx.has(p)) junction = p;
    const at = mainIdx.get(junction) ?? 0;
    if (at <= lastGateIdx) {
      const list = detours.get(junction) ?? [];
      list.push(pos);
      detours.set(junction, list);
    }
  }
  return detours;
}

/** The ordered visit walk start→goal with a round-trip inserted per detour. */
export function visitWalk(map: ByPos, main: string[], detours: Map<string, string[]>): string[] {
  if (!main.length) return [];
  const walk = [main[0]];
  for (let mi = 1; mi < main.length; mi++) {
    const junction = main[mi - 1];
    for (const keyPos of detours.get(junction) ?? []) {
      const dp = bfsPath(map, junction, keyPos);
      for (let i = 1; i < dp.length; i++) walk.push(dp[i]);
      for (let i = dp.length - 2; i >= 0; i--) walk.push(dp[i]);
    }
    walk.push(main[mi]);
  }
  return walk;
}

export function planRoute(section: Section): Route {
  const map = byPos(section);
  const start = section.start_pos;
  const goalCell = section.cells.find((c) => c.is_end);
  const goal = goalCell?.pos ?? section.end_pos;
  const main = bfsPath(map, start, goal);
  const walk = main.length
    ? visitWalk(map, main, planKeyDetours(map, main, start))
    : [start];

  const steps: SolverStep[] = [];
  const seen = new Set<string>();
  const collected = new Set<string>();
  let keys = 0;
  let keysSpent = 0;

  for (let wi = 0; wi < walk.length; wi++) {
    const pos = walk[wi];
    const cell = map.get(pos);
    if (!cell) continue;
    const first = !seen.has(pos);
    seen.add(pos);

    steps.push({
      kind: 'enter',
      pos,
      text: first
        ? `enter ${pos} — ${cell.stage_id}${cell.is_start ? ' (start)' : ''}`
        : `back through ${pos}`,
      keysAfter: keys,
    });

    if (first) {
      const enemies = enemyCount(cell);
      if (enemies > 0) {
        steps.push({
          kind: 'clear',
          pos,
          text: `clear the room — ${enemies} enemie${enemies === 1 ? '' : 's'} down`,
          keysAfter: keys,
          enemies,
        });
      }
      const held = keysHeldBy(cell);
      if (held > 0 && !collected.has(pos)) {
        collected.add(pos);
        keys += held;
        steps.push({
          kind: 'key',
          pos,
          text: `pick up ${held} key${held === 1 ? '' : 's'} (for the gate at ${cell.key_for_cell})`,
          keysAfter: keys,
        });
      }
    }

    if (wi + 1 < walk.length) {
      const next = walk[wi + 1];
      const dir = dirTo(cell, next);
      if (cell.is_key_gate && cell.key_gate_direction === dir) {
        const cost = cell.required_keys ?? 1;
        keys -= cost;
        keysSpent += cost;
        steps.push({
          kind: 'gate',
          pos,
          text: `spend ${cost} key${cost === 1 ? '' : 's'} — ${dir} gate opens`,
          keysAfter: keys,
          gateDir: dir,
          cost,
        });
      }
    } else if (section.type === 'boss') {
      steps.push({
        kind: 'boss',
        pos,
        text: 'boss down — the return warp spawns',
        keysAfter: keys,
      });
    } else {
      steps.push({
        kind: 'warp',
        pos,
        text: goalCell
          ? `warp out of the section (${goalCell.warp_edge || 'in-room'} edge)`
          : 'section complete',
        keysAfter: keys,
      });
    }
  }

  return { steps, walk };
}

export function keysSpentOnRoute(steps: SolverStep[]): number {
  return steps.reduce((n, s) => n + (s.cost ?? 0), 0);
}

/** Total key copies the route's "key" steps picked up (a room may hold two). */
export function keysGainedOnRoute(steps: SolverStep[]): number {
  let n = 0;
  let prev = 0;
  for (const s of steps) {
    if (s.kind === 'key') n += s.keysAfter - prev;
    prev = s.keysAfter;
  }
  return n;
}
