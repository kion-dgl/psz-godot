import { defineConfig } from 'astro/config';
import react from '@astrojs/react';
import { resolve } from 'node:path';
import floorMeshPatch from './web/vite-plugin-floor-mesh-patch.ts';
import stageConfigSave from './web/vite-plugin-stage-config-save.ts';
import colliderExport from './web/vite-plugin-collider-export.ts';
import cityLab from './web/vite-plugin-city-lab.ts';
import { siteFiles } from './scripts/site/files.mjs';

const root = import.meta.dirname;
export default defineConfig({
  site: 'https://kion-dgl.github.io',
  base: '/psz-godot',
  trailingSlash: 'always',
  srcDir: './spec/src',
  publicDir: './.site-public',
  outDir: './dist/site',
  output: 'static',
  integrations: [siteFiles(root), react()],
  vite: {
    resolve: { alias: { '@': resolve(root, 'web/src') }, dedupe: ['react', 'react-dom', 'three'] },
    define: {
      'import.meta.env.VITE_ASSETS_BASE': JSON.stringify(process.env.VITE_ASSETS_BASE ?? 'https://pub-8bb0622759a042aa9dbd9cb4bd1f21e6.r2.dev'),
    },
    plugins: [floorMeshPatch(root), stageConfigSave(root), colliderExport(root), cityLab(root)],
    server: {
      fs: { allow: [root] },
      watch: { ignored: ['**/assets/**', '**/archive/**', '**/.site-public/**'] },
      proxy: {
        '/cdn': {
          target: process.env.VITE_ASSETS_BASE ?? 'https://pub-8bb0622759a042aa9dbd9cb4bd1f21e6.r2.dev',
          changeOrigin: true,
          rewrite: path => path.replace(/^\/cdn/, ''),
        },
      },
    },
  },
});
