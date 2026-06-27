import type { APIRoute } from 'astro';
import { mkdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';

export const prerender = false;

// Where bug reports land. On the droplet this is /srv/reports (a holding area
// you triage from); locally it defaults to ./reports for smoke-testing.
const REPORTS_DIR = process.env.REPORTS_DIR ?? './reports';

// Reports can carry a screenshot + a save blob, so allow a few MB. Anything
// larger is almost certainly junk/abuse.
const MAX_BODY = 8 * 1024 * 1024;

// Crude per-IP throttle (in-memory, resets on restart) — enough to stop a
// trivial flood. The site runs behind Caddy, so prefer X-Forwarded-For.
const WINDOW_MS = 60_000;
const MAX_PER_WINDOW = 10;
const hits = new Map<string, number[]>();

function clientIp(request: Request, fallback: string): string {
  const fwd = request.headers.get('x-forwarded-for');
  return fwd ? fwd.split(',')[0]!.trim() : fallback;
}

function throttled(ip: string): boolean {
  const now = Date.now();
  const recent = (hits.get(ip) ?? []).filter((t) => now - t < WINDOW_MS);
  recent.push(now);
  hits.set(ip, recent);
  return recent.length > MAX_PER_WINDOW;
}

function json(obj: unknown, status = 200): Response {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}

export const POST: APIRoute = async ({ request, clientAddress }) => {
  const ip = clientIp(request, clientAddress ?? 'unknown');
  if (throttled(ip)) return json({ error: 'rate limited' }, 429);

  const declaredLen = Number(request.headers.get('content-length') ?? 0);
  if (declaredLen > MAX_BODY) return json({ error: 'payload too large' }, 413);

  let body: Record<string, unknown>;
  try {
    body = await request.json();
  } catch {
    return json({ error: 'invalid json' }, 400);
  }

  const freeText = String(body.free_text ?? '').slice(0, 4000);
  const hasSave = typeof body.save_blob === 'string' && body.save_blob.length > 0;
  if (!freeText.trim() && !hasSave) {
    return json({ error: 'empty report (need free_text or save_blob)' }, 400);
  }

  // Filesystem-safe timestamped dir; UUID avoids collisions within the same ms.
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const id = randomUUID().slice(0, 8);
  const dir = join(REPORTS_DIR, `${stamp}-${id}`);
  await mkdir(dir, { recursive: true });

  const meta = {
    received_at: new Date().toISOString(),
    ip,
    user_agent: request.headers.get('user-agent'),
    source: body.source ?? null,
    version: body.version ?? null,
    quest_id: body.quest_id ?? null,
    stage_id: body.stage_id ?? null,
    cell: body.cell ?? null,
    player_pos: body.player_pos ?? null,
    sanity_tail: body.sanity_tail ?? null,
    reporter_handle: body.reporter_handle ? String(body.reporter_handle).slice(0, 120) : null,
    free_text: freeText,
  };
  await writeFile(join(dir, 'report.json'), JSON.stringify(meta, null, 2));

  // Optional binaries: data-URL screenshot + base64 save blob.
  if (typeof body.screenshot === 'string' && body.screenshot.startsWith('data:image')) {
    const b64 = body.screenshot.split(',')[1] ?? '';
    if (b64) await writeFile(join(dir, 'screenshot.png'), Buffer.from(b64, 'base64'));
  }
  if (hasSave) {
    await writeFile(join(dir, 'save.bin'), Buffer.from(body.save_blob as string, 'base64'));
  }

  return json({ ok: true, id });
};
