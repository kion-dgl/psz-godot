// Dev-only Vite plugin: write-backs for the #/city-lab tool.
//
//   POST /api/city-lab/export-glb?path=<repo-relative>  body: raw GLB bytes
//     → writes the fixed city-market export to the repo. The path must be
//       exactly assets/stages/city_e/market/dairon3.glb — this endpoint
//       only ever writes the market lineage re-export (dairon2 stays the
//       rollback), never arbitrary files.
//   POST /api/city-lab/save-lights   body: { stageId, json }
//     → writes data/stage_configs/city-lights/<stageId>.json, the sidecar
//       city_area_base._add_authored_lights loads. stageId must be a known
//       city stage id (s00e_* for now); the doc shape is checked before
//       the write.
//
// Same contract as vite-plugin-collider-export: dev server only
// (apply: 'serve'), the client does the serialisation, the server just
// validates and writes bytes.

import type { Plugin } from 'vite';
import { writeFileSync, mkdirSync } from 'node:fs';
import path from 'node:path';

const GLB_TARGET = 'assets/stages/city_e/market/dairon3.glb';
const ALLOWED_STAGE_IDS = ['s00e_sa2'];

interface SaveLightsBody {
  stageId?: string;
  json?: { stage?: string; ambient?: Record<string, unknown>; lights?: unknown[] };
}

export default function cityLabPlugin(repoRoot: string): Plugin {
  return {
    name: 'city-lab',
    apply: 'serve',
    configureServer(server) {
      server.middlewares.use('/api/city-lab/export-glb', async (req, res) => {
        if (req.method !== 'POST') {
          res.statusCode = 405;
          res.end('POST only');
          return;
        }
        const url = new URL(req.url ?? '', 'http://localhost');
        const rel = (url.searchParams.get('path') ?? '').replace(/^\/+/, '');
        const abs = path.resolve(repoRoot, rel);
        const within = path.relative(repoRoot, abs).replace(/\\/g, '/');
        if (within !== GLB_TARGET) {
          res.statusCode = 400;
          res.end(`bad path (only ${GLB_TARGET}): ${rel}`);
          return;
        }
        const chunks: Buffer[] = [];
        for await (const chunk of req) chunks.push(chunk as Buffer);
        const buf = Buffer.concat(chunks);
        if (buf.length < 12 || buf.readUInt32LE(0) !== 0x46546c67) {
          res.statusCode = 400;
          res.end('body is not a GLB (bad magic)');
          return;
        }
        try {
          mkdirSync(path.dirname(abs), { recursive: true });
          writeFileSync(abs, buf);
          res.statusCode = 200;
          res.setHeader('content-type', 'application/json');
          res.end(JSON.stringify({ ok: true, path: within, bytes: buf.length }));
        } catch (err) {
          res.statusCode = 500;
          res.end(`write failed: ${(err as Error).message}`);
        }
      });

      server.middlewares.use('/api/city-lab/save-lights', async (req, res) => {
        if (req.method !== 'POST') {
          res.statusCode = 405;
          res.end('POST only');
          return;
        }
        let raw = '';
        for await (const chunk of req) raw += chunk;
        let body: SaveLightsBody;
        try {
          body = JSON.parse(raw);
        } catch (e) {
          res.statusCode = 400;
          res.end(`bad JSON: ${(e as Error).message}`);
          return;
        }
        const stageId = body.stageId ?? '';
        const doc = body.json;
        if (!ALLOWED_STAGE_IDS.includes(stageId)) {
          res.statusCode = 400;
          res.end(`unknown stageId (allowed: ${ALLOWED_STAGE_IDS.join(', ')}): ${stageId}`);
          return;
        }
        if (
          !doc || typeof doc !== 'object' || doc.stage !== stageId ||
          !Array.isArray(doc.lights) || typeof doc.ambient !== 'object' || doc.ambient === null
        ) {
          res.statusCode = 400;
          res.end('bad lights doc (needs stage/ambient/lights)');
          return;
        }
        const abs = path.join(repoRoot, 'data/stage_configs/city-lights', `${stageId}.json`);
        try {
          mkdirSync(path.dirname(abs), { recursive: true });
          writeFileSync(abs, `${JSON.stringify(doc, null, 2)}\n`);
          res.statusCode = 200;
          res.setHeader('content-type', 'application/json');
          res.end(JSON.stringify({ ok: true, path: path.relative(repoRoot, abs), lights: doc.lights.length }));
        } catch (err) {
          res.statusCode = 500;
          res.end(`write failed: ${(err as Error).message}`);
        }
      });
    },
  };
}
