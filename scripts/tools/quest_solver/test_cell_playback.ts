#!/usr/bin/env bun
// test_cell_playback — Bun-side equivalent of the editor's "Play cell"
// sim. Loads the live unified-stage-configs.json + the quest plan, builds
// the per-cell spawn → switch → exit sequence, BFSes each leg over the
// waypoint graph, then floor-walks each leg at sampleStep intervals
// against the actual floor.glb triangles. Reports per-leg pass/fail.
//
// This is the iteration loop the editor browser sim is, but in plain TS
// — no React, no three.js, no HMR — so verifying each cell is millisecond
// fast.
//
// Usage:
//   bun test_cell_playback.ts <quest_id>                 # walk every cell
//   bun test_cell_playback.ts <quest_id> --cell <pos>    # one cell only
//   bun test_cell_playback.ts <quest_id> --stage <id>    # all cells using a stage

import { readFileSync } from "node:fs";
import { join, resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { loadGlb3D, loadStage3D, type Tri3D } from "./lib/floor.ts";
import { loadQuestPlan } from "./lib/quest_walk.ts";
import { pointInTriangle, type Tri2D } from "./lib/floor.ts";

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO = resolve(__dirname, "..", "..", "..");
const STAGE_CFG_PATH = join(REPO, "data", "stage_configs", "unified-stage-configs.json");
const ASSETS_STAGES = join(REPO, "assets", "stages");
const QUEST_PLANS = join(REPO, "data", "quest_plans");

const AREA_FOLDER: Record<string, string> = {
	gurhacia: "valley", ozette: "wetlands", rioh: "snowfield", makara: "makara",
	paru: "paru", arca: "arca", dark: "shrine", tower: "tower",
};
function stageSubfolder(stageId: string, areaId: string): string {
	const folder = AREA_FOLDER[areaId] ?? areaId;
	const variant = stageId.length >= 4 ? stageId[3] : "";
	return variant ? `${folder}_${variant}` : folder;
}

const DIRECTION_ORDER = ["north", "east", "south", "west"] as const;
type Direction = (typeof DIRECTION_ORDER)[number];
function rotateDirection(dir: Direction, rotation: number): Direction {
	if (rotation === 0) return dir;
	const idx = DIRECTION_ORDER.indexOf(dir);
	if (idx < 0) return dir;
	const steps = ((rotation / 90) % 4 + 4) % 4;
	return DIRECTION_ORDER[(idx + steps) % 4];
}

function parseArgs() {
	const args = process.argv.slice(2);
	if (args.length === 0 || args[0].startsWith("--")) {
		console.error("usage: bun test_cell_playback.ts <quest_id> [--cell <pos>] [--stage <id>] [--sample-step <m>] [--floor-only]");
		process.exit(1);
	}
	const questId = args[0];
	let cellFilter: string | null = null;
	let stageFilter: string | null = null;
	let sampleStep = 0.25;
	// Default: same fused floor+m mesh the solver uses for routing. The
	// autopilot in-game collides with both meshes, so the fused set is the
	// honest floor. --floor-only restricts to -floor.glb only when you want
	// to find which routes depend on m-mesh collision.
	let floorOnly = false;
	for (let i = 1; i < args.length; i++) {
		if (args[i] === "--cell") cellFilter = args[++i];
		else if (args[i] === "--stage") stageFilter = args[++i];
		else if (args[i] === "--sample-step") sampleStep = parseFloat(args[++i]);
		else if (args[i] === "--floor-only") floorOnly = true;
		else { console.error(`unknown arg: ${args[i]}`); process.exit(1); }
	}
	return { questId, cellFilter, stageFilter, sampleStep, floorOnly };
}

interface Waypoint {
	id: string;
	position: [number, number, number];
	kind?: string;
	label?: string;
}

function bfsPath(adj: Record<string, string[]>, from: string, to: string): string[] | null {
	if (from === to) return [from];
	const parent: Record<string, string | null> = { [from]: null };
	const q = [from];
	while (q.length) {
		const cur = q.shift()!;
		if (cur === to) break;
		for (const nb of adj[cur] ?? []) {
			if (nb in parent) continue;
			parent[nb] = cur;
			q.push(nb);
		}
	}
	if (!(to in parent)) return null;
	const out: string[] = [];
	let n: string | null = to;
	while (n) { out.push(n); n = parent[n]; }
	return out.reverse();
}

function walkLegFloorCheck(
	corners: { x: number; z: number }[],
	floor: Tri2D[],
	sampleStep: number,
): { ok: true } | { ok: false; failedAt: { x: number; z: number }; segmentIdx: number } {
	const isOnFloor = (px: number, pz: number): boolean => {
		for (let i = 0; i < floor.length; i++) {
			if (pointInTriangle(px, pz, floor[i])) return true;
		}
		return false;
	};
	for (let i = 0; i < corners.length - 1; i++) {
		const a = corners[i];
		const b = corners[i + 1];
		const len = Math.hypot(b.x - a.x, b.z - a.z);
		const steps = Math.max(1, Math.ceil(len / sampleStep));
		for (let s = 0; s <= steps; s++) {
			const t = s / steps;
			const sx = a.x + (b.x - a.x) * t;
			const sz = a.z + (b.z - a.z) * t;
			if (!isOnFloor(sx, sz)) {
				return { ok: false, failedAt: { x: sx, z: sz }, segmentIdx: i };
			}
		}
	}
	return { ok: true };
}

function tri3dToTri2d(t: Tri3D): Tri2D {
	return { x1: t.x1, z1: t.z1, x2: t.x2, z2: t.z2, x3: t.x3, z3: t.z3 };
}

function main() {
	const { questId, cellFilter, stageFilter, sampleStep, floorOnly } = parseArgs();
	const plan = loadQuestPlan(join(QUEST_PLANS, `${questId}.json`));
	const stageCfgs = JSON.parse(readFileSync(STAGE_CFG_PATH, "utf8"));

	console.log(`Quest: ${plan.questName} (${plan.questId})`);
	console.log(`Sample step: ${sampleStep}m   Floor: ${floorOnly ? "floor.glb only" : "fused floor+m"}`);
	console.log();

	let totalCells = 0;
	let okCells = 0;
	const failedCells: string[] = [];

	for (const section of plan.sections) {
		for (const cell of section.cells) {
			if (cellFilter && cell.pos !== cellFilter) continue;
			if (stageFilter && cell.stageId !== stageFilter) continue;
			totalCells++;
			const cfg = stageCfgs[cell.stageId];
			if (!cfg) {
				console.log(`✗ ${cell.pos} (${cell.stageId}): stage config missing`);
				failedCells.push(cell.pos);
				continue;
			}
			const waypoints: Waypoint[] = cfg.waypoints ?? [];
			const edges: [string, string][] = cfg.waypointEdges ?? [];
			const wpById: Record<string, Waypoint> = {};
			for (const w of waypoints) wpById[w.id] = w;
			const adj: Record<string, string[]> = {};
			for (const [a, b] of edges) {
				(adj[a] ??= []).push(b);
				(adj[b] ??= []).push(a);
			}

			// Find spawn/exit using the same direction-mapping logic as the
			// editor's cellSim memo.
			const rotation = cell.rotation ?? 0;
			const conns = cell.connections ?? {};
			const connDirs = Object.keys(conns) as Direction[];
			let entryDirGrid: Direction | null = null;
			let exitDirGrid: Direction | null = null;
			if (cell.keyGate?.direction) {
				exitDirGrid = cell.keyGate.direction as Direction;
				entryDirGrid = connDirs.find((d) => d !== exitDirGrid) ?? null;
			} else if (connDirs.length >= 2) {
				entryDirGrid = connDirs[0];
				exitDirGrid = connDirs[1];
			} else if (connDirs.length === 1) {
				entryDirGrid = connDirs[0];
				exitDirGrid = connDirs[0];
			}
			if (!entryDirGrid || !exitDirGrid) {
				console.log(`✗ ${cell.pos} (${cell.stageId}): no connections`);
				failedCells.push(cell.pos);
				continue;
			}
			const entryDirLocal = rotateDirection(entryDirGrid, -rotation);
			const exitDirLocal = rotateDirection(exitDirGrid, -rotation);
			const findWp = (kind: "spawn" | "exit", localDir: Direction): string | null => {
				const prefix = kind === "spawn" ? "spawn " : "load ";
				for (const w of waypoints) {
					if (w.kind === kind && w.label === `${prefix}${localDir}`) return w.id;
				}
				return null;
			};
			const entryId = findWp("spawn", entryDirLocal);
			const exitId = findWp("exit", exitDirLocal);
			const switchWps = waypoints.filter((w) => w.kind === "switch");

			if (!entryId || !exitId) {
				console.log(`✗ ${cell.pos} (${cell.stageId}): missing waypoints (entry=${entryDirLocal}:${!!entryId} exit=${exitDirLocal}:${!!exitId})`);
				failedCells.push(cell.pos);
				continue;
			}

			// Build sequence: spawn → each switch → exit.
			const sequence: string[] = [entryId];
			for (const sw of switchWps) sequence.push(sw.id);
			sequence.push(exitId);

			// Load floor triangles per cell. Default: fused floor+m to match
			// the solver's routing set. --floor-only restricts to floor.glb
			// only — useful for finding routes that lean on m-mesh collision.
			const subfolder = stageSubfolder(cell.stageId, plan.areaId);
			let floor3d: Tri3D[];
			try {
				if (floorOnly) {
					const floorPath = `${ASSETS_STAGES}/${subfolder}/${cell.stageId}/lndmd/${cell.stageId}-floor.glb`;
					const all = loadGlb3D(floorPath);
					const overrides = cfg.floorCollision?.triangles ?? {};
					floor3d = all.filter((_, i) => overrides[`tri_${i}`] !== false);
				} else {
					floor3d = loadStage3D(cell.stageId, subfolder, ASSETS_STAGES, cfg.floorCollision ?? {});
				}
			} catch (_e) {
				console.log(`✗ ${cell.pos} (${cell.stageId}): mesh not loadable`);
				failedCells.push(cell.pos);
				continue;
			}
			const floor2d = floor3d.map(tri3dToTri2d);

			// BFS each leg.
			let cellOk = true;
			const legResults: string[] = [];
			for (let li = 0; li < sequence.length - 1; li++) {
				const from = sequence[li];
				const to = sequence[li + 1];
				const ids = bfsPath(adj, from, to);
				if (!ids || ids.length < 2) {
					legResults.push(`L${li + 1} NO PATH (${wpById[from].label ?? from.slice(-4)} → ${wpById[to].label ?? to.slice(-4)})`);
					cellOk = false;
					continue;
				}
				const corners = ids.map((id) => ({ x: wpById[id].position[0], z: wpById[id].position[2] }));
				const r = walkLegFloorCheck(corners, floor2d, sampleStep);
				const label = `${wpById[from].label ?? from.slice(-4)} → ${wpById[to].label ?? to.slice(-4)}`;
				if (r.ok) {
					legResults.push(`L${li + 1} ✓ ${label} (${corners.length} corners)`);
				} else {
					legResults.push(`L${li + 1} ✗ ${label}: NO FLOOR at (${r.failedAt.x.toFixed(2)}, ${r.failedAt.z.toFixed(2)}) seg ${r.segmentIdx + 1}`);
					cellOk = false;
				}
			}

			const status = cellOk ? "✓" : "✗";
			console.log(`${status} ${cell.pos.padEnd(4)} (${cell.stageId})  ${entryDirLocal}→${switchWps.length}sw→${exitDirLocal}`);
			for (const r of legResults) console.log(`   ${r}`);
			if (cellOk) okCells++;
			else failedCells.push(cell.pos);
		}
	}

	console.log();
	console.log(`Cells: ${okCells}/${totalCells} ok`);
	if (failedCells.length > 0) console.log(`Failed: ${failedCells.join(", ")}`);
	process.exit(failedCells.length === 0 ? 0 : 1);
}

main();
