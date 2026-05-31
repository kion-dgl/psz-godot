#!/usr/bin/env bun
// solve_recast — generate autopilot waypoint graphs via recast-navigation.
//
// Replaces solve_quest.ts's hand-rolled grid+A*+clearance pipeline with the
// Recast & Detour navmesh library (the same one Godot/Unity/Unreal use).
// Recast handles agent radius, slope filtering, and floor classification
// natively from the actual 3D triangle mesh — no Y-flattening hacks, no
// wall extraction, no clearance tuning per stage.
//
// Usage:
//   bun solve_recast.ts <quest_id>
//   bun solve_recast.ts <quest_id> --apply
//   bun solve_recast.ts <quest_id> --stage s05a_tb3
//   bun solve_recast.ts <quest_id> --cell-size 0.3 --agent-radius 0.5

import { readFileSync, writeFileSync } from "node:fs";
import { join, resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { loadStage3D, loadGlb3D } from "./lib/floor.ts";
import { ensureRecast, buildRecastNavMesh } from "./lib/recast_solver.ts";
import { applyToStageConfigRecast, solveStageGraphRecast } from "./lib/emit_recast.ts";
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
		console.error("usage: bun solve_recast.ts <quest_id> [--apply] [--stage <id>] [--cell-size <m>] [--agent-radius <m>]");
		process.exit(1);
	}
	const questId = args[0];
	let apply = false;
	let stageFilter: string | null = null;
	let cellSize = 0.3;
	let agentRadius = 0.5;
	for (let i = 1; i < args.length; i++) {
		const a = args[i];
		if (a === "--apply") apply = true;
		else if (a === "--stage") stageFilter = args[++i];
		else if (a === "--cell-size") cellSize = parseFloat(args[++i]);
		else if (a === "--agent-radius") agentRadius = parseFloat(args[++i]);
		else { console.error(`unknown arg: ${a}`); process.exit(1); }
	}
	return { questId, apply, stageFilter, cellSize, agentRadius };
}

async function main() {
	await ensureRecast();
	const { questId, apply, stageFilter, cellSize, agentRadius } = parseArgs();
	const planPath = join(QUEST_PLANS, `${questId}.json`);
	const plan = loadQuestPlan(planPath);
	const stageConfigs = JSON.parse(readFileSync(STAGE_CFG_PATH, "utf8"));

	let stages = stagesUsed(plan);
	if (stageFilter) stages = stages.filter((s) => s === stageFilter);

	console.log(`Quest:        ${plan.questName} (${plan.questId})`);
	console.log(`Area:         ${plan.areaId}`);
	console.log(`Stages:       ${stages.length}`);
	console.log(`Engine:       recast-navigation`);
	console.log(`Cell size:    ${cellSize}m   Agent radius: ${agentRadius}m`);
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
		const cells = cellsForStage(plan, stageId).map((c) => c.cell);
		const points = stagePoints(stageId, cfg, cells);

		// Two-pass: try -floor.glb (curated, in-game collision) first. Only
		// fall back to fusing _m.glb (visual mesh, may include decoration with
		// horizontal tops that recast misclassifies as floor) if floor-only
		// fails to connect every required pair of points. Per-stage tag in
		// the log shows which source was used: "f" = floor only, "f+m" =
		// floor + visual mesh fallback.
		const floorPath = `${ASSETS_STAGES}/${subfolder}/${stageId}/lndmd/${stageId}-floor.glb`;
		let floorTris: any[] = [];
		try {
			const all = loadGlb3D(floorPath);
			const overrides = cfg.floorCollision?.triangles ?? {};
			for (let i = 0; i < all.length; i++) {
				if (overrides[`tri_${i}`] === false) continue;
				floorTris.push(all[i]);
			}
		} catch (_e) {}

		const buildOpts = {
			cellSize,
			cellHeight: 0.2,
			agentRadius,
			agentHeight: 1.8,
			agentMaxClimb: 0.5,
			walkableSlopeAngle: 45,
		};

		let built = floorTris.length > 0 ? buildRecastNavMesh(floorTris, buildOpts) : null;
		let graph = built ? solveStageGraphRecast(stageId, built.query, points) : null;
		let usedSource = "f  ";
		if (!built || !graph || graph.stats.pathsFailed > 0) {
			if (built) { built.navMesh.destroy(); }
			const fused = loadStage3D(stageId, subfolder, ASSETS_STAGES, cfg.floorCollision ?? {});
			if (fused.length === 0) {
				console.log(`✗ ${stageId}: no triangles (looked in ${subfolder}/${stageId}/lndmd/)`);
				stageFail.push(stageId);
				continue;
			}
			built = buildRecastNavMesh(fused, buildOpts);
			if (!built) {
				console.log(`✗ ${stageId}: navmesh build failed (${fused.length} tris)`);
				stageFail.push(stageId);
				continue;
			}
			graph = solveStageGraphRecast(stageId, built.query, points);
			usedSource = "f+m";
		}
		const tris = floorTris;
		const elapsed = performance.now() - t0;
		const reachStr = graph.stats.pathsFailed === 0
			? `${graph.stats.pathsSolved}/${graph.stats.pathsAttempted} paths`
			: `${graph.stats.pathsSolved}/${graph.stats.pathsAttempted} paths (${graph.stats.pathsFailed} FAILED)`;
		const status = graph.stats.pathsFailed === 0 ? "✓" : "✗";
		console.log(`${status} ${stageId.padEnd(12)} ${usedSource} ${tris.length.toString().padStart(5)} tris  ${graph.stats.uniqueWaypoints.toString().padStart(3)} wpts  ${graph.stats.edges.toString().padStart(3)} edges  ${reachStr.padEnd(38)} ${elapsed.toFixed(0)}ms`);

		if (graph.stats.pathsFailed === 0) {
			stageOk++;
		} else {
			stageFail.push(stageId);
		}

		stageConfigs[stageId] = applyToStageConfigRecast(cfg, graph);

		// Free the navmesh — these hold WASM memory.
		built.navMesh.destroy();
	}

	console.log();
	console.log(`Solved: ${stageOk}/${stages.length}`);
	if (stageFail.length > 0) {
		console.log(`Failed: ${stageFail.join(", ")}`);
	}

	const outPath = apply
		? STAGE_CFG_PATH
		: STAGE_CFG_PATH.replace(".json", `.recast.${questId}.json`);
	writeFileSync(outPath, JSON.stringify(stageConfigs, null, 2) + "\n");
	console.log(`Wrote: ${outPath.replace(REPO + "/", "")}`);
	process.exit(stageFail.length === 0 ? 0 : 1);
}

main();
