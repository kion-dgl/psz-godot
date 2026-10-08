import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { createServer, type ViteDevServer } from 'vite';
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import collider from '../../web/vite-plugin-collider-export';
import stages from '../../web/vite-plugin-stage-config-save';
import city from '../../web/vite-plugin-city-lab';
import floor from '../../web/vite-plugin-floor-mesh-patch';

describe('retained local editor endpoints', () => {
  let root: string;
  let server: ViteDevServer;
  let origin: string;
  beforeAll(async () => {
    root = mkdtempSync(join(tmpdir(), 'psz-site-editors-'));
    mkdirSync(join(root, 'data/stage_configs'), { recursive: true });
    writeFileSync(join(root, 'data/stage_configs/unified-stage-configs.json'), '{}');
    server = await createServer({
      configFile: false, root, plugins: [collider(root), stages(root), city(root), floor(root)],
      server: { port: 0, host: '127.0.0.1' },
    });
    await server.listen();
    const address = server.httpServer!.address() as { port: number };
    origin = `http://127.0.0.1:${address.port}`;
  });
  afterAll(async () => {
    await server?.close();
    if (root) rmSync(root, { recursive: true, force: true });
  });
  const post = (path: string, body: unknown) => fetch(origin + path, {
    method: 'POST', body: JSON.stringify(body), headers: { 'Content-Type': 'application/json' },
  });
  it('saves stage configuration into the supplied repository root', async () => {
    const response = await post('/api/stage-config/save-stage/', { stageId: 'probe', config: { rotation: 90 } });
    expect(response.status).toBe(200);
    expect(JSON.parse(readFileSync(join(root, 'data/stage_configs/unified-stage-configs.json'), 'utf8')).probe.rotation).toBe(90);
  });
  it('exports a collider without touching the actual game assets', async () => {
    const path = 'assets/stages/probe/probe-floor.glb';
    const bytes = Buffer.alloc(12);
    bytes.writeUInt32LE(0x46546c67);
    const response = await fetch(`${origin}/api/collider/export/?path=${path}`, { method: 'POST', body: bytes });
    expect(response.status).toBe(200);
    expect(readFileSync(join(root, path))).toEqual(bytes);
  });
  it('saves city light documents', async () => {
    const doc = { stage: 's00e_sa2', ambient: {}, lights: [] };
    const response = await post('/api/city-lab/save-lights/', { stageId: doc.stage, json: doc });
    expect(response.status).toBe(200);
    expect(JSON.parse(readFileSync(join(root, 'data/stage_configs/city-lights/s00e_sa2.json'), 'utf8'))).toEqual(doc);
  });
  it('keeps all four plugin families reachable and rejects non-POST requests', async () => {
    for (const path of ['/api/collider/reset/', '/api/city-lab/export-glb/', '/api/stage-config/reset-stage/', '/api/floor-mesh/patch-vertex/']) {
      expect((await fetch(origin + path)).status).toBe(405);
    }
  });
});
