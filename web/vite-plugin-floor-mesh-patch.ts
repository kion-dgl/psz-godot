// Dev-only Vite plugin: POST /api/floor-mesh/patch-vertex patches a single
// vertex's X/Y/Z floats in a stage's -floor.glb on disk.
//
// Body: { stageId: string, primIdx: number, vertexIdx: number, x: number, y: number, z: number }
//
// The GLB binary format is: 12-byte header + JSON chunk + BIN chunk. POSITION
// data lives in the BIN chunk at:
//   binStart + bufferViews[positionAccessor.bufferView].byteOffset
//   + positionAccessor.byteOffset
//   + vertexIdx * stride + (0|4|8) for X|Y|Z (each float32 LE)
//
// Indexed meshes share vertices across triangles — editing vertex N moves
// every triangle that references N. That's the desired behavior for sealing
// cracks (move two coincident-but-not-equal vertices to the same XZ).

import type { Plugin } from 'vite';
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import path from 'node:path';

const AREA_PREFIX_MAP: Record<string, string> = {
  '00': 'city',
  '01': 'valley',
  '02': 'wetlands',
  '03': 'snowfield',
  '04': 'makara',
  '05': 'paru',
  '06': 'arca',
  '07': 'shrine',
  '08': 'tower',
};

function resolveFloorGlb(repoRoot: string, stageId: string): string | null {
  const m = stageId.match(/^s(\d{2})([a-z])_/);
  if (!m) return null;
  const folder = AREA_PREFIX_MAP[m[1]];
  if (!folder) return null;
  const subfolder = `${folder}_${m[2]}`;
  const p = path.join(repoRoot, 'assets', 'stages', subfolder, stageId, 'lndmd', `${stageId}-floor.glb`);
  return existsSync(p) ? p : null;
}

interface PatchBody {
  stageId: string;
  primIdx: number;
  vertexIdx: number;
  x: number;
  y: number;
  z: number;
}

function patchGlbVertex(glbPath: string, body: PatchBody): { ok: true } | { ok: false; error: string } {
  const buf = readFileSync(glbPath);
  const view = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);

  const magic = view.getUint32(0, true);
  if (magic !== 0x46546c67) return { ok: false, error: 'not a GLB file' };

  const jsonLen = view.getUint32(12, true);
  const jsonStr = new TextDecoder('utf-8').decode(buf.subarray(20, 20 + jsonLen));
  const json = JSON.parse(jsonStr);

  const padding = (4 - (jsonLen % 4)) % 4;
  const binStart = 20 + jsonLen + padding + 8;

  // Walk meshes.primitives in declaration order — same order the client sees.
  let flatPrimIdx = 0;
  let targetAcc = -1;
  for (const mesh of json.meshes ?? []) {
    for (const prim of mesh.primitives ?? []) {
      if (flatPrimIdx === body.primIdx) {
        targetAcc = prim.attributes?.POSITION;
        break;
      }
      flatPrimIdx++;
    }
    if (targetAcc !== -1) break;
  }
  if (targetAcc === -1) return { ok: false, error: `primIdx ${body.primIdx} out of range` };

  const acc = json.accessors[targetAcc];
  const bv = json.bufferViews[acc.bufferView];
  if (body.vertexIdx < 0 || body.vertexIdx >= acc.count) {
    return { ok: false, error: `vertexIdx ${body.vertexIdx} out of range (count=${acc.count})` };
  }
  const stride = bv.byteStride ?? 12;
  const offset = binStart + (bv.byteOffset ?? 0) + (acc.byteOffset ?? 0) + body.vertexIdx * stride;

  view.setFloat32(offset + 0, body.x, true);
  view.setFloat32(offset + 4, body.y, true);
  view.setFloat32(offset + 8, body.z, true);

  writeFileSync(glbPath, buf);
  return { ok: true };
}

export default function floorMeshPatchPlugin(repoRoot: string): Plugin {
  return {
    name: 'floor-mesh-patch',
    apply: 'serve',
    configureServer(server) {
      server.middlewares.use('/api/floor-mesh/patch-vertex', async (req, res) => {
        if (req.method !== 'POST') {
          res.statusCode = 405;
          res.end('POST only');
          return;
        }
        let raw = '';
        for await (const chunk of req) raw += chunk;
        let body: PatchBody;
        try {
          body = JSON.parse(raw);
        } catch (e) {
          res.statusCode = 400;
          res.end(`bad JSON: ${(e as Error).message}`);
          return;
        }
        const glb = resolveFloorGlb(repoRoot, body.stageId);
        if (!glb) {
          res.statusCode = 404;
          res.end(`no floor GLB for stage ${body.stageId}`);
          return;
        }
        const result = patchGlbVertex(glb, body);
        res.statusCode = result.ok ? 200 : 400;
        res.setHeader('content-type', 'application/json');
        res.end(JSON.stringify(result.ok ? { ok: true, path: glb } : result));
      });

      // Restore the GLB to its git HEAD state. Lets the editor offer a
      // one-tap "undo all my edits" bailout for the active stage.
      server.middlewares.use('/api/floor-mesh/reset', async (req, res) => {
        if (req.method !== 'POST') {
          res.statusCode = 405;
          res.end('POST only');
          return;
        }
        let raw = '';
        for await (const chunk of req) raw += chunk;
        let body: { stageId: string };
        try {
          body = JSON.parse(raw);
        } catch (e) {
          res.statusCode = 400;
          res.end(`bad JSON: ${(e as Error).message}`);
          return;
        }
        const glb = resolveFloorGlb(repoRoot, body.stageId);
        if (!glb) {
          res.statusCode = 404;
          res.end(`no floor GLB for stage ${body.stageId}`);
          return;
        }
        try {
          const rel = path.relative(repoRoot, glb);
          execFileSync('git', ['checkout', 'HEAD', '--', rel], { cwd: repoRoot, stdio: 'pipe' });
          res.statusCode = 200;
          res.setHeader('content-type', 'application/json');
          res.end(JSON.stringify({ ok: true, path: glb }));
        } catch (err) {
          res.statusCode = 500;
          res.end(`git checkout failed: ${(err as Error).message}`);
        }
      });
    },
  };
}
