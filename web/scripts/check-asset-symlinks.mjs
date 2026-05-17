#!/usr/bin/env node
// Ensures dev-only symlinks under web/public/assets/ point at the repo's
// /assets/ tree. Vite serves files out of web/public/, and we keep the
// repo asset tree (~250 MB of GLBs/PNGs) outside that directory, so each
// runtime subtree needs a symlink. These aren't tracked in git — every
// dev box has to recreate them. Missing ones cause silent 404s and, in
// at least one case, an R3F crash when an ErrorBoundary fallback tries
// to render <div> inside <Canvas>.
//
// Behavior: auto-create when the target exists, log what happened,
// hard-fail only if the symlink slot is occupied by something else
// (a real file or a directory). If a target is missing, warn but don't
// fail — devs may legitimately work on non-asset code with no /assets/.

import { existsSync, lstatSync, readlinkSync, symlinkSync } from 'node:fs';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const WEB_ROOT = resolve(SCRIPT_DIR, '..');
const REPO_ROOT = resolve(WEB_ROOT, '..');
const PUBLIC_ASSETS = join(WEB_ROOT, 'public', 'assets');

// name → relative target (from web/public/assets/)
const REQUIRED = {
  enemies: '../../../assets/enemies',
  npcs: '../../../assets/npcs',
  objects: '../../../assets/objects',
  player: '../../../assets/player',
  stages: '../../../assets/stages',
};

let created = 0;
let missingTargets = [];
let failures = [];

for (const [name, relTarget] of Object.entries(REQUIRED)) {
  const linkPath = join(PUBLIC_ASSETS, name);
  const absTarget = resolve(PUBLIC_ASSETS, relTarget);

  let entry = null;
  try { entry = lstatSync(linkPath); } catch { entry = null; }

  if (entry?.isSymbolicLink()) {
    const current = readlinkSync(linkPath);
    if (current !== relTarget) {
      console.warn(`[symlinks] ${name}: points at "${current}", expected "${relTarget}" — leaving as-is`);
    }
    continue;
  }

  if (entry) {
    failures.push(`${name}: web/public/assets/${name} exists but isn't a symlink (${entry.isDirectory() ? 'directory' : 'file'}). Remove it manually.`);
    continue;
  }

  if (!existsSync(absTarget)) {
    missingTargets.push(`${name}: target ${absTarget} doesn't exist — run scripts/tools/fetch_assets_dev.sh to populate assets/`);
    continue;
  }

  try {
    symlinkSync(relTarget, linkPath);
    console.log(`[symlinks] created web/public/assets/${name} -> ${relTarget}`);
    created++;
  } catch (e) {
    failures.push(`${name}: ${e.message}`);
  }
}

for (const w of missingTargets) console.warn(`[symlinks] WARN ${w}`);
if (failures.length) {
  for (const f of failures) console.error(`[symlinks] ERROR ${f}`);
  process.exit(1);
}

if (created === 0 && missingTargets.length === 0) {
  // Quiet success — nothing to do.
} else if (created > 0) {
  console.log(`[symlinks] ok (${created} created)`);
}
