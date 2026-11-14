// Dev-only Vite plugin: write floor-collider GLBs and city boundary JSON
// sidecars built by `#/floor-collider-builder` back into the repo.
//
//   POST /api/collider/export?path=<repo-relative>   body: raw GLB bytes
//     → writes the bytes to <repoRoot>/<path>, creating parent dirs.
//   POST /api/collider/reset   body: { path }
//     → `git checkout HEAD -- <path>` if tracked, else deletes the file.
//   GET  /api/collider/boundary?area=<market|underground|office|counter>
//     → reads <repoRoot>/data/stage_configs/city-boundaries/<area>.json.
//   POST /api/collider/save-boundary   body: { areaId, config }
//     → writes <repoRoot>/data/stage_configs/city-boundaries/<areaId>.json.

import type { Plugin } from 'vite';
import { writeFileSync, readFileSync, mkdirSync, existsSync, unlinkSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import path from 'node:path';

const ALLOWED_CITY_AREAS = new Set(['market']);

function resolveSafe(repoRoot: string, rel: string): string | null {
  const cleaned = rel.replace(/^\/+/, '');
  const abs = path.resolve(repoRoot, cleaned);
  const within = path.relative(repoRoot, abs).replace(/\\/g, '/');
  if (within.startsWith('..') || path.isAbsolute(within)) return null;
  if (!/^assets\/stages\/[^.][^:]*-floor\.glb$/.test(within)) {
    return null;
  }
  return abs;
}

function resolveSafeBoundary(repoRoot: string, areaId: string): string | null {
  const key = areaId.trim().toLowerCase();
  if (!ALLOWED_CITY_AREAS.has(key)) return null;
  return path.resolve(repoRoot, 'data/stage_configs/city-boundaries', `${key}.json`);
}

export default function colliderExportPlugin(repoRoot: string): Plugin {
  return {
    name: 'collider-export',
    apply: 'serve',
    configureServer(server) {
      server.middlewares.use('/api/collider/export', async (req, res) => {
        if (req.method !== 'POST') {
          res.statusCode = 405;
          res.end('POST only');
          return;
        }
        const url = new URL(req.url ?? '', 'http://localhost');
        const rel = url.searchParams.get('path') ?? '';
        const abs = resolveSafe(repoRoot, rel);
        if (!abs) {
          res.statusCode = 400;
          res.end(`bad path (must be assets/stages/...-floor.glb): ${rel}`);
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
          res.end(JSON.stringify({ ok: true, path: path.relative(repoRoot, abs), bytes: buf.length }));
        } catch (err) {
          res.statusCode = 500;
          res.end(`write failed: ${(err as Error).message}`);
        }
      });

      server.middlewares.use('/api/collider/reset', async (req, res) => {
        if (req.method !== 'POST') {
          res.statusCode = 405;
          res.end('POST only');
          return;
        }
        let raw = '';
        for await (const chunk of req) raw += chunk;
        let body: { path: string };
        try {
          body = JSON.parse(raw);
        } catch (e) {
          res.statusCode = 400;
          res.end(`bad JSON: ${(e as Error).message}`);
          return;
        }
        const abs = resolveSafe(repoRoot, body.path ?? '');
        if (!abs) {
          res.statusCode = 400;
          res.end(`bad path: ${body.path}`);
          return;
        }
        const rel = path.relative(repoRoot, abs);
        try {
          let tracked = true;
          try {
            execFileSync('git', ['cat-file', '-e', `HEAD:${rel.replace(/\\/g, '/')}`], {
              cwd: repoRoot,
              stdio: 'pipe',
            });
          } catch {
            tracked = false;
          }
          if (tracked) {
            execFileSync('git', ['checkout', 'HEAD', '--', rel], { cwd: repoRoot, stdio: 'pipe' });
          } else if (existsSync(abs)) {
            unlinkSync(abs);
          }
          res.statusCode = 200;
          res.setHeader('content-type', 'application/json');
          res.end(JSON.stringify({ ok: true, path: rel, action: tracked ? 'checkout' : 'unlink' }));
        } catch (err) {
          res.statusCode = 500;
          res.end(`reset failed: ${(err as Error).message}`);
        }
      });

      server.middlewares.use('/api/collider/boundary', (req, res) => {
        if (req.method !== 'GET') {
          res.statusCode = 405;
          res.end('GET only');
          return;
        }
        const url = new URL(req.url ?? '', 'http://localhost');
        const area = url.searchParams.get('area') ?? '';
        const abs = resolveSafeBoundary(repoRoot, area);
        if (!abs) {
          res.statusCode = 400;
          res.end(`bad area (must be market|underground|office|counter): ${area}`);
          return;
        }
        if (!existsSync(abs)) {
          res.statusCode = 404;
          res.end(`boundary config not found: ${area}`);
          return;
        }
        try {
          const text = readFileSync(abs, 'utf8');
          res.statusCode = 200;
          res.setHeader('content-type', 'application/json');
          res.end(text);
        } catch (err) {
          res.statusCode = 500;
          res.end(`read failed: ${(err as Error).message}`);
        }
      });

      server.middlewares.use('/api/collider/save-boundary', async (req, res) => {
        if (req.method !== 'POST') {
          res.statusCode = 405;
          res.end('POST only');
          return;
        }
        let raw = '';
        for await (const chunk of req) raw += chunk;
        let body: { areaId?: string; config?: Record<string, unknown> };
        try {
          body = JSON.parse(raw);
        } catch (e) {
          res.statusCode = 400;
          res.end(`bad JSON: ${(e as Error).message}`);
          return;
        }
        const areaId = String(body.areaId ?? '');
        const abs = resolveSafeBoundary(repoRoot, areaId);
        if (!abs) {
          res.statusCode = 400;
          res.end(`bad areaId (must be market|underground|office|counter): ${areaId}`);
          return;
        }
        const cfg = body.config;
        if (!cfg || typeof cfg !== 'object' || !Array.isArray(cfg.perimeter) || cfg.perimeter.length < 3) {
          res.statusCode = 400;
          res.end('invalid boundary config (perimeter must have >= 3 points)');
          return;
        }
        try {
          mkdirSync(path.dirname(abs), { recursive: true });
          const serialized = JSON.stringify({ ...cfg, areaId }, null, 2) + '\n';
          writeFileSync(abs, serialized, 'utf8');
          const rel = path.relative(repoRoot, abs).replace(/\\/g, '/');
          res.statusCode = 200;
          res.setHeader('content-type', 'application/json');
          res.end(JSON.stringify({ ok: true, path: rel, bytes: Buffer.byteLength(serialized, 'utf8') }));
        } catch (err) {
          res.statusCode = 500;
          res.end(`write failed: ${(err as Error).message}`);
        }
      });
    },
  };
}
