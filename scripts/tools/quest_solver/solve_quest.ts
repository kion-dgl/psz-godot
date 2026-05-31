#!/usr/bin/env bun
// solve_quest — generate autopilot waypoint graphs for every stage referenced
// by a quest plan, by ray-casting + A* over each stage's floor mesh.
//
// Reads:
//   data/quest_plans/<quest_id>.json        (autopilot's quest plan)
//   data/stage_configs/unified-stage-configs.json  (per-stage portal + floorCollision)
//   assets/stages/<area>_<variant>/<stage_id>/lndmd/{stage_id}-floor.glb
//   assets/stages/<area>_<variant>/<stage_id>/lndmd/{stage_id}_m.glb (fallback)
//
// Writes (with --apply):
//   data/stage_configs/unified-stage-configs.json — replaces `waypoints` +
//     `waypointEdges` for each stage used by the quest.
//
// Without --apply (default), writes a side file:
//   data/stage_configs/unified-stage-configs.solver.<quest_id>.json
// for inspection. The Godot autopilot reads from the main file, so dry-run
// changes nothing about the in-game behavior.
//
// Usage:
//   bun solve_quest.ts <quest_id>
//   bun solve_quest.ts <quest_id> --apply
//   bun solve_quest.ts <quest_id> --stage s01b_ic1     (single-stage debug)
//   bun solve_quest.ts <quest_id> --resolution 0.5 --clearance 1.0

import { readFileSync, writeFileSync } from "node:fs";
import { join, resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { loadStageFloor, loadStageMainMesh } from "./lib/floor.ts";
import { buildNavGrid } from "./lib/grid.ts";
import { loadStageWalls } from "./lib/walls.ts";
import { applyToStageConfig, solveStageGraph } from "./lib/emit.ts";
import { cellsForStage, loadQuestPlan, stagePoints, stagesUsed } from "./lib/quest_walk.ts";

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO = resolve(__dirname, "..", "..", "..");
const QUEST_PLANS = join(REPO, "data", "quest_plans");
const STAGE_CFG_PATH = join(REPO, "data", "stage_configs", "unified-stage-configs.json");
const ASSETS_STAGES = join(REPO, "assets", "stages");

const AREA_FOLDER: Record<string, string> = {
	gurhacia: "valley",
	ozette: "wetlands",
	rioh: "snowfield",
	makara: "makara",
	paru: "paru",
	arca: "arca",
	dark: "shrine",
	tower: "tower",
};

function stageSubfolder(stageId: string, areaId: string): string {
	const folder = AREA_FOLDER[areaId] ?? areaId;
	const variant = stageId.length >= 4 ? stageId[3] : "";
	return variant ? `${folder}_${variant}` : folder;
}

function parseArgs() {
	const args = process.argv.slice(2);
	if (args.length === 0 || args[0].startsWith("--")) {
		console.error("usage: bun solve_quest.ts <quest_id> [--apply] [--stage <id>] [--resolution <m>] [--clearance <m>]");
		process.exit(1);
	}
	const questId = args[0];
	let apply = false;
	let stageFilter: string | null = null;
	let resolution = 0.5;
	// Default clearance is small because we already block the wall XZ shadows
	// from the visual mesh. A larger clearance would also taint cells next to
	// edges of the *floor* (anything not floor counts), which kills 1m-wide
	// corridors that the player can actually fit through.
	let clearance = 0.0;
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

function main() {
	const { questId, apply, stageFilter, resolution, clearance } = parseArgs();
	const planPath = join(QUEST_PLANS, `${questId}.json`);
	const plan = loadQuestPlan(planPath);
	const stageConfigs = JSON.parse(readFileSync(STAGE_CFG_PATH, "utf8"));

	let stages = stagesUsed(plan);
	if (stageFilter) stages = stages.filter((s) => s === stageFilter);

	console.log(`Quest:      ${plan.questName} (${plan.questId})`);
	console.log(`Area:       ${plan.areaId}`);
	console.log(`Stages:     ${stages.length}`);
	console.log(`Grid:       ${resolution}m  Clearance: ${clearance}m`);
	console.log();

	let stageOk = 0;
	let stageFail: string[] = [];

	for (const stageId of stages) {
		const subfolder = stageSubfolder(stageId, plan.areaId);
		const cfg = stageConfigs[stageId];
		if (!cfg) {
			console.log(`✗ ${stageId}: not in unified-stage-configs.json`);
			stageFail.push(stageId);
			continue;
		}

		const t0 = performance.now();
		const floorTris = loadStageFloor(stageId, subfolder, ASSETS_STAGES, cfg.floorCollision ?? {});
		const walls = loadStageWalls(stageId, subfolder, ASSETS_STAGES);
		const cells = cellsForStage(plan, stageId).map((c) => c.cell);
		const points = stagePoints(stageId, cfg, cells);
		if (floorTris.length === 0 && points.length === 0) {
			console.log(`✗ ${stageId}: no floor triangles or points (looked in ${subfolder}/${stageId}/lndmd/)`);
			stageFail.push(stageId);
			continue;
		}
		// Strategy: try cumulatively more permissive grids until A* solves
		// every required path. Each retry adds one source of nav data:
		//   1. floor.glb alone, with walls + wallClearance
		//   2. floor + _m.glb fallback, with walls + wallClearance
		//   3. same as 2 but with reduced wallClearance
		//   4. same as 2 with no walls at all (last resort)
		// Most SR stages settle on (1) or (2); paru's open-style stages need (4)
		// because their _m.glb decoration meshes have steep normals that my wall
		// extractor flags as walls even though the player walks past them.
		const wallClearance = 1.5;
		const mainTris = loadStageMainMesh(stageId, subfolder, ASSETS_STAGES);
		const fused = [...floorTris, ...mainTris];
		const attempts: { label: string; tris: typeof floorTris; walls: typeof walls; wc: number }[] = [
			{ label: "f  ",      tris: floorTris, walls, wc: wallClearance },
			{ label: "f+m",      tris: fused,     walls, wc: wallClearance },
			{ label: "f+m wc=0", tris: fused,     walls, wc: 0 },
			{ label: "f+m -w",   tris: fused,     walls: [], wc: 0 },
		];
		let grid: ReturnType<typeof buildNavGrid> | null = null;
		let graph: ReturnType<typeof solveStageGraph> | null = null;
		let sourceTag = "f  ";
		for (const a of attempts) {
			grid = buildNavGrid(a.tris, { resolution, clearance, walls: a.walls, wallClearance: a.wc });
			graph = solveStageGraph(stageId, grid, points);
			sourceTag = a.label;
			if (graph.stats.pathsFailed === 0) break;
		}
		const usedFallback = sourceTag !== "f  ";

		const elapsed = performance.now() - t0;
		if (graph == null) graph = { stats: { stagePoints: 0, pathsAttempted: 0, pathsFailed: 0, pathsSolved: 0, uniqueWaypoints: 0, edges: 0 }, waypoints: [], waypointEdges: [] };
		const reachStr = graph.stats.pathsFailed === 0
			? `${graph.stats.pathsSolved}/${graph.stats.pathsAttempted} paths`
			: `${graph.stats.pathsSolved}/${graph.stats.pathsAttempted} paths (${graph.stats.pathsFailed} FAILED)`;
		const status = graph.stats.pathsFailed === 0 ? "✓" : "✗";
		console.log(`${status} ${stageId.padEnd(12)} ${sourceTag.padEnd(9)} ${floorTris.length.toString().padStart(4)} tris  ${graph.stats.uniqueWaypoints.toString().padStart(3)} wpts  ${graph.stats.edges.toString().padStart(3)} edges  ${reachStr.padEnd(38)} ${elapsed.toFixed(0)}ms`);

		if (graph.stats.pathsFailed === 0) {
			stageOk++;
		} else {
			stageFail.push(stageId);
		}

		stageConfigs[stageId] = applyToStageConfig(cfg, graph);
	}

	console.log();
	console.log(`Solved: ${stageOk}/${stages.length}`);
	if (stageFail.length > 0) {
		console.log(`Failed: ${stageFail.join(", ")}`);
	}

	const outPath = apply
		? STAGE_CFG_PATH
		: STAGE_CFG_PATH.replace(".json", `.solver.${questId}.json`);
	writeFileSync(outPath, JSON.stringify(stageConfigs, null, 2) + "\n");
	console.log(`Wrote: ${outPath.replace(REPO + "/", "")}`);
	process.exit(stageFail.length === 0 ? 0 : 1);
}

main();
