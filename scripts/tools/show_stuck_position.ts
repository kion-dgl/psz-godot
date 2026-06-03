#!/usr/bin/env bun
// Render an annotated top-down ASCII map of the s02a_ga1 floor mesh
// showing the stuck-walk player position, walk direction, and the
// 3 _can_move_to lateral sample points.

import { loadGlb3D, type Tri3D } from "./quest_solver/lib/floor.ts";

const GLB = "assets/stages/wetlands_a/s02a_ga1/lndmd/s02a_ga1-floor.glb";
const tris = loadGlb3D(GLB);

// Stuck-walk diagnostic data
const px = -0.017, pz = 7.845;
const tx = -0.019, tz = 22.901;
const dx = 0, dz = 1;
const FLOOR_CHECK_DISTANCE = 1.0;
const FLOOR_CHECK_SIDE = 0.5;
const cx = px + dx * FLOOR_CHECK_DISTANCE;
const cz = pz + dz * FLOOR_CHECK_DISTANCE;
const sideX = -dz, sideZ = dx;
const lx = cx + sideX * FLOOR_CHECK_SIDE, lz = cz + sideZ * FLOOR_CHECK_SIDE;
const rx = cx - sideX * FLOOR_CHECK_SIDE, rz = cz - sideZ * FLOOR_CHECK_SIDE;
// Also the 1.5x fallback probe
const cx15 = px + dx * FLOOR_CHECK_DISTANCE * 1.5;
const cz15 = pz + dz * FLOOR_CHECK_DISTANCE * 1.5;

function inTri(qx: number, qz: number, t: Tri3D): boolean {
	const dX = qx - t.x3, dY = qz - t.z3;
	const dX21 = t.x2 - t.x3, dY12 = t.z3 - t.z2;
	const D = dY12 * (t.x1 - t.x3) + dX21 * (t.z1 - t.z3);
	if (D === 0) return false;
	const s = (dY12 * dX + dX21 * dY) / D;
	const tt = ((t.z3 - t.z1) * dX + (t.x1 - t.x3) * dY) / D;
	return s >= 0 && tt >= 0 && s + tt <= 1;
}
function floor(qx: number, qz: number): boolean {
	for (const t of tris) if (inTri(qx, qz, t)) return true;
	return false;
}

// Render a focused 6m × 6m window around the player, 0.1m step
const stepX = 0.1, stepZ = 0.1;
const xMin = -3, xMax = 3;
const zMin = 6.5, zMax = 11.5;

console.log(`Stage: s02a_ga1`);
console.log(`Player world pos:   (${px}, 0.190, ${pz})`);
console.log(`Walk target:        (${tx}, 0.000, ${tz})`);
console.log(`Walk direction:     (${dx}, 0, ${dz})  (pure +Z / north)`);
console.log(`Distance to target: ${Math.hypot(tx - px, tz - pz).toFixed(2)}m`);
console.log("");
console.log(`Floor sample at FLOOR_CHECK_DISTANCE=1.0:`);
console.log(`  center=(${cx.toFixed(2)}, ${cz.toFixed(2)}) floor=${floor(cx, cz)}`);
console.log(`  left  =(${lx.toFixed(2)}, ${lz.toFixed(2)}) floor=${floor(lx, lz)}`);
console.log(`  right =(${rx.toFixed(2)}, ${rz.toFixed(2)}) floor=${floor(rx, rz)}`);
console.log(`Floor sample at FLOOR_CHECK_DISTANCE=1.5 (fallback):`);
console.log(`  center=(${cx15.toFixed(2)}, ${cz15.toFixed(2)}) floor=${floor(cx15, cz15)}`);
console.log("");
console.log(`Top-down view of s02a_ga1 floor mesh (X right, Z down = north).`);
console.log(`Legend: '.'=floor  ' '=void  'P'=player  '^'=walk dir  'C/L/R'=1.0m sample  '*'=1.5m sample`);
console.log("");

// X axis ruler
let ruler = "       ";
for (let x = xMin; x <= xMax; x += 0.5) {
	const slot = Math.round((x - xMin) / stepX);
	while (ruler.length < 7 + slot) ruler += " ";
	const label = x === 0 ? "0" : x > 0 ? `+${x}` : `${x}`;
	ruler += label;
}
console.log(ruler);

for (let z = zMin; z <= zMax; z += stepZ) {
	let row = `z=${z.toFixed(1).padStart(4)}  `;
	for (let x = xMin; x <= xMax; x += stepX) {
		// Choose marker priority
		const near = (qx: number, qz: number) => Math.abs(x - qx) < stepX / 2 && Math.abs(z - qz) < stepZ / 2;
		if (near(px, pz)) row += "P";
		else if (near(cx, cz)) row += "C";
		else if (near(lx, lz)) row += "L";
		else if (near(rx, rz)) row += "R";
		else if (near(cx15, cz15)) row += "*";
		else if (Math.abs(x - px) < stepX / 2 && z > pz && z < cz - stepZ) row += "^";  // direction arrow column
		else row += floor(x, z) ? "." : " ";
	}
	console.log(row);
}
