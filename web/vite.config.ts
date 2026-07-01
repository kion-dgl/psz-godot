import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import path from 'path';
import floorMeshPatchPlugin from './vite-plugin-floor-mesh-patch';
import stageConfigSavePlugin from './vite-plugin-stage-config-save';
import colliderExportPlugin from './vite-plugin-collider-export';

export default defineConfig({
  plugins: [
    react(),
    floorMeshPatchPlugin(path.resolve(__dirname, '..')),
    stageConfigSavePlugin(path.resolve(__dirname, '..')),
    colliderExportPlugin(path.resolve(__dirname, '..')),
  ],
  base: '/psz-godot/',
  server: {
    fs: {
      allow: ['..'],
    },
    watch: {
      // public/assets contains thousands of GLBs/PNGs that don't change
      // during editor work; watching them blows past the 65k inotify cap.
      ignored: ['**/public/assets/**', '**/node_modules/**'],
    },
  },
  resolve: {
    alias: {
      '@': path.resolve(__dirname, 'src'),
    },
  },
  test: {
    globals: true,
  },
});
