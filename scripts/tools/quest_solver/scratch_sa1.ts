import { loadStageFloor, loadStageMainMesh } from "./lib/floor.ts";
import { loadStageWalls } from "./lib/walls.ts";
import { buildNavGrid, isWalkable, worldToGrid } from "./lib/grid.ts";
import { astar } from "./lib/pathfinder.ts";
import { readFileSync } from "node:fs";

const cfg = JSON.parse(readFileSync("../../../data/stage_configs/unified-stage-configs.json", "utf8"));
const stage = cfg.s05b_sa1;
console.log("portals:", stage.portals);
const floorTris = loadStageFloor("s05b_sa1", "paru_b", "../../../assets/stages", stage.floorCollision);
const mainTris = loadStageMainMesh("s05b_sa1", "paru_b", "../../../assets/stages");
const walls = loadStageWalls("s05b_sa1", "paru_b", "../../../assets/stages");
console.log(`floor=${floorTris.length}, main=${mainTris.length}, walls=${walls.length}`);

const g = buildNavGrid([...floorTris, ...mainTris], { resolution: 0.5, clearance: 0, walls, wallClearance: 0 });
let walkable = 0;
for (let i = 0; i < g.walkable.length; i++) walkable += g.walkable[i];
console.log(`grid: ${g.rows}x${g.cols}, walkable=${walkable}`);

// For each portal pair, try A*
const portals = stage.portals;
for (let i = 0; i < portals.length; i++) {
  for (let j = i + 1; j < portals.length; j++) {
    const a = portals[i], b = portals[j];
    const ax = a.position[0], az = a.position[2];
    const bx = b.position[0], bz = b.position[2];
    const sa = worldToGrid(g, ax, az);
    const sb = worldToGrid(g, bx, bz);
    const p = astar(g, sa, sb);
    console.log(`${a.direction} (${ax},${az}) → ${b.direction} (${bx},${bz}): ${p ? p.cells.length + " cells" : "NO PATH"} | wa=${isWalkable(g,sa.r,sa.c)} wb=${isWalkable(g,sb.r,sb.c)}`);
  }
}

// Print a coarse map
console.log("\nMap (1m, no walls):");
const gNoW = buildNavGrid([...floorTris, ...mainTris], { resolution: 0.5, clearance: 0 });
const bx0 = Math.floor(g.minX), by0 = Math.floor(g.minZ);
for (let z = by0; z <= -by0; z += 1) {
  const row: string[] = [];
  for (let x = bx0; x <= -bx0; x += 1) {
    const rc = worldToGrid(g, x, z);
    const w = isWalkable(g, rc.r, rc.c);
    const wn = isWalkable(gNoW, rc.r, rc.c);
    row.push(w ? "·" : (wn ? "W" : "█"));
  }
  console.log(`${z.toString().padStart(3)}: ${row.join("")}`);
}
