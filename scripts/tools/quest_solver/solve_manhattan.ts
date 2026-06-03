#!/usr/bin/env bun
// solve_manhattan — generate autopilot waypoint graphs via a 4-connected
// grid A* + L-shape decimation. Matches the user's "perpendicular first"
// strategy: stages in this game are small E/C/T/Z arenas; Manhattan paths
// follow the corridor backbone, avoid floor-mesh joins, and emit waypoints
// the autopilot's camera-relative input can drive without diagonal drift.

import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { join, resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { loadStage3D, loadGlb3D, type Tri3D } from "./lib/floor.ts";
import { buildNavGrid } from "./lib/grid.ts";
import { applyToStageConfigManhattan, solveStageGraphManhattan } from "./lib/emit_manhattan.ts";
import { cellsForStage, loadQuestPlan, stageFences, stagePoints, stagesUsed } from "./lib/quest_walk.ts";
// Walls intentionally NOT used: the solver focuses on floor + fences.
// When the autopilot gets caught on obstacle collisions, we disable
// those colliders rather than route around them.
import type { Tri2D } from "./lib/floor.ts";

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO = resolve(__dirname, "..", "..", "..");
const STAGE_SPECS = join(REPO, "data", "stage_specs");
const QUEST_PLANS = join(REPO, "data", "quest_plans");
const STAGE_CFG_PATH = join(REPO, "data", "stage_configs", "unified-stage-configs.json");
const ASSETS_STAGES = join(REPO, "assets", "stages");

const AREA_FOLDER: Record<string, string> = {
	gurhacia: "valley", ozette: "wetlands", rioh: "snowfield", makara: "makara",
	paru: "paru", arca: "arca", dark: "shrine", tower: "tower",
};

function stageSubfolder(stageId: string, areaId: string): string {
	const folder = AREA_FOLDER[areaId] ?? areaId;
	const variant = stageId.length >= 4 ? stageId[3] : "";
	return variant ? `${folder}_${variant}` : folder;
}

function parseArgs() {
	const args = process.argv.slice(2);
	if (args.length === 0 || args[0].startsWith("--")) {
		console.error("usage: bun solve_manhattan.ts <quest_id> [--apply] [--stage <id>] [--resolution <m>] [--clearance <m>]");
		process.exit(1);
	}
	const questId = args[0];
	let apply = false;
	let stageFilter: string | null = null;
	let resolution = 0.5;
	let clearance = 0;
	for (let i = 1; i < args.length; i++) {
		const a = args[i];
		if (a === "--apply") apply = true;
		else if (a === "--stage") stageFilter = args[++i];
		else if (a === "--resolution") resolution = parseFloat(args[++i]);
		else if (a === "--clearance") clearance = parseFloat(args[++i]);
		else { console.error(`unknown arg: ${a}`); process.exit(1); }
	}
	return { questId, apply, stageFilter, resolution, clearance };
}

function tri3dToTri2d(t: Tri3D): Tri2D {
	return { x1: t.x1, z1: t.z1, x2: t.x2, z2: t.z2, x3: t.x3, z3: t.z3 };
}

function main() {
	const { questId, apply, stageFilter, resolution, clearance } = parseArgs();
	const planPath = join(QUEST_PLANS, `${questId}.json`);
	const plan = loadQuestPlan(planPath);
	const stageConfigs = JSON.parse(readFileSync(STAGE_CFG_PATH, "utf8"));

	let stages = stagesUsed(plan);
	if (stageFilter) stages = stages.filter((s) => s === stageFilter);

	console.log(`Quest:       ${plan.questName} (${plan.questId})`);
	console.log(`Area:        ${plan.areaId}`);
	console.log(`Stages:      ${stages.length}`);
	console.log(`Engine:      manhattan-grid (4-conn A*, 8-conn fallback for Z-rooms)`);
	console.log(`Resolution:  ${resolution}m   Clearance: ${clearance}m`);
	console.log();

	let stageOk = 0;
	const stageFail: string[] = [];

	for (const stageId of stages) {
		const subfolder = stageSubfolder(stageId, plan.areaId);
		const cfg = stageConfigs[stageId];
		if (!cfg) {
			console.log(`✗ ${stageId}: not in unified-stage-configs.json`);
			stageFail.push(stageId);
			continue;
		}
		// Skip stages that already have a hand-authored spec — the user's
		// human-authored backbone is more topologically aware than what
		// the solver derives from triangles. The solver fills in stages
		// that haven't been authored yet.
		const specPath = join(STAGE_SPECS, `${stageId}.json`);
		if (existsSync(specPath)) {
			console.log(`◌ ${stageId.padEnd(12)} (skipped — has spec at data/stage_specs/${stageId}.json)`);
			stageOk++;
			continue;
		}

		const t0 = performance.now();
		const cells = cellsForStage(plan, stageId).map((c) => c.cell);
		const points = stagePoints(stageId, cfg, cells);
		const fences = stageFences(cells);
		const floorPath = `${ASSETS_STAGES}/${subfolder}/${stageId}/lndmd/${stageId}-floor.glb`;
		let floor3d: Tri3D[] = [];
		try {
			const all = loadGlb3D(floorPath);
			const overrides = cfg.floorCollision?.triangles ?? {};
			for (let i = 0; i < all.length; i++) {
				if (overrides[`tri_${i}`] === false) continue;
				floor3d.push(all[i]);
			}
		} catch (_e) {}

		const floorOnly2d = floor3d.map(tri3dToTri2d);
		const fused2d = loadStage3D(stageId, subfolder, ASSETS_STAGES, cfg.floorCollision ?? {}).map(tri3dToTri2d);

		// Retry ladder: floor.glb only → fused with _m.glb. Manhattan paths
		// need continuous floor; if -floor.glb is incomplete the fused mesh
		// fills the gaps (at the cost of routing through some non-walkable
		// surfaces if the visual mesh's horizontal tops slip through).
		const attempts: { label: string; tris: typeof floorOnly2d }[] = [
			{ label: "f  ", tris: floorOnly2d },
			{ label: "f+m", tris: fused2d },
		];
		let grid: ReturnType<typeof buildNavGrid> | null = null;
		let graph: ReturnType<typeof solveStageGraphManhattan> | null = null;
		let sourceTag = "f  ";
		let trisUsed = 0;
		for (const a of attempts) {
			if (a.tris.length === 0) continue;
			grid = buildNavGrid(a.tris, { resolution, clearance });
			const preSwitchGrid = fences.length > 0
				? buildNavGrid(a.tris, { resolution, clearance, fences })
				: grid;
			// Floor-coverage validation: sample every emitted edge against
			// the SAME triangle set used for routing. Catches grid-walkable
			// edges that still cross holes after clearance erosion (the
			// grid cell was big enough to span a sub-cell gap). Validating
			// against the routing set keeps the solver self-consistent;
			// runtime collision differences (player falls through m-mesh
			// surfaces) are caught by the autopilot run, not here.
			graph = solveStageGraphManhattan(stageId, grid, points, {
				preSwitchGrid,
				floorTriangles: a.tris,
			});
			sourceTag = a.label;
			trisUsed = a.tris.length;
			if (graph.stats.pathsFailed === 0) break;
		}

		if (!graph) {
			console.log(`✗ ${stageId}: no triangles loadable`);
			stageFail.push(stageId);
			continue;
		}

		const elapsed = performance.now() - t0;
		const reachStr = graph.stats.pathsFailed === 0
			? `${graph.stats.pathsSolved}/${graph.stats.pathsAttempted} paths`
			: `${graph.stats.pathsSolved}/${graph.stats.pathsAttempted} paths (${graph.stats.pathsFailed} FAILED)`;
		const status = graph.stats.pathsFailed === 0 ? "✓" : "✗";
		console.log(`${status} ${stageId.padEnd(12)} ${sourceTag} ${trisUsed.toString().padStart(5)} tris  ${graph.stats.uniqueWaypoints.toString().padStart(3)} wpts  ${graph.stats.edges.toString().padStart(3)} edges  ${reachStr.padEnd(38)} ${elapsed.toFixed(0)}ms`);

		if (graph.stats.pathsFailed === 0) {
			stageOk++;
		} else {
			stageFail.push(stageId);
		}

		stageConfigs[stageId] = applyToStageConfigManhattan(cfg, graph);
	}

	console.log();
	console.log(`Solved: ${stageOk}/${stages.length}`);
	if (stageFail.length > 0) {
		console.log(`Failed: ${stageFail.join(", ")}`);
	}

	const outPath = apply
		? STAGE_CFG_PATH
		: STAGE_CFG_PATH.replace(".json", `.manhattan.${questId}.json`);
	writeFileSync(outPath, JSON.stringify(stageConfigs, null, 2) + "\n");
	console.log(`Wrote: ${outPath.replace(REPO + "/", "")}`);
	process.exit(stageFail.length === 0 ? 0 : 1);
}

main();
