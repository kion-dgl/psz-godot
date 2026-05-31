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
	kind: "spawn" | "exit" | "key_drop" | "switch" | "telepipe" | "via";
	x: number;
	z: number;
	label: string;
}

/**
 * Infer a stage's room shape from its ID. Stage IDs use a convention like
 * `s05a_tb3`, where the 4th character is the area variant (a/b) and the 5th-6th
 * characters encode the room type:
 *   • sa, ga         = dead-end (1 portal)
 *   • na, nb, nc     = narrow (corridor / 2 portals straight)
 *   • ia, ib, ic     = "I" shape (straight corridor)
 *   • la, lb, lc     = L-bend
 *   • ta, tb, tc, td = T-junction (3 portals)
 *   • xa, xb         = X-junction (4 portals)
 * The trailing digit is a variant number (1, 2, 3) — different stages of
 * the same topology with different decoration. The shape hint drives the
 * solver: T/X-stages get a forced "via" waypoint at the portal centroid so
 * paths route through the junction instead of cutting diagonals across
 * floor mesh joins.
 */
export type StageShape = "dead_end" | "straight" | "l_bend" | "t_junction" | "x_junction" | "unknown";

export function inferStageShape(stageId: string): StageShape {
	// Strip the prefix "sNNX_" (e.g., "s05a_") to get the room type.
	const m = stageId.match(/^s\d+[a-z]_([a-z]+)\d+$/);
	if (!m) return "unknown";
	const type = m[1];
	switch (type[0]) {
		case "s": case "g": return "dead_end";
		case "n": case "i": return "straight";
		case "l": return "l_bend";
		case "t": return "t_junction";
		case "x": return "x_junction";
		default: return "unknown";
	}
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
	const gateXs: number[] = [];
	const gateZs: number[] = [];
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
		gateXs.push(p.position[0]);
		gateZs.push(p.position[2]);
	}

	// Topology hint: T- and X-junctions have a junction center where the
	// corridors meet; routing every spawn→spawn path THROUGH this point
	// avoids the diagonal "cut across the room floor" that often lands on
	// floor-mesh joins or gaps. The portal-position centroid is a strong
	// proxy for the geometric junction in these layouts. (For L-bends the
	// centroid is the wrong point — it's on the diagonal between the two
	// portals, not at the bend corner — so we skip them here.)
	const shape = inferStageShape(stageId);
	if ((shape === "t_junction" || shape === "x_junction") && gateXs.length >= 3) {
		const cx = gateXs.reduce((a, b) => a + b, 0) / gateXs.length;
		const cz = gateZs.reduce((a, b) => a + b, 0) / gateZs.length;
		out.push({ id: `wp_via_${stageId}`, kind: "via", x: cx, z: cz, label: `junction center (${shape})` });
	} else if (shape === "l_bend" && gateXs.length === 2) {
		// L-bend with two portals: the corner is one of (x1, z2) or (x2, z1)
		// in stage-local coords. We emit BOTH candidates; the emit step
		// validates each against the navmesh (isPointOnNavMesh) and the path
		// finder picks the one that yields a valid route.
		const ax = gateXs[0], az = gateZs[0], bx = gateXs[1], bz = gateZs[1];
		out.push({ id: `wp_via_a_${stageId}`, kind: "via", x: ax, z: bz, label: `L-corner (x1,z2)` });
		out.push({ id: `wp_via_b_${stageId}`, kind: "via", x: bx, z: az, label: `L-corner (x2,z1)` });
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

/**
 * Collect deduped fence positions across all cells using this stage. Used by
 * the solver to mark fence cells as obstacles when routing the pre-switch leg
 * (spawn → switch): the autopilot must reach the switch *before* the fence
 * opens, so any path that cuts through the fence position is invalid.
 *
 * Post-switch legs (switch → exit) use a grid WITHOUT these obstacles so the
 * autopilot can walk through the now-open fence.
 */
export function stageFences(cells: QuestCell[]): { x: number; z: number; linkId: string }[] {
	const seen = new Map<string, true>();
	const out: { x: number; z: number; linkId: string }[] = [];
	for (const c of cells) {
		for (const f of c.fences ?? []) {
			const [x, , z] = f.position;
			const k = `${Math.round(x * 2)}_${Math.round(z * 2)}`;
			if (seen.has(k)) continue;
			seen.set(k, true);
			out.push({ x, z, linkId: f.linkId ?? "" });
		}
	}
	return out;
}
