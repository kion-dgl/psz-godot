import { loadStageWalls } from "./lib/walls.ts";
const walls = loadStageWalls("s01a_lb3", "valley_a", "../../../assets/stages");
const failX = 17, failZ = 9;
let foundCount = 0;
for (const w of walls) {
  const xMin = Math.min(w.x1, w.x2, w.x3);
  const xMax = Math.max(w.x1, w.x2, w.x3);
  const zMin = Math.min(w.z1, w.z2, w.z3);
  const zMax = Math.max(w.z1, w.z2, w.z3);
  if (xMax < failX - 5 || xMin > failX + 5 || zMax < failZ - 5 || zMin > failZ + 5) continue;
  foundCount++;
  console.log(`  wall x=[${xMin.toFixed(1)},${xMax.toFixed(1)}] z=[${zMin.toFixed(1)},${zMax.toFixed(1)}]`);
}
console.log(`walls in 5m radius of (${failX},${failZ}): ${foundCount}`);
