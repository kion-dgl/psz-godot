// Dev-only Vite plugin: write a floor-collider GLB built by the floor-collider
// builder tool back into the repo.
//
//   POST /api/collider/export?path=<repo-relative>   body: raw GLB bytes
//     → writes the bytes to <repoRoot>/<path>, creating parent dirs.
//   POST /api/collider/reset   body: { path }
//     → `git checkout HEAD -- <path>` if tracked, else deletes the file.
//
// The client (FloorColliderBuilder) serialises the selected triangles to a
// binary GLB via three's GLTFExporter and POSTs the ArrayBuffer here — the
// server just validates the path and writes bytes, so there's no GLB encoding
// logic to keep in sync between client and server.
//
// Path safety: the target must resolve under assets/stages/.../lndmd/ and end
// in -floor.glb. Anything else is rejected — this endpoint only writes floor
// colliders, never arbitrary files.

import type { Plugin } from 'vite';
import { writeFileSync, mkdirSync, existsSync, unlinkSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import path from 'node:path';

function resolveSafe(repoRoot: string, rel: string): string | null {
  // Normalise and confine to any -floor.glb under assets/stages/ (covers both
  // the lndmd/ stage layout and the flat market/ layout where dairon2 lives).
  const cleaned = rel.replace(/^\/+/, '');
  const abs = path.resolve(repoRoot, cleaned);
  const within = path.relative(repoRoot, abs).replace(/\\/g, '/');
  if (within.startsWith('..') || path.isAbsolute(within)) return null;
  if (!/^assets\/stages\/[^.][^:]*-floor\.glb$/.test(within)) {
    return null;
  }
  return abs;
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

      // Undo: restore the collider to git HEAD, or delete it if it's a new
      // (untracked) file. Lets the tool offer a one-tap bailout.
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
          // Tracked in git? → checkout. Untracked? → unlink.
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
    },
  };
}
