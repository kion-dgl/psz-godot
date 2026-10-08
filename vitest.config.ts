import { defineConfig } from 'vitest/config';
import { resolve } from 'node:path';
export default defineConfig({
  resolve: { alias: { '@': resolve(import.meta.dirname, 'web/src') } },
  test: { globals: true, include: ['web/src/**/*.test.ts', 'scripts/site/**/*.test.ts'] },
});
