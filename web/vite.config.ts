import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import path from 'path';

export default defineConfig({
  plugins: [react()],
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
