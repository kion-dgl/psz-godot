// Dev-only Vite plugin: persist stage-editor edits back to the committed
// unified-stage-configs.json so the dev loop is edit → save → re-run autopilot
// without an export-zip + manual-unpack round trip.
//
// Endpoints:
//   POST /api/stage-config/save-stage
//     body: { stageId: string, config: object }
//     → reads data/stage_configs/unified-stage-configs.json,
//       overwrites the [stageId] key, writes back with 2-space indent.
//
//   POST /api/stage-config/reset-stage
//     body: ignored — resets ALL stage configs, not just one. Despite the
//       endpoint name and the editor's per-stage Reset button, this runs
//       `git checkout HEAD -- data/stage_configs/unified-stage-configs.json`
//       on the entire file. Fine for the dev-only undo-my-last-save flow,
//       but worth flagging so future callers know it's not stage-scoped.

import type { Plugin } from 'vite';
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import path from 'node:path';

const CONFIG_REL = 'data/stage_configs/unified-stage-configs.json';

interface SaveBody {
  stageId: string;
  config: Record<string, unknown>;
}

function saveStage(repoRoot: string, body: SaveBody): { ok: true; path: string } | { ok: false; error: string } {
  const full = path.join(repoRoot, CONFIG_REL);
  if (!existsSync(full)) return { ok: false, error: `${CONFIG_REL} not found` };
  if (!body.stageId || typeof body.stageId !== 'string') {
    return { ok: false, error: 'stageId required' };
  }
  if (!body.config || typeof body.config !== 'object') {
    return { ok: false, error: 'config object required' };
  }
  let parsed: Record<string, unknown>;
  try {
    parsed = JSON.parse(readFileSync(full, 'utf-8'));
  } catch (e) {
    return { ok: false, error: `parse error: ${(e as Error).message}` };
  }
  parsed[body.stageId] = body.config;
  writeFileSync(full, JSON.stringify(parsed, null, 2) + '\n');
  return { ok: true, path: full };
}

async function readJsonBody<T>(req: { [Symbol.asyncIterator](): AsyncIterator<Buffer | string> }): Promise<T> {
  let raw = '';
  for await (const chunk of req) raw += chunk;
  return JSON.parse(raw);
}

export default function stageConfigSavePlugin(repoRoot: string): Plugin {
  return {
    name: 'stage-config-save',
    apply: 'serve',
    configureServer(server) {
      server.middlewares.use('/api/stage-config/save-stage', async (req, res) => {
        if (req.method !== 'POST') {
          res.statusCode = 405; res.end('POST only'); return;
        }
        let body: SaveBody;
        try { body = await readJsonBody<SaveBody>(req); }
        catch (e) { res.statusCode = 400; res.end(`bad JSON: ${(e as Error).message}`); return; }
        const result = saveStage(repoRoot, body);
        res.statusCode = result.ok ? 200 : 400;
        res.setHeader('content-type', 'application/json');
        res.end(JSON.stringify(result));
      });

      server.middlewares.use('/api/stage-config/reset-stage', async (req, res) => {
        if (req.method !== 'POST') {
          res.statusCode = 405; res.end('POST only'); return;
        }
        try {
          execFileSync('git', ['checkout', 'HEAD', '--', CONFIG_REL], {
            cwd: repoRoot, stdio: 'pipe',
          });
          res.statusCode = 200;
          res.setHeader('content-type', 'application/json');
          res.end(JSON.stringify({ ok: true, path: path.join(repoRoot, CONFIG_REL) }));
        } catch (err) {
          res.statusCode = 500;
          res.end(`git checkout failed: ${(err as Error).message}`);
        }
      });
    },
  };
}
