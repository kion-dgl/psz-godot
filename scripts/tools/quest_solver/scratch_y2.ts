import { loadGlb3D } from "./lib/floor.ts";
import { readFileSync } from "node:fs";
const cfg = JSON.parse(readFileSync("../../../data/stage_configs/unified-stage-configs.json", "utf8"));
const all = loadGlb3D("../../../assets/stages/paru_a/s05a_tb3/lndmd/s05a_tb3-floor.glb");
const overrides = cfg.s05a_tb3.floorCollision?.triangles ?? {};
const tris = all.filter((_, i) => overrides[`tri_${i}`] !== false);
function onFloor(px: number, pz: number): boolean {
  for (const t of tris) {
    const d1 = (px - t.x2) * (t.z1 - t.z2) - (t.x1 - t.x2) * (pz - t.z2);
    const d2 = (px - t.x3) * (t.z2 - t.z3) - (t.x2 - t.x3) * (pz - t.z3);
    const d3 = (px - t.x1) * (t.z3 - t.z1) - (t.x3 - t.x1) * (pz - t.z1);
    const hN = d1 < 0 || d2 < 0 || d3 < 0;
    const hP = d1 > 0 || d2 > 0 || d3 > 0;
    if (!(hN && hP)) return true;
  }
  return false;
}
// Sample a small area around the stuck point at 0.1m resolution
console.log("Floor coverage around (1.9, 20.5) at 0.1m:");
for (let z = 20.0; z <= 21.0; z += 0.1) {
  const row: string[] = [];
  for (let x = 1.0; x <= 3.0; x += 0.1) {
    row.push(onFloor(x, z) ? "·" : "█");
  }
  console.log(`z=${z.toFixed(1).padStart(4)}: ${row.join("")}`);
}
