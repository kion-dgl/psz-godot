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
  warpEdge: string | null;
  keyGate: { direction: string; requiredKeys: number } | null;
  keyDrop: { targetCell: string; position: Vec3 | null } | null;
  switches: { position: Vec3; linkId: string | null }[];
  fences: { position: Vec3; linkId: string | null }[];
  npcs: { npcId: string; position: Vec3; animation: string | null }[];
  storyProps: { propPath: string; position: Vec3 }[];
  dialogTriggers: { position: Vec3; condition: string | null; actions: string[] | null }[];
  enemyCount: number;
  boxCount: number;
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

  return {
    pos: cell.pos,
    stageId: cell.stage_id,
    rotation: cell.rotation,
    pathOrder: cell.path_order,
    isStart: !!cell.is_start,
    isEnd: !!cell.is_end,
    isBranch: !!cell.is_branch,
    connections: cell.connections,
    warpEdge: cell.warp_edge || null,
    keyGate: cell.is_key_gate
      ? { direction: cell.key_gate_direction ?? '', requiredKeys: cell.required_keys ?? 1 }
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

function planQuest(quest: Quest): QuestPlan {
  return {
    questId: quest.id,
    questName: quest.name,
    areaId: quest.area_id,
    sections: quest.sections.map((s) => ({
      type: s.type,
      area: s.area,
      startPos: s.start_pos,
      endPos: s.end_pos,
      entryDirection: s.entry_direction ?? null,
      exitDirection: s.exit_direction ?? null,
      cells: scheduleCells(s.cells.map(planCell), `${quest.id}/${s.area}`),
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
  const keyDropOf = new Map<string, string>();
  for (const c of cells) {
    if (c.keyDrop?.targetCell) {
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
