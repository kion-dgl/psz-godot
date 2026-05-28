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
      },
    },
  },

  integrations: [react()],
});