import { loadStageFloor, loadStageMainMesh } from "./lib/floor.ts";
import { loadStageWalls } from "./lib/walls.ts";
import { buildNavGrid, isWalkable, worldToGrid, gridToWorld } from "./lib/grid.ts";
import { astar } from "./lib/pathfinder.ts";
import { readFileSync } from "node:fs";
const cfg = JSON.parse(readFileSync("../../../data/stage_configs/unified-stage-configs.json", "utf8"));
const floorTris = loadStageFloor("s01a_lb3", "valley_a", "../../../assets/stages", cfg.s01a_lb3.floorCollision);
const walls = loadStageWalls("s01a_lb3", "valley_a", "../../../assets/stages");
const g = buildNavGrid(floorTris, { resolution: 0.5, clearance: 0, walls });

// Visualize area around failure point (x in [10, 25], z in [5, 15])
console.log("Zoomed view (0.5m grid) around (17, 9):");
for (let z = 0; z <= 16; z += 0.5) {
  const row: string[] = [];
  for (let x = 10; x <= 25; x += 0.5) {
    const rc = worldToGrid(g, x, z);
    row.push(isWalkable(g, rc.r, rc.c) ? "·" : "█");
  }
  console.log(`z=${z.toFixed(1).padStart(5)}: ${row.join("")}`);
}

// Try A* from (16.5, 8.7) to (20.8, 11.9)
const s = worldToGrid(g, 16.5, 8.7);
const e = worldToGrid(g, 20.8, 11.9);
console.log(`\nstart walkable: ${isWalkable(g, s.r, s.c)}, end walkable: ${isWalkable(g, e.r, e.c)}`);
const p = astar(g, s, e);
console.log(`A*: ${p ? p.cells.length + " cells" : "NO PATH"}`);
if (p) {
  console.log("Path (every 5th cell):");
  for (let i = 0; i < p.cells.length; i += 5) {
    const w = gridToWorld(g, p.cells[i].r, p.cells[i].c);
    console.log(`  (${w.x.toFixed(1)}, ${w.z.toFixed(1)})`);
  }
}
