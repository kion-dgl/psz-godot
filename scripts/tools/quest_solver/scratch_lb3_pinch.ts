import { loadGlb } from "./lib/glb.ts";
// Look for ALL triangles near (17, 9) — where player got stuck
const prims = loadGlb("../../../assets/stages/valley_a/s01a_lb3/lndmd/s01a_lb3_m.glb");
const failX = 17, failZ = 9;
const radius = 5;
let count = 0;
for (const p of prims) {
  const triCount = p.indices ? p.indices.length / 3 : p.positions.length / 9;
  for (let i = 0; i < triCount; i++) {
    const i0 = p.indices ? p.indices[i*3] : i*3;
    const i1 = p.indices ? p.indices[i*3+1] : i*3+1;
    const i2 = p.indices ? p.indices[i*3+2] : i*3+2;
    const ax = p.positions[i0*3], ay = p.positions[i0*3+1], az = p.positions[i0*3+2];
    const bx = p.positions[i1*3], by = p.positions[i1*3+1], bz = p.positions[i1*3+2];
    const cx = p.positions[i2*3], cy = p.positions[i2*3+1], cz = p.positions[i2*3+2];
    const cx2 = (ax + bx + cx) / 3, cz2 = (az + bz + cz) / 3;
    const dist = Math.hypot(cx2 - failX, cz2 - failZ);
    if (dist > radius) continue;
    const ux = bx-ax, uy = by-ay, uz = bz-az;
    const vx = cx-ax, vy = cy-ay, vz = cz-az;
    const nx = uy*vz - uz*vy, ny = uz*vx - ux*vz, nz = ux*vy - uy*vx;
    const len = Math.hypot(nx, ny, nz);
    const nyAbs = Math.abs(ny / len);
    const yRange = `[${Math.min(ay,by,cy).toFixed(1)},${Math.max(ay,by,cy).toFixed(1)}]`;
    const xRange = `[${Math.min(ax,bx,cx).toFixed(1)},${Math.max(ax,bx,cx).toFixed(1)}]`;
    const zRange = `[${Math.min(az,bz,cz).toFixed(1)},${Math.max(az,bz,cz).toFixed(1)}]`;
    count++;
    if (count <= 25) console.log(`  ny=${nyAbs.toFixed(2)} y=${yRange} x=${xRange} z=${zRange}`);
  }
}
console.log(`total: ${count} triangles within ${radius}m of (${failX}, ${failZ})`);
