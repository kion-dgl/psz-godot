// Quest traversal sequencer — read a quest plan (data/quest_plans/<id>.json)
// and produce, per stage, the list of important XZ positions plus the A*
// paths connecting them.
//
// Important positions per stage:
//   • One spawn point per portal direction (3m inward from the portal gate).
//   • One exit point per portal direction (4m outward from the gate — the
//     scene-change trigger lives at +3m, the load waypoint at +4m, matching
//     the convention in the existing hand-authored graphs).
//   • Key drop position (if cell has one).
//   • Switch positions (one per switch in the cell).
//
// We don't try to derive a strict visit order — that's the autopilot's job
// (its action list per cell already handles key→switch→gate sequencing). The
// solver just needs to ensure that *any* pair of useful points is reachable
// via the emitted graph.

import { readFileSync } from "node:fs";

export interface QuestCell {
	pos: string;
	stageId: string;
	rotation: number;
	pathOrder: number;
	isStart: boolean;
	isEnd: boolean;
	connections: Record<string, string>;
	warpEdge: string | null;
	keyGate: { direction: string; requiredKeys: number } | null;
	keyDrop: { targetCell: string; position: [number, number, number] } | null;
	switches: { position: [number, number, number]; linkId?: string }[];
	fences: { position: [number, number, number]; linkId?: string }[];
	dialogTriggers: { position: [number, number, number]; condition: string | null; actions: string[] | null }[];
}

export interface QuestSection {
	type: string;
	area: string;
	cells: QuestCell[];
}

export interface QuestPlan {
	questId: string;
	questName: string;
	areaId: string;
	sections: QuestSection[];
}

export function loadQuestPlan(path: string): QuestPlan {
	return JSON.parse(readFileSync(path, "utf8")) as QuestPlan;
}

/** All stage IDs referenced by the quest, deduped. */
export function stagesUsed(plan: QuestPlan): string[] {
	const set = new Set<string>();
	for (const s of plan.sections) {
		for (const c of s.cells) set.add(c.stageId);
	}
	return [...set].sort();
}

/** Return all (cell, area) pairs that use the given stageId. A stage can be
 *  reused across multiple cells in the same quest (e.g. s01a_tb3 appears as
 *  both the gate-and-detour and the return path in search-and-rescue). */
export function cellsForStage(plan: QuestPlan, stageId: string): { cell: QuestCell; area: string }[] {
	const out: { cell: QuestCell; area: string }[] = [];
	for (const s of plan.sections) {
		for (const c of s.cells) {
			if (c.stageId === stageId) out.push({ cell: c, area: s.area });
		}
	}
	return out;
}

const OUTWARD: Record<string, [number, number]> = {
	north: [0, -1],
	south: [0, 1],
	east: [1, 0],
	west: [-1, 0],
};

// Engine convention (valley_field_controller.gd): portal.position is the
// GATE (cell edge); the player-spawn pose lives 3m OUTWARD from the gate;
// the scene-change trigger is at gate + 7m OUTWARD. The autopilot drives
// the player from spawn → … → load (where load matches the trigger), so the
// load waypoint MUST sit on the trigger or past it, not short of it.
const SPAWN_INSET = 3.0;
const EXIT_OUTSET = 7.0;

export interface StagePoint {
	id: string;
	kind: "spawn" | "exit" | "key_drop" | "switch" | "telepipe";
	x: number;
	z: number;
	label: string;
}

/**
 * Enumerate the points the autopilot might want to walk to in a given stage,
 * derived from the stage's portal config plus the union of all cells that
 * reference the stage in this quest. Deduped by (x,z) within 0.5m.
 */
export function stagePoints(
	stageId: string,
	stageConfig: { portals: { direction: string; position: [number, number, number]; label?: string }[] },
	cells: QuestCell[],
): StagePoint[] {
	const out: StagePoint[] = [];

	// Portals → spawn + exit waypoints. The portal `position` IS the gate
	// (trigger that fires the scene change is at +3m outward, spawn pos at
	// -3m inward; the *exit* waypoint where the autopilot walks to leave is
	// at +4m outward).
	for (let i = 0; i < stageConfig.portals.length; i++) {
		const p = stageConfig.portals[i];
		const dir = p.direction;
		const o = OUTWARD[dir];
		if (!o) continue;
		// Both spawn and exit sit OUTSIDE the gate (the gate is on the cell's
		// edge, the player walks across it from outside-in or inside-out).
		// Spawn is just outside; exit (the scene-change trigger) is further
		// outside. Both increase along the outward direction.
		const spawnX = p.position[0] + o[0] * SPAWN_INSET;
		const spawnZ = p.position[2] + o[1] * SPAWN_INSET;
		const exitX = p.position[0] + o[0] * EXIT_OUTSET;
		const exitZ = p.position[2] + o[1] * EXIT_OUTSET;
		out.push({ id: `wp_spawn_${i}_${stageId}`, kind: "spawn", x: spawnX, z: spawnZ, label: `spawn ${dir}` });
		out.push({ id: `wp_load_${i}_${stageId}`, kind: "exit", x: exitX, z: exitZ, label: `load ${dir}` });
	}

	// Objective points across all cells that use this stage.
	const seen = new Map<string, true>();
	const key = (x: number, z: number) => `${Math.round(x * 2)}_${Math.round(z * 2)}`;
	let idx = 0;
	for (const cell of cells) {
		if (cell.keyDrop) {
			const [x, , z] = cell.keyDrop.position;
			const k = `key_${key(x, z)}`;
			if (!seen.has(k)) {
				seen.set(k, true);
				out.push({ id: `wp_key_${idx++}_${stageId}`, kind: "key_drop", x, z, label: `key ${cell.pos}` });
			}
		}
		for (const sw of cell.switches) {
			const [x, , z] = sw.position;
			const k = `switch_${key(x, z)}`;
			if (!seen.has(k)) {
				seen.set(k, true);
				out.push({ id: `wp_switch_${idx++}_${stageId}`, kind: "switch", x, z, label: `switch ${cell.pos}` });
			}
		}
		// Telepipe spawn = the position of any dialog_trigger whose actions list
		// includes "telepipe". Used by the autopilot's _drive_walk_to_telepipe.
		for (const trig of cell.dialogTriggers) {
			if ((trig.actions ?? []).includes("telepipe")) {
				const [x, , z] = trig.position;
				const k = `telepipe_${key(x, z)}`;
				if (!seen.has(k)) {
					seen.set(k, true);
					out.push({ id: `wp_telepipe_${idx++}_${stageId}`, kind: "telepipe", x, z, label: `telepipe ${cell.pos}` });
				}
			}
		}
	}

	return out;
}
