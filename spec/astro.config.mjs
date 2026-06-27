// @ts-check
import { defineConfig } from 'astro/config';
import { createReadStream, existsSync, statSync } from 'node:fs';
import { resolve, normalize } from 'node:path';

import react from '@astrojs/react';
import node from '@astrojs/node';

// Dev-only middleware: serve the repo's local working-tree assets at /local/*.
// The /cdn proxy points at the R2 mirror (published assets); /local serves the
// *uncommitted* working tree (e.g. baked weapon models, retextured GLBs) so the
// weapon gallery can review local edits before they're published. Repo root is
// the parent of spec/ (process.cwd() is spec/ when running `npm run dev`).
const REPO_ROOT = resolve(process.cwd(), '..');
function localAssets() {
  return {
    name: 'serve-local-assets',
    configureServer(server) {
      server.middlewares.use('/local/', (req, res, next) => {
        const rel = decodeURIComponent((req.url || '').split('?')[0]).replace(/^\/+/, '');
        const abs = normalize(resolve(REPO_ROOT, rel));
        if (!abs.startsWith(REPO_ROOT) || !existsSync(abs) || !statSync(abs).isFile()) {
          next();
          return;
        }
        if (abs.endsWith('.glb')) res.setHeader('Content-Type', 'model/gltf-binary');
        else if (abs.endsWith('.png')) res.setHeader('Content-Type', 'image/png');
        res.setHeader('Access-Control-Allow-Origin', '*');
        createReadStream(abs).pipe(res);
      });
    },
  };
}

// https://astro.build/config
// Deployed as the public site at psz.onl (DO droplet, systemd node server behind
// Caddy). Static-by-default so the 55 docs pages prerender (cheap on the 1GB
// box); only /api/report opts into on-demand rendering (prerender = false there).
// The node standalone server serves the prerendered pages + /play + the endpoint.
// The dev-only proxies below (/cdn → R2, /web → :5173, /local → working tree)
// exist only under `astro dev`; in production Caddy recreates /cdn → R2
// (see the deploy script / Caddyfile).
export default defineConfig({
  output: 'static',
  adapter: node({ mode: 'standalone' }),
  vite: {
    plugins: [localAssets()],
    server: {
      proxy: {
        '/web': {
          target: 'http://localhost:5173',
          changeOrigin: true,
          rewrite: (path) => path.replace(/^\/web/, '/psz-godot'),
        },
        '/cdn': {
          target: 'https://pub-8bb0622759a042aa9dbd9cb4bd1f21e6.r2.dev',
          changeOrigin: true,
          rewrite: (path) => path.replace(/^\/cdn/, ''),
        },
      },
    },
  },

  integrations: [react()],
});
