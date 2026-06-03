#!/usr/bin/env bun
// Inspect floor mesh coverage around a point in a stage's floor GLB.
// Reports: which triangles are at this point, what's the floor coverage
// in a 1m radius, and how the can_move_to (center + left + right) sample
// would behave at various N-of-3 thresholds.

import { loadGlb3D, type Tri3D } from "./quest_solver/lib/floor.ts";
import { existsSync } from "node:fs";

const [stagePath, xs, zs, dirXs, dirZs, txs, tzs] = process.argv.slice(2);
if (!stagePath || !xs || !zs) {
	console.error("usage: bun scripts/tools/inspect_floor_at.ts <stage_id> <x> <z> [dir_x] [dir_z] [target_x] [target_z]");
	console.error("  ex:  bun scripts/tools/inspect_floor_at.ts s02a_ga1 0 7.8 0 1");
	console.error("  ex:  bun scripts/tools/inspect_floor_at.ts s02a_ga1 0 7.8 0 1 -3.9 -15.8  (also map around the target)");
	process.exit(2);
}

const x = parseFloat(xs);
const z = parseFloat(zs);
// Default direction: due south (+z)
const dirX = parseFloat(dirXs ?? "0");
const dirZ = parseFloat(dirZs ?? "1");

// Same constants as scripts/3d/player/player.gd:74-76
const FLOOR_CHECK_DISTANCE = 1.0;
const FLOOR_CHECK_SIDE = 0.5;

// Find the stage's -floor.glb under assets/stages/<area>/<stage_id>/lndmd/
const AREA_PREFIX_MAP: Record<string, string> = {
	s01: "valley_a", s02: "wetlands_a", s05: "paru_a",
};
const stageKey = stagePath.slice(0, 3);
const areaCandidates = ["valley_a", "valley_b", "wetlands_a", "wetlands_b", "paru_a", "paru_b", "snowfield_a", "snowfield_b"];
let glbPath = "";
for (const a of areaCandidates) {
	const candidate = `assets/stages/${a}/${stagePath}/lndmd/${stagePath}-floor.glb`;
	if (existsSync(candidate)) {
		glbPath = candidate;
		break;
	}
}
if (!glbPath) {
	console.error(`could not find floor mesh for stage ${stagePath}`);
	process.exit(2);
}
console.log(`loaded: ${glbPath}`);

const tris = loadGlb3D(glbPath);
console.log(`${tris.length} triangles in floor mesh`);

// 2D point-in-triangle test (XZ plane, ignores Y for walkability check
// — matches the spirit of _has_floor_at's downward raycast).
function pointInTri2D(px: number, pz: number, t: Tri3D): boolean {
	const dX = px - t.x3, dY = pz - t.z3;
	const dX21 = t.x2 - t.x3, dY12 = t.z3 - t.z2;
	const D = dY12 * (t.x1 - t.x3) + dX21 * (t.z1 - t.z3);
	if (D === 0) return false;
	const s = (dY12 * dX + dX21 * dY) / D;
	const tt = ((t.z3 - t.z1) * dX + (t.x1 - t.x3) * dY) / D;
	return s >= 0 && tt >= 0 && s + tt <= 1;
}

function hasFloorAt(px: number, pz: number): boolean {
	for (const t of tris) {
		if (pointInTri2D(px, pz, t)) return true;
	}
	return false;
}

// Helper: sample N points in a grid around a center to visualize coverage
function coverageMap(cx: number, cz: number, radius: number, step: number) {
	const lines: string[] = [];
	for (let dz = -radius; dz <= radius; dz += step) {
		let row = "";
		for (let dx = -radius; dx <= radius; dx += step) {
			const px = cx + dx, pz = cz + dz;
			if (Math.abs(dx) < step / 2 && Math.abs(dz) < step / 2) {
				row += hasFloorAt(px, pz) ? "+" : "X";  // center marker
			} else {
				row += hasFloorAt(px, pz) ? "." : " ";
			}
		}
		lines.push(`z=${(cz + dz).toFixed(1).padStart(6)}  ${row}`);
	}
	return lines;
}

// Normalize direction. Guard the (0,0) case — without this, both components
// divide by zero and every downstream sample/probe lands at NaN, which the
// floor-coverage routine silently returns false for and makes the diagnostic
// look like "no floor anywhere" regardless of the actual mesh.
const dirLen = Math.hypot(dirX, dirZ);
const dx = dirLen === 0 ? 0 : dirX / dirLen;
const dz = dirLen === 0 ? 1 : dirZ / dirLen;
if (dirLen === 0) {
	console.log(`\nplayer at (${x}, ${z}), no direction passed — defaulting to due-south probe`);
} else {
	console.log(`\nplayer at (${x}, ${z}), moving toward (${dx.toFixed(2)}, ${dz.toFixed(2)})`);
}

// Sample at FLOOR_CHECK_DISTANCE ahead (the can_move_to check)
const cx = x + dx * FLOOR_CHECK_DISTANCE;
const cz = z + dz * FLOOR_CHECK_DISTANCE;
// Perpendicular: rotate 90° (-dz, dx) — matches player.gd:1087
const sideX = -dz, sideZ = dx;
const lx = cx + sideX * FLOOR_CHECK_SIDE, lz = cz + sideZ * FLOOR_CHECK_SIDE;
const rx = cx - sideX * FLOOR_CHECK_SIDE, rz = cz - sideZ * FLOOR_CHECK_SIDE;

console.log(`\n_can_move_to check sample points (forward ${FLOOR_CHECK_DISTANCE}m, side ±${FLOOR_CHECK_SIDE}m):`);
console.log(`  center: (${cx.toFixed(2)}, ${cz.toFixed(2)}) → floor: ${hasFloorAt(cx, cz)}`);
console.log(`  left:   (${lx.toFixed(2)}, ${lz.toFixed(2)}) → floor: ${hasFloorAt(lx, lz)}`);
console.log(`  right:  (${rx.toFixed(2)}, ${rz.toFixed(2)}) → floor: ${hasFloorAt(rx, rz)}`);

const hits = [hasFloorAt(cx, cz), hasFloorAt(lx, lz), hasFloorAt(rx, rz)].filter(Boolean).length;
console.log(`  → hits: ${hits}/3`);
console.log(`  → all-3 rule:  ${hits === 3 ? "PASS" : "BLOCK"}`);
console.log(`  → 2-of-3 rule: ${hits >= 2 ? "PASS" : "BLOCK"}`);
console.log(`  → 1-of-3 rule: ${hits >= 1 ? "PASS" : "BLOCK"}`);

// Also try axis-fallback (player.gd:1059-1066 tries x-only then z-only)
function tryAxis(dx2: number, dz2: number, label: string) {
	const _cx = x + dx2 * FLOOR_CHECK_DISTANCE, _cz = z + dz2 * FLOOR_CHECK_DISTANCE;
	const _sx = -dz2, _sz = dx2;
	const _lx = _cx + _sx * FLOOR_CHECK_SIDE, _lz = _cz + _sz * FLOOR_CHECK_SIDE;
	const _rx = _cx - _sx * FLOOR_CHECK_SIDE, _rz = _cz - _sz * FLOOR_CHECK_SIDE;
	const h = [hasFloorAt(_cx, _cz), hasFloorAt(_lx, _lz), hasFloorAt(_rx, _rz)].filter(Boolean).length;
	console.log(`  ${label}: hits=${h}/3 (all3=${h===3?"PASS":"BLOCK"} 2of3=${h>=2?"PASS":"BLOCK"})`);
}
console.log(`\naxis-fallback (player slides along obstruction):`);
if (dx !== 0) tryAxis(Math.sign(dx), 0, `x-only (${Math.sign(dx)}, 0)`);
if (dz !== 0) tryAxis(0, Math.sign(dz), `z-only (0, ${Math.sign(dz)})`);

// Visualize a 4m × 4m coverage map around the player
console.log(`\nfloor coverage map (4m × 4m around player, step 0.25m, '.'=floor ' '=void '+'=player):`);
const lines = coverageMap(x, z, 2, 0.25);
console.log(lines.join("\n"));

// And around the target waypoint for context. Reads positional args 6 + 7
// via the named `txs`/`tzs` destructured at the top — earlier this used
// `process.argv[6]`/`[7]` directly, which collided with the dir_x/dir_z
// slots and made the target-around-map print at the wrong coordinates
// whenever direction args were also passed.
if (txs !== undefined && tzs !== undefined) {
	const tx = parseFloat(txs);
	const tz = parseFloat(tzs);
	if (!Number.isNaN(tx) && !Number.isNaN(tz)) {
		console.log(`\nfloor coverage map around target waypoint (${tx}, ${tz}):`);
		console.log(coverageMap(tx, tz, 2, 0.25).join("\n"));
	}
}

// Find continuous corridor in the desired direction. Build the direction
// label without the "due southnorth" string-concat bug — only one of the
// X/Z components contributes when the other is zero.
function dirLabel(dxc: number, dzc: number): string {
	const xPart = dxc === 0 ? "" : (dxc > 0 ? "east" : "west");
	const zPart = dzc === 0 ? "" : (dzc > 0 ? "south" : "north");
	if (xPart && zPart) return `${zPart}-${xPart}`;
	return xPart || zPart || "stationary";
}
console.log(`\nwalking forward ${dirLabel(dx, dz)} from player, where does floor end?`);
let probeDist = 0;
for (let d = 0; d < 30; d += 0.1) {
	const px = x + dx * d;
	const pz = z + dz * d;
	if (!hasFloorAt(px, pz)) {
		console.log(`  no floor at d=${d.toFixed(1)}m (${px.toFixed(2)}, ${pz.toFixed(2)})`);
		probeDist = d;
		break;
	}
}
if (probeDist === 0) {
	console.log(`  continuous floor for 30m`);
}

// Bonus: scan X offsets to find a continuous south-walking corridor
console.log(`\nscanning X offsets for continuous floor corridor from z=${z.toFixed(1)} to z=${(z + 15).toFixed(1)}:`);
for (let testX = -10; testX <= 10; testX += 0.5) {
	let maxRun = 0, curRun = 0;
	for (let testZ = z; testZ <= z + 15; testZ += 0.25) {
		if (hasFloorAt(testX, testZ)) {
			curRun += 0.25;
			if (curRun > maxRun) maxRun = curRun;
		} else {
			curRun = 0;
		}
	}
	const bar = "█".repeat(Math.floor(maxRun * 2));
	console.log(`  x=${testX.toFixed(1).padStart(5)}: max continuous = ${maxRun.toFixed(2).padStart(5)}m ${bar}`);
}
