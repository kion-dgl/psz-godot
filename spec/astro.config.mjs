// @ts-check
import { defineConfig } from 'astro/config';

import react from '@astrojs/react';

// https://astro.build/config
export default defineConfig({
  vite: {
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