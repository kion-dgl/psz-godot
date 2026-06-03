#!/usr/bin/env bun
// quest_plan — extract a symbolic plan from a quest JSON for the autopilot.
//
// Input:  data/quests/<id>.json
// Output: data/quest_plans/<id>.json
//
// What the autopilot actually needs to solve a quest under the kill_all
// assumption is the puzzle / interactable graph, not enemy positions. So per
// cell we pull: stage + rotation + connections + (key gate, key drop, switches,
// fences by link_id, NPCs, story props, dialog triggers). Counts of enemies +
// loot are kept as hints, positions dropped.
//
// Usage:
//   bun scripts/tools/quest_plan.ts <quest-id-or-json-path>
//   bun scripts/tools/quest_plan.ts --all          (every quest in data/quests)

import { readFileSync, writeFileSync, mkdirSync, readdirSync } from 'node:fs';
import { join, dirname, resolve, basename } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO = resolve(__dirname, '..', '..');

type Vec3 = [number, number, number];
type Dir = 'north' | 'south' | 'east' | 'west';

interface QuestObject {
  type: string;
  position?: Vec3;
  [k: string]: unknown;
}

interface QuestCell {
  pos: string;
  stage_id: string;
  rotation: number;
  connections: Partial<Record<Dir, string>>;
  portals?: Partial<Record<string, string>>;
  is_start: boolean;
  is_end: boolean;
  is_branch?: boolean;
  is_key_gate?: boolean;
  key_gate_direction?: string;
  key_gate_directions?: string[];
  required_keys?: number;
  key_drop?: string;
  key_drop_position?: Vec3;
  warp_edge?: string;
  path_order: number;
  objects?: QuestObject[];
}

interface QuestSection {
  type: string;
  area: string;
  start_pos: string;
  end_pos: string;
  entry_direction?: string;
  exit_direction?: string;
  cells: QuestCell[];
}

interface Quest {
  id: string;
  name: string;
  area_id: string;
  sections: QuestSection[];
}

interface CellPlan {
  pos: string;
  stageId: string;
  rotation: number;
  pathOrder: number;
  isStart: boolean;
  isEnd: boolean;
  isBranch: boolean;
  connections: Partial<Record<Dir, string>>;
  // Portal direction → portal ID. Used at step-emission time to bake the
  // stable portal ID into each step's `exit_portal_id` field so the
  // autopilot can look up the exit portal by ID (invariant) rather than by
  // direction label (subject to rotation-table drift).
  portals: Record<string, string>;
  warpEdge: string | null;
  // `direction` is the legacy single-gate field. `directions` carries the
  // full list when the cell has more than one locked portal (multi-gate
  // hubs like finding_ogi B 3,2). For single-gate cells `directions` is
  // [direction]; for multi-gate hubs `direction` is the FIRST entry in
  // `directions` (the spoke walked first), used as the default for any
  // legacy consumer that doesn't yet know about the multi-direction list.
  keyGate: { direction: string; directions: string[]; requiredKeys: number } | null;
  keyDrop: { targetCell: string; position: Vec3 | null } | null;
  switches: { position: Vec3; linkId: string | null }[];
  fences: { position: Vec3; linkId: string | null }[];
  npcs: { npcId: string; position: Vec3; animation: string | null }[];
  storyProps: { propPath: string; position: Vec3 }[];
  dialogTriggers: { position: Vec3; condition: string | null; actions: string[] | null }[];
  enemyCount: number;
  boxCount: number;
}

// Flat-step output schema. One entry per cell visit (including BFS-detour
// passthroughs and multi-visit hubs in finding_ogi-style quests). Matches
// the dict shape the autopilot's _build_steps_from_plan used to emit at
// runtime — now we emit it offline so the autopilot can be a flat-list
// executor (see /home/kion/.claude/plans/sharded-wishing-thimble.md).
interface PlanStep {
  label: string;          // "A 2,4 (passthrough)" / "B 3,2 (return)" / "A 2,0"
  do: string[];           // ordered action list: kill_all, dismiss_dialog, flip_switch, pickup_key, open_gate, pickup_quest_item, wait_quest_complete
  exit: string;           // direction to walk after the actions: "north" | "south" | "east" | "west" | ""
  exit_portal_id: string; // portal ID for the exit direction (preferred over direction label at walk time)
  target: string;         // next cell pos (e.g. "2,3") or ""
  _section_idx: number;   // section index — keys the per-cell visit count
  _pos: string;           // cell pos — keys the per-cell visit count
  stageId: string;        // duplicated from the source cell for tooling convenience
  rotation: number;       // duplicated from the source cell for tooling convenience
}

interface QuestPlan {
  questId: string;
  questName: string;
  areaId: string;
  sections: {
    type: string;
    area: string;
    startPos: string;
    endPos: string;
    entryDirection: string | null;
    exitDirection: string | null;
    cells: CellPlan[];
    steps: PlanStep[];
  }[];
}

function asVec3(v: unknown): Vec3 {
  const a = v as number[];
  return [Number(a?.[0] ?? 0), Number(a?.[1] ?? 0), Number(a?.[2] ?? 0)];
}

function planCell(cell: QuestCell): CellPlan {
  const objs = cell.objects ?? [];
  const ofType = (t: string) => objs.filter((o) => o.type === t);

  const switches = ofType('step_switch').map((o) => ({
    position: asVec3(o.position),
    linkId: (o.link_id as string) ?? null,
  }));
  const fences = ofType('fence').map((o) => ({
    position: asVec3(o.position),
    linkId: (o.link_id as string) ?? null,
  }));
  const npcs = ofType('npc').map((o) => ({
    npcId: String(o.npc_id ?? ''),
    position: asVec3(o.position),
    animation: (o.animation as string) ?? null,
  }));
  const storyProps = ofType('story_prop').map((o) => ({
    propPath: String(o.prop_path ?? ''),
    position: asVec3(o.position),
  }));
  const dialogTriggers = ofType('dialog_trigger').map((o) => ({
    position: asVec3(o.position),
    condition: (o.trigger_condition as string) ?? null,
    actions: (o.actions as string[]) ?? null,
  }));
  const enemyCount = ofType('enemy').length;
  const boxCount = ofType('box').length + ofType('rare_box').length;

  // Portal direction → portal_id. The raw cell ships this as
  // `cell.portals = { north: "portal_...", south: "portal_...", ... }`.
  // Mirror it into CellPlan so step-emission can bake the stable ID into
  // each step's exit_portal_id field.
  const portals: Record<string, string> = {};
  for (const [dir, id] of Object.entries(cell.portals ?? {})) {
    if (typeof id === 'string') portals[dir] = id;
  }

  return {
    pos: cell.pos,
    stageId: cell.stage_id,
    rotation: cell.rotation,
    pathOrder: cell.path_order,
    isStart: !!cell.is_start,
    isEnd: !!cell.is_end,
    isBranch: !!cell.is_branch,
    connections: cell.connections,
    portals,
    warpEdge: cell.warp_edge || null,
    keyGate: cell.is_key_gate
      ? (() => {
          const dirs = (cell.key_gate_directions && cell.key_gate_directions.length > 0)
            ? cell.key_gate_directions
            : (cell.key_gate_direction ? [cell.key_gate_direction] : []);
          return {
            direction: dirs[0] ?? (cell.key_gate_direction ?? ''),
            directions: dirs,
            requiredKeys: cell.required_keys ?? 1,
          };
        })()
      : null,
    // keyDrop covers two raw-format shapes:
    //   • `cell.key_drop = "<target>"` (search_and_rescue): a key spawns
    //     in this cell, target is the gate-locked cell. position is
    //     `key_drop_position`.
    //   • `cell.has_key = true` + `cell.key_for_cell = "<target>"`
    //     (the_paru_pact and later): same idea, different field names.
    //     position is `key_position`.
    // Both flatten to `{ targetCell, position }`.
    keyDrop: cell.key_drop
      ? { targetCell: cell.key_drop, position: cell.key_drop_position ? asVec3(cell.key_drop_position) : null }
      : cell.has_key
        ? { targetCell: cell.key_for_cell ?? '', position: cell.key_position ? asVec3(cell.key_position) : null }
        : null,
    switches,
    fences,
    npcs,
    storyProps,
    dialogTriggers,
    enemyCount,
    boxCount,
  };
}

// BFS through the section's cell-connection graph from `startPos` to
// `endPos`. Returns the pos list including both endpoints. Caller treats
// every cell BETWEEN the endpoints as a passthrough step. Matches the
// algorithm in autopilot.gd:_bfs_cell_path — ported here so the solver
// can emit detour passthroughs offline instead of at autopilot runtime.
function bfsCellPath(startPos: string, endPos: string, byPos: Map<string, CellPlan>): string[] {
  if (startPos === endPos) return [startPos];
  const parent = new Map<string, string>([[startPos, '']]);
  const queue: string[] = [startPos];
  while (queue.length > 0) {
    const cur = queue.shift()!;
    if (cur === endPos) {
      const out: string[] = [];
      let node: string | undefined = cur;
      while (node !== undefined && node !== '') {
        out.unshift(node);
        node = parent.get(node);
      }
      return out;
    }
    const curCell = byPos.get(cur);
    if (!curCell) continue;
    for (const next of Object.values(curCell.connections)) {
      if (!next) continue;
      if (parent.has(next)) continue;
      if (!byPos.has(next)) continue; // not in this section
      parent.set(next, cur);
      queue.push(next);
    }
  }
  // No path — trivial pair so the caller doesn't error.
  return [startPos, endPos];
}

function oppositeDirection(d: string): string {
  switch (d) {
    case 'north': return 'south';
    case 'south': return 'north';
    case 'east':  return 'west';
    case 'west':  return 'east';
    default:      return '';
  }
}

interface PreStep {
  cell: CellPlan;
  isPassthrough: boolean;
}

// BFS through a section's connection graph but refuse to step into any cell
// in `barred`. Used by hub-and-spoke planning to walk one spoke without
// crossing back through the hub.
function bfsCellPathExcluding(
  startPos: string,
  endPos: string,
  byPos: Map<string, CellPlan>,
  barred: Set<string>,
): string[] {
  if (startPos === endPos) return [startPos];
  if (barred.has(startPos)) return [];
  const parent = new Map<string, string>([[startPos, '']]);
  const queue: string[] = [startPos];
  while (queue.length > 0) {
    const cur = queue.shift()!;
    if (cur === endPos) {
      const out: string[] = [];
      let node: string | undefined = cur;
      while (node !== undefined && node !== '') {
        out.unshift(node);
        node = parent.get(node);
      }
      return out;
    }
    const curCell = byPos.get(cur);
    if (!curCell) continue;
    for (const next of Object.values(curCell.connections)) {
      if (!next) continue;
      if (parent.has(next)) continue;
      if (!byPos.has(next)) continue;
      if (barred.has(next)) continue;
      parent.set(next, cur);
      queue.push(next);
    }
  }
  return [];
}

// Find this section's hub-and-spoke geometry from a hub cell with multiple
// locked-gate directions. For each direction in `hub.keyGate.directions`, walk
// the spoke (BFS through the section, avoiding re-entering the hub) until
// reaching a cell with `keyDrop.targetCell == hub.pos` OR the section's
// end-cell. Returns the spoke cell-path for each direction (including the
// hub-neighbour cell on each end but NOT the hub itself).
function discoverSpokes(
  hub: CellPlan,
  byPos: Map<string, CellPlan>,
  sectionEndPos: string,
): { direction: string; path: string[] }[] {
  if (!hub.keyGate) return [];
  const spokes: { direction: string; path: string[] }[] = [];
  const hubBar = new Set<string>([hub.pos]);
  for (const dir of hub.keyGate.directions) {
    const startNeighbour = hub.connections[dir as Dir];
    if (!startNeighbour) continue;
    // Find any cell reachable through this gate that either drops a key for
    // the hub OR is the section's final cell. BFS-expand step by step so
    // every visited cell becomes a candidate.
    const candidates: string[] = [];
    const visited = new Set<string>(hubBar);
    visited.add(startNeighbour);
    const queue: string[] = [startNeighbour];
    while (queue.length > 0) {
      const cur = queue.shift()!;
      const curCell = byPos.get(cur);
      if (!curCell) continue;
      const dropsHubKey = curCell.keyDrop?.targetCell === hub.pos && cur !== hub.pos;
      const isSectionEnd = cur === sectionEndPos;
      if (dropsHubKey || isSectionEnd) candidates.push(cur);
      for (const next of Object.values(curCell.connections)) {
        if (!next) continue;
        if (visited.has(next)) continue;
        if (!byPos.has(next)) continue;
        visited.add(next);
        queue.push(next);
      }
    }
    if (candidates.length === 0) continue;
    // Prefer the section-end if it matches, otherwise pick the first
    // candidate that drops a hub key (which is the spoke payload).
    const target =
      candidates.find((p) => p === sectionEndPos) ?? candidates[0];
    const path = bfsCellPathExcluding(startNeighbour, target, byPos, hubBar);
    if (path.length > 0) spokes.push({ direction: dir, path });
  }
  return spokes;
}

// Multi-gate hub section: emit start→hub passthroughs, then for each spoke
// direction emit hub-visit + spoke-forward + payload + spoke-return + hub-revisit,
// closing on the final spoke's payload (which is also the section end).
function buildHubAndSpokeSteps(
  hub: CellPlan,
  spokes: { direction: string; path: string[] }[],
  startCell: CellPlan,
  byPos: Map<string, CellPlan>,
  section: QuestPlan['sections'][number],
  sectionIdx: number,
  totalSections: number,
): PlanStep[] {
  const area = (section.area || '?').toUpperCase();
  const isLastSection = sectionIdx === totalSections - 1;
  const steps: PlanStep[] = [];
  const visitedKeys = new Map<string, number>();

  const pushStep = (
    cell: CellPlan,
    actions: string[],
    exitDir: string,
    targetPos: string,
    suffix: string,
  ): void => {
    const visitN = (visitedKeys.get(cell.pos) ?? 0) + 1;
    visitedKeys.set(cell.pos, visitN);
    const label = `${area} ${cell.pos}${suffix}`;
    let exitPortalId = '';
    if (exitDir !== '' && cell.portals[exitDir]) exitPortalId = cell.portals[exitDir];
    steps.push({
      label,
      do: actions,
      exit: exitDir,
      exit_portal_id: exitPortalId,
      target: targetPos,
      _section_idx: sectionIdx,
      _pos: cell.pos,
      stageId: cell.stageId,
      rotation: cell.rotation,
    });
  };

  // ── Start → hub approach ───────────────────────────────────────
  // BFS the path from section start to the hub. Each intermediate is a
  // passthrough; the start cell itself gets a real visit (kill_all).
  const approach = bfsCellPathExcluding(startCell.pos, hub.pos, byPos, new Set());
  for (let i = 0; i < approach.length - 1; i++) {
    const cell = byPos.get(approach[i])!;
    const nextPos = approach[i + 1];
    let exitDir = '';
    for (const [d, p] of Object.entries(cell.connections)) {
      if (p === nextPos) {
        exitDir = d;
        break;
      }
    }
    const isStartLikeCell = i === 0;
    const actions: string[] = ['kill_all'];
    if (isStartLikeCell) {
      const hasNullDialog = cell.dialogTriggers.some((d) => d.condition === null && d.actions === null);
      if (hasNullDialog) actions.push('dismiss_dialog');
      if (cell.switches.length > 0) actions.push('flip_switch');
      if (cell.keyDrop !== null) actions.push('pickup_key');
      // No quest items on the approach by definition; if any quest data
      // ever puts an item on a path cell before the hub, the existing
      // single-pass code would have picked it up — keep parity with that.
    }
    pushStep(cell, actions, exitDir, nextPos, isStartLikeCell ? '' : ' (passthrough)');
  }

  // ── Hub + spokes ────────────────────────────────────────────────
  // Per-visit hub action list:
  //   first visit  : kill_all + (pickup_key if self-drop) + open_gate:<dirN>
  //   later visits : open_gate:<dirN> only (kill_all on an already-cleared
  //                  room can stall the wave-clear hook with empty waves)
  for (let si = 0; si < spokes.length; si++) {
    const { direction, path } = spokes[si];
    const isFirstHubVisit = si === 0;
    const isLastSpoke = si === spokes.length - 1;

    // Hub step.
    const hubActions: string[] = [];
    if (isFirstHubVisit) {
      hubActions.push('kill_all');
      const hasNullDialog = hub.dialogTriggers.some((d) => d.condition === null && d.actions === null);
      if (hasNullDialog) hubActions.push('dismiss_dialog');
      if (hub.keyDrop !== null && hub.keyDrop.targetCell === hub.pos) hubActions.push('pickup_key');
    }
    hubActions.push(`open_gate:${direction}`);
    pushStep(hub, hubActions, direction, path[0], isFirstHubVisit ? '' : ' (return)');

    // Spoke forward: path[0..length-2] are passthroughs, path[length-1] is payload.
    for (let pi = 0; pi < path.length; pi++) {
      const cell = byPos.get(path[pi])!;
      const isPayload = pi === path.length - 1;
      let exitDir = '';
      let target = '';
      if (!isPayload) {
        const nextPos = path[pi + 1];
        for (const [d, p] of Object.entries(cell.connections)) {
          if (p === nextPos) {
            exitDir = d;
            target = nextPos;
            break;
          }
        }
        pushStep(cell, ['kill_all'], exitDir, target, ' (passthrough)');
      } else {
        // Payload cell.
        const actions: string[] = ['kill_all'];
        const hasNullDialog = cell.dialogTriggers.some((d) => d.condition === null && d.actions === null);
        if (hasNullDialog) actions.push('dismiss_dialog');
        if (cell.switches.length > 0) actions.push('flip_switch');
        if (cell.keyDrop !== null) actions.push('pickup_key');
        actions.push('pickup_quest_item');
        const isTerminal = isLastSpoke && isLastSection;
        if (isTerminal) actions.push('wait_quest_complete');
        // Exit: if this is the final payload, no exit (we're done); otherwise
        // walk back toward the hub via the reverse of the way we came.
        if (!isLastSpoke) {
          // Find the connection on this payload cell that leads back along
          // the spoke (toward path[pi-1] if length>1, else back to hub).
          const prevPos = path.length >= 2 ? path[pi - 1] : hub.pos;
          for (const [d, p] of Object.entries(cell.connections)) {
            if (p === prevPos) {
              exitDir = d;
              target = prevPos;
              break;
            }
          }
        }
        pushStep(cell, actions, exitDir, target, '');
      }
    }

    // Spoke return path (only if not last spoke): from payload back to hub.
    if (!isLastSpoke) {
      // Walk path in reverse, excluding the payload (already emitted).
      for (let pi = path.length - 2; pi >= 0; pi--) {
        const cell = byPos.get(path[pi])!;
        const nextPos = pi === 0 ? hub.pos : path[pi - 1];
        let exitDir = '';
        for (const [d, p] of Object.entries(cell.connections)) {
          if (p === nextPos) {
            exitDir = d;
            break;
          }
        }
        pushStep(cell, ['kill_all'], exitDir, nextPos, ' (return)');
      }
    }
  }

  return steps;
}

// Build the flat step list for one section. Ported from
// autopilot.gd:_build_steps_from_plan (lines 369-531). Behaviour is
// intended to be bit-for-bit identical to the GDScript version so the
// regression harness sees no semantic change after this refactor.
function buildStepsForSection(
  cells: CellPlan[],
  section: QuestPlan['sections'][number],
  sectionIdx: number,
  totalSections: number,
): PlanStep[] {
  // Sort by pathOrder (scheduleCells already renumbered, but we re-sort to
  // tolerate any external mutation).
  const sortedCells = [...cells].sort((a, b) => a.pathOrder - b.pathOrder);

  // pos → cell map for BFS detour resolution + connection lookups.
  const byPos = new Map<string, CellPlan>();
  for (const c of sortedCells) byPos.set(c.pos, c);

  // Multi-gate hub fast-path: when the section contains a hub (cell with
  // `keyGate.directions.length > 1`), the natural pathOrder traversal can't
  // express the hub→spoke→hub→spoke→hub pattern the gameplay needs. Emit
  // a custom hub-and-spoke step list instead.
  const hub = sortedCells.find((c) => c.keyGate && c.keyGate.directions.length > 1);
  if (hub) {
    const startCell = sortedCells.find((c) => c.isStart) ?? sortedCells[0];
    const spokes = discoverSpokes(hub, byPos, section.endPos);
    if (spokes.length > 0) {
      return buildHubAndSpokeSteps(
        hub,
        spokes,
        startCell,
        byPos,
        section,
        sectionIdx,
        totalSections,
      );
    }
    // Fall through to the linear builder if spoke discovery returned
    // nothing — the warning surfaces in scheduleCells output.
  }

  // Insert BFS passthroughs whenever consecutive cells aren't directly
  // connected. A "passthrough" is an intermediate cell visited only as
  // transit — kill_all action only, walk to the next cell.
  const entries: PreStep[] = [];
  for (let ci = 0; ci < sortedCells.length; ci++) {
    const cell = sortedCells[ci];
    if (ci > 0) {
      const prevCell = sortedCells[ci - 1];
      const directlyConnected = Object.values(prevCell.connections)
        .some((next) => next === cell.pos);
      if (!directlyConnected) {
        const detour = bfsCellPath(prevCell.pos, cell.pos, byPos);
        for (let di = 1; di < detour.length - 1; di++) {
          const passthroughCell = byPos.get(detour[di]);
          if (passthroughCell) entries.push({ cell: passthroughCell, isPassthrough: true });
        }
      }
    }
    entries.push({ cell, isPassthrough: false });
  }

  const isLastSection = sectionIdx === totalSections - 1;
  const visitedKeys = new Map<string, number>();
  const steps: PlanStep[] = [];

  for (let ei = 0; ei < entries.length; ei++) {
    const { cell, isPassthrough } = entries[ei];
    const visitN = (visitedKeys.get(cell.pos) ?? 0) + 1;
    visitedKeys.set(cell.pos, visitN);
    const isLastEntryInSection = ei === entries.length - 1;
    const isTerminal = isLastSection && isLastEntryInSection;

    // ── Exit direction derivation ────────────────────────────────────
    let exitDir = '';
    let targetPos = '';
    const warpEdge = cell.warpEdge ?? '';
    const sectionExitDir = section.exitDirection ?? '';
    const isStartCell = cell.isStart;
    // Use warp_edge as the exit only when this cell is meant to exit
    // INTO another section (single-cell transition sections like paru
    // pact's s05e_ia1 have warp_edge="south" on the entry side and
    // exit north). For section-start cells without an explicit
    // exitDirection, fall through to the connections-based derivation
    // so we walk toward the next planned cell.
    let shouldUseWarpExit = false;
    if (warpEdge !== '' && warpEdge !== null) {
      shouldUseWarpExit = sectionExitDir !== '' || !isStartCell;
    }
    if (shouldUseWarpExit) {
      exitDir = sectionExitDir !== '' ? sectionExitDir : warpEdge;
    } else if (!isTerminal) {
      const nextEntry = entries[ei + 1];
      const nextPos = nextEntry.cell.pos;
      for (const [dir, p] of Object.entries(cell.connections)) {
        if (p === nextPos) {
          exitDir = dir;
          targetPos = nextPos;
          break;
        }
      }
    }

    // ── Action list ──────────────────────────────────────────────────
    let actions: string[];
    if (isPassthrough) {
      actions = ['kill_all'];
    } else {
      actions = ['kill_all'];
      const hasNullDialog = cell.dialogTriggers.some(
        (d) => d.condition === null && d.actions === null,
      );
      if (hasNullDialog) actions.push('dismiss_dialog');
      // Order: switch → key → gate → pickup. flip_switch first because
      // switches unblock fences that may sit on the path to keys, gates,
      // or items. pickup_key before open_gate because the key dropped in
      // this cell typically unlocks this cell's own gate (paru pact's
      // B 2,1 drops its own gate key). Item pickup last since
      // fences/gates may sit between the player and the item.
      if (cell.switches.length > 0) actions.push('flip_switch');
      if (cell.keyDrop !== null) actions.push('pickup_key');
      if (cell.keyGate !== null) actions.push('open_gate');
      actions.push('pickup_quest_item');
      if (isTerminal) actions.push('wait_quest_complete');
    }

    // ── Label ────────────────────────────────────────────────────────
    const area = (section.area || '?').toUpperCase();
    const suffix = isPassthrough ? ' (passthrough)' : (visitN > 1 ? ' (return)' : '');
    const label = `${area} ${cell.pos}${suffix}`;

    // ── Exit portal ID resolution ────────────────────────────────────
    let exitPortalId = '';
    if (exitDir !== '' && cell.portals[exitDir]) {
      exitPortalId = cell.portals[exitDir];
    }

    steps.push({
      label,
      do: actions,
      exit: exitDir,
      exit_portal_id: exitPortalId,
      target: targetPos,
      _section_idx: sectionIdx,
      _pos: cell.pos,
      stageId: cell.stageId,
      rotation: cell.rotation,
    });
  }

  return steps;
}

function planQuest(quest: Quest): QuestPlan {
  const sectionMetas = quest.sections.map((s) => ({
    type: s.type,
    area: s.area,
    startPos: s.start_pos,
    endPos: s.end_pos,
    entryDirection: s.entry_direction ?? null,
    exitDirection: s.exit_direction ?? null,
  }));
  const sectionCells = quest.sections.map((s, i) =>
    scheduleCells(s.cells.map(planCell), `${quest.id}/${s.area}`),
  );
  const totalSections = quest.sections.length;
  return {
    questId: quest.id,
    questName: quest.name,
    areaId: quest.area_id,
    sections: quest.sections.map((s, i) => ({
      ...sectionMetas[i],
      cells: sectionCells[i],
      steps: buildStepsForSection(
        sectionCells[i],
        { ...sectionMetas[i], cells: [], steps: [] },
        i,
        totalSections,
      ),
    })),
  };
}

// Reorder cells so action dependencies are honored before the autopilot
// executes the cell's listed actions:
//
//   • key→gate: if cell G has `keyGate` and cell K has `keyDrop.targetCell ==
//     G.pos`, K must appear before G. Quest authors lay cells out in spatial
//     `path_order` (left-right, top-bottom on the grid), which is friendly to
//     the level editor but doesn't reflect logical action order — we'd ask the
//     autopilot to `open_gate` at G before any cell has dropped the key.
//
// The autopilot's _build_steps_from_plan already handles inserting BFS
// passthroughs between non-adjacent cells (visit transit cells with kill_all
// only). So when we move K (the key cell) before G (the gate cell), the
// autopilot naturally re-routes through G as a passthrough on its way to K,
// then visits G "for real" later for the open_gate + pickup actions.
//
// Out of scope for v1:
//   • Switch→fence dependencies (link_id matching) — more cells, more graph
//     edges, can wait until we hit a quest where it actually matters.
//   • Cross-section dependencies — every quest we ship today keeps keys and
//     gates in the same section.
//   • Multi-key gates (`required_keys > 1`) — currently a stretch since each
//     key cell would need to be visited.
function scheduleCells(cells: CellPlan[], label: string): CellPlan[] {
  // Map: gate-cell pos → key-drop cell pos (cell that drops the key for that gate)
  //
  // Some quests have multiple cells dropping keys for the same gate (e.g.
  // finding_ogi's hub at B 3,2 collects 4 different drops: a self-drop in
  // 3,2 itself plus drops in three spoke cells). The runtime treats any key
  // as opening any gate in the room, so we only need ONE key picked up
  // before the gate to satisfy the constraint. Prefer the FIRST cell that
  // drops the key (don't overwrite) — that picks up self-drops on the gate
  // cell itself, which trivially avoids the circular dependency of "key
  // sits past the gate it would unlock."
  const keyDropOf = new Map<string, string>();
  for (const c of cells) {
    if (c.keyDrop?.targetCell && !keyDropOf.has(c.keyDrop.targetCell)) {
      keyDropOf.set(c.keyDrop.targetCell, c.pos);
    }
  }

  // Data-quality check: a cell flagged as a key gate must carry the direction
  // of the locked portal. Downstream tooling (autopilot exit derivation, the
  // solver's playback, spec viewers) relies on `keyGate.direction` to know
  // which portal is locked. An empty string here is silently dangerous —
  // surface it loudly so the source quest data gets fixed instead of
  // producing wrong routes at runtime.
  for (const c of cells) {
    if (c.keyGate && (!c.keyGate.direction || c.keyGate.direction === '')) {
      console.warn(
        `  WARN [${label}]: cell ${c.pos} (${c.stageId}) is a key gate but key_gate_direction is empty — autopilot routing may pick the wrong portal`,
      );
    }
  }

  const result = cells.map((c) => ({ ...c }));
  const reorders: string[] = [];

  let i = 0;
  while (i < result.length) {
    const cell = result[i];
    if (cell.keyGate) {
      const keyPos = keyDropOf.get(cell.pos);
      // Self-drops (key spawns in the same cell as the gate) need no reorder.
      if (keyPos && keyPos !== cell.pos) {
        const keyIdx = result.findIndex((c) => c.pos === keyPos);
        if (keyIdx > i) {
          const [keyCell] = result.splice(keyIdx, 1);
          result.splice(i, 0, keyCell);
          reorders.push(`${keyPos} (key) → before ${cell.pos} (gate)`);
          // Gate cell is now at i+1. Skip past both so we don't re-check
          // the moved key cell as a "gate" on the next iteration.
          i += 2;
          continue;
        }
      }
    }
    i++;
  }

  // Renumber pathOrder so it reflects the post-schedule order. Downstream
  // consumers (the autopilot, debugging tools) sort by pathOrder, not array
  // index — keep them aligned.
  for (let k = 0; k < result.length; k++) {
    result[k].pathOrder = k;
  }

  if (reorders.length > 0) {
    console.log(`  scheduler [${label}]: ${reorders.length} reorder(s)`);
    for (const r of reorders) console.log(`    ${r}`);
  }

  return result;
}

function runOne(questPath: string) {
  const quest: Quest = JSON.parse(readFileSync(questPath, 'utf8'));
  const plan = planQuest(quest);
  const outDir = join(REPO, 'data', 'quest_plans');
  mkdirSync(outDir, { recursive: true });
  const outPath = join(outDir, `${quest.id}.json`);
  writeFileSync(outPath, JSON.stringify(plan, null, 2) + '\n');

  const cells = plan.sections.flatMap((s) => s.cells);
  const npcs = cells.flatMap((c) => c.npcs);
  console.log(`✓ ${quest.id} → ${outPath.replace(REPO + '/', '')}`);
  console.log(
    `  ${plan.sections.length} section(s), ${cells.length} cell(s); ` +
      `${cells.filter((c) => c.keyGate).length} key-gate(s), ` +
      `${cells.filter((c) => c.keyDrop).length} key-drop(s), ` +
      `${cells.filter((c) => c.switches.length || c.fences.length).length} switch puzzle(s), ` +
      `${npcs.length} NPC(s)`
  );
}

function main() {
  const args = process.argv.slice(2);
  if (args.length === 0) {
    console.error('usage: bun scripts/tools/quest_plan.ts <quest-id-or-json-path> | --all');
    process.exit(1);
  }
  const questsDir = join(REPO, 'data', 'quests');
  if (args[0] === '--all') {
    for (const f of readdirSync(questsDir)) {
      if (!f.endsWith('.json') || f === 'manifest.json') continue;
      runOneSafe(join(questsDir, f));
    }
    return;
  }
  for (const arg of args) {
    const p = arg.endsWith('.json')
      ? (arg.startsWith('/') ? arg : resolve(arg))
      : join(questsDir, `${arg}.json`);
    runOneSafe(p);
  }
}

function runOneSafe(p: string) {
  try {
    runOne(p);
  } catch (e) {
    console.error(`✗ ${basename(p)}: ${(e as Error).message}`);
  }
}

main();
