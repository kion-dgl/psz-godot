#!/usr/bin/env bun
// generate_waypoints — author per-stage waypoint graphs for every stage used
// by a quest, derived from the stage's portals + the quest plan's objects.
//
// Authored graph per stage:
//   • For each portal direction: one `spawn` waypoint 3m INWARD from the
//     gate, one `exit` waypoint 7m OUTWARD (matches the convention the
//     user authored by hand for s01a_lb1, lb3, tb3, na1, b_ic1).
//   • A `center` waypoint at (0, 0, 0).
//   • One waypoint per quest object (switches, key drops) at the object's
//     position — these are the targets the autopilot's flip_switch /
//     pickup_key actions need to reach.
//   • Edges: spawn↔exit (straight through gate), center↔each spawn,
//     center↔each quest-object waypoint. The autopilot's BFS handles the
//     rest.
//
// Usage:
//   bun scripts/tools/generate_waypoints.ts <quest-id>
//     [--skip-stages s01a_lb1,s01a_lb3,...]    don't overwrite these
//     [--corridor]    treat every stage as a straight/L-shaped corridor:
//                     emit ONLY spawn/exit pairs and a single inner-corner
//                     waypoint per pair of portals (placed at the
//                     right-angle elbow). No 10m corner clique. For stages
//                     with no obstacles + no in-cell objects (Eternal
//                     Tower-style climbs), this keeps the autopilot on
//                     the actual hallway rather than zigzagging through
//                     corner waypoints that sit outside the floor.
//
// Writes back to data/stage_configs/unified-stage-configs.json.

import { readFileSync, writeFileSync } from "node:fs";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO = resolve(__dirname, "..", "..");

const OUTWARD: Record<string, [number, number, number]> = {
	north: [0, 0, -1],
	south: [0, 0, 1],
	east: [1, 0, 0],
	west: [-1, 0, 0],
};

const SPAWN_INSET = 3.0;
const EXIT_OUTSET = 7.0;

function main() {
	const questId = process.argv[2];
	if (!questId) {
		console.error("usage: bun scripts/tools/generate_waypoints.ts <quest-id> [--skip-stages a,b,c]");
		process.exit(1);
	}
	const skipArg = process.argv.find((a) => a.startsWith("--skip-stages="));
	const skip = new Set((skipArg?.split("=")[1] ?? "").split(",").filter(Boolean));
	const corridor = process.argv.includes("--corridor");

	const planPath = join(REPO, "data", "quest_plans", `${questId}.json`);
	const cfgPath = join(REPO, "data", "stage_configs", "unified-stage-configs.json");
	const plan = JSON.parse(readFileSync(planPath, "utf8"));
	const configs = JSON.parse(readFileSync(cfgPath, "utf8"));

	// Group cells by stage so each stage's waypoints can reference every quest
	// object that any cell in that stage carries.
	const cellsByStage: Record<string, any[]> = {};
	for (const sect of plan.sections ?? []) {
		for (const cell of sect.cells ?? []) {
			const sid = cell.stageId;
			if (!sid) continue;
			(cellsByStage[sid] ??= []).push(cell);
		}
	}

	const usedStages = Object.keys(cellsByStage).sort();
	let updated = 0;
	for (const sid of usedStages) {
		if (skip.has(sid)) {
			console.log(`  skip ${sid} (in --skip-stages)`);
			continue;
		}
		const stage = configs[sid];
		if (!stage) {
			console.log(`  WARN: ${sid} not in stage configs`);
			continue;
		}
		const existing = stage.waypoints?.length ?? 0;
		if (existing > 0) {
			console.log(`  skip ${sid} (already authored: ${existing} waypoints)`);
			continue;
		}
		const { waypoints, edges } = corridor
			? buildCorridorGraph(sid, stage)
			: buildGraph(sid, stage, cellsByStage[sid] ?? []);
		stage.waypoints = waypoints;
		stage.waypointEdges = edges;
		updated += 1;
		console.log(`  wrote ${sid}: ${waypoints.length} waypoints, ${edges.length} edges`);
	}

	writeFileSync(cfgPath, JSON.stringify(configs, null, 2) + "\n");
	console.log(`\nUpdated ${updated} stage(s).`);
}

// Corridor mode: one spawn + one exit per portal direction, no 10m corner
// clique. If the stage has exactly two portals that share an axis (both N/S
// or both E/W) we connect their spawns directly — that's a straight
// corridor. If two portals sit on perpendicular axes we place a single
// "elbow" waypoint at the right-angle inside corner so the autopilot turns
// without cutting through wall geometry. Three+ portals get a full-mesh
// among spawns (BFS handles the rest), suitable for the rare T-junction
// floor — refine by hand if the auto layout walks into a wall.
function buildCorridorGraph(sid: string, stage: any) {
	const waypoints: any[] = [];
	const edges: [string, string][] = [];
	const portals = stage.portals ?? [];

	type Spawn = { id: string; dir: string; pos: [number, number, number] };
	const spawns: Spawn[] = [];
	for (let i = 0; i < portals.length; i++) {
		const p = portals[i];
		const dir = p.direction;
		const pos = p.position;
		if (!OUTWARD[dir] || !Array.isArray(pos) || pos.length < 3) continue;
		const [ox, , oz] = OUTWARD[dir];
		const spawn: [number, number, number] = [
			pos[0] + ox * SPAWN_INSET,
			0,
			pos[2] + oz * SPAWN_INSET,
		];
		const exitPos: [number, number, number] = [
			pos[0] + ox * EXIT_OUTSET,
			0,
			pos[2] + oz * EXIT_OUTSET,
		];
		const spawnId = `wp_spawn_${i}_auto_${sid}`;
		const exitId = `wp_load_${i}_auto_${sid}`;
		waypoints.push({ id: spawnId, position: spawn, kind: "spawn", label: `spawn ${dir}` });
		waypoints.push({ id: exitId, position: exitPos, kind: "exit", label: `load ${dir}` });
		edges.push([exitId, spawnId]);
		spawns.push({ id: spawnId, dir, pos: spawn });
	}

	if (spawns.length === 2) {
		const [a, b] = spawns;
		const sameAxis =
			((a.dir === "north" || a.dir === "south") && (b.dir === "north" || b.dir === "south")) ||
			((a.dir === "east" || a.dir === "west") && (b.dir === "east" || b.dir === "west"));
		if (sameAxis) {
			edges.push([a.id, b.id]);
		} else {
			// L-shape. The inside elbow sits at the right-angle corner: take x
			// from the N/S-portal side and z from the E/W-portal side (or vice
			// versa). That puts the waypoint at the bend, on the floor.
			const ns = a.dir === "north" || a.dir === "south" ? a : b;
			const ew = a.dir === "east" || a.dir === "west" ? a : b;
			const elbow: [number, number, number] = [ns.pos[0], 0, ew.pos[2]];
			const elbowId = `wp_elbow_${sid}`;
			waypoints.push({ id: elbowId, position: elbow, kind: "point", label: "elbow" });
			edges.push([a.id, elbowId]);
			edges.push([b.id, elbowId]);
		}
	} else if (spawns.length > 2) {
		// T-junction or branching room — full mesh among spawns. Author may
		// want to refine by hand if a straight spawn↔spawn line crosses an
		// obstacle.
		for (let i = 0; i < spawns.length; i++) {
			for (let j = i + 1; j < spawns.length; j++) {
				edges.push([spawns[i].id, spawns[j].id]);
			}
		}
	}
	return { waypoints, edges };
}

function buildGraph(sid: string, stage: any, cells: any[]) {
	const waypoints: any[] = [];
	const edges: [string, string][] = [];
	const portals = stage.portals ?? [];

	const spawnIds: string[] = [];
	for (let i = 0; i < portals.length; i++) {
		const p = portals[i];
		const dir = p.direction;
		const pos = p.position;
		if (!OUTWARD[dir] || !Array.isArray(pos) || pos.length < 3) continue;
		const [ox, , oz] = OUTWARD[dir];
		const spawn = [pos[0] + ox * SPAWN_INSET, 0, pos[2] + oz * SPAWN_INSET];
		const exit = [pos[0] + ox * EXIT_OUTSET, 0, pos[2] + oz * EXIT_OUTSET];
		const spawnId = `wp_spawn_${i}_auto_${sid}`;
		const exitId = `wp_load_${i}_auto_${sid}`;
		waypoints.push({ id: spawnId, position: spawn, kind: "spawn", label: `spawn ${dir}` });
		waypoints.push({ id: exitId, position: exit, kind: "exit", label: `load ${dir}` });
		edges.push([exitId, spawnId]);
		spawnIds.push(spawnId);
	}

	// Four corner waypoints in the cell quadrants, ~10m from center. Stages
	// with obstacles near (0, 0) (e.g. s01a_ic1 has a cylinder there) make a
	// single center waypoint unreachable, so we use four offset corners and
	// fully interconnect them. Spawns attach to all four corners; quest
	// objects to the nearest corner.
	const cornerOffset = 10;
	const corners: { id: string; pos: [number, number, number] }[] = [
		{ id: `wp_corner_ne_${sid}`, pos: [cornerOffset, 0, -cornerOffset] },
		{ id: `wp_corner_se_${sid}`, pos: [cornerOffset, 0, cornerOffset] },
		{ id: `wp_corner_sw_${sid}`, pos: [-cornerOffset, 0, cornerOffset] },
		{ id: `wp_corner_nw_${sid}`, pos: [-cornerOffset, 0, -cornerOffset] },
	];
	for (const c of corners) {
		waypoints.push({ id: c.id, position: c.pos, kind: "point", label: c.id.split("_").slice(2, 3)[0] });
	}
	// Fully connect the corners (4-clique) so BFS can route around obstacles.
	for (let i = 0; i < corners.length; i++) {
		for (let j = i + 1; j < corners.length; j++) {
			edges.push([corners[i].id, corners[j].id]);
		}
	}
	// Each spawn connects to its two nearest corners.
	for (const sId of spawnIds) {
		const spawnWp = waypoints.find((w) => w.id === sId);
		if (!spawnWp) continue;
		const sorted = [...corners].sort(
			(a, b) => xzDist(a.pos, spawnWp.position) - xzDist(b.pos, spawnWp.position),
		);
		edges.push([sId, sorted[0].id]);
		edges.push([sId, sorted[1].id]);
	}

	// Quest objects: switches and key drops are positions the autopilot
	// drives the player onto. Each attaches to its nearest corner. Fences
	// are obstacles; skip.
	const objectsSeen = new Set<string>();
	for (const cell of cells) {
		const collect = (
			pos: number[] | undefined,
			kind: string,
			label: string,
		) => {
			if (!pos || pos.length < 3) return;
			const key = `${kind}_${posKey(pos)}`;
			if (objectsSeen.has(key)) return;
			objectsSeen.add(key);
			const wpId = `wp_${kind}_${cellSafe(cell.pos)}_auto`;
			waypoints.push({ id: wpId, position: pos, kind: "point", label });
			// Attach to the nearest corner.
			const sorted = [...corners].sort(
				(a, b) => xzDist(a.pos, pos as [number, number, number]) - xzDist(b.pos, pos as [number, number, number]),
			);
			edges.push([sorted[0].id, wpId]);
		};
		for (const sw of cell.switches ?? []) collect(sw.position, "switch", `switch ${cell.pos}`);
		collect(cell.keyDrop?.position, "key", `key drop ${cell.pos}`);
	}

	return { waypoints, edges };
}

function xzDist(a: number[], b: number[]): number {
	const dx = a[0] - b[0];
	const dz = a[2] - b[2];
	return Math.sqrt(dx * dx + dz * dz);
}

function posKey(p: number[]): string {
	return p.map((v) => v.toFixed(2)).join(",");
}
function cellSafe(pos: string): string {
	return (pos ?? "").replace(",", "_");
}

main();
