import { cpSync, existsSync, mkdirSync, statSync, createReadStream, rmSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { dirname, resolve, sep } from 'node:path';
import { pathToFileURL } from 'node:url';

// Only public assets tracked by Git enter the static artifact. Local extracted
// game assets stay on the CDN; dev /local access does not publish them.
export function siteFiles(root) {
  return {
    name: 'psz-public-files',
    hooks: {
      'astro:config:setup': ({ command, updateConfig }) => {
        // A production build can run while the local editor is open.
        const output = resolve(root, '.site-public', command);
        updateConfig({
          publicDir: pathToFileURL(output + sep),
          vite: { cacheDir: resolve(root, '.astro/cache', command) },
        });
        rmSync(output, { recursive: true, force: true });
        mkdirSync(output, { recursive: true });
        const files = execFileSync('git', ['ls-files', '-z', 'web/public', 'spec/public'], { cwd: root, encoding: 'utf8' }).split('\0').filter(Boolean);
        for (const file of files) {
          const source = resolve(root, file);
          if (!existsSync(source)) continue;
          const relative = file.replace(/^(web|spec)\/public\//, '');
          if (relative === 'data') continue;
          const dest = resolve(output, relative);
          mkdirSync(dirname(dest), { recursive: true });
          cpSync(source, dest, { recursive: true, dereference: true });
        }
        cpSync(resolve(root, 'data'), resolve(output, 'data'), { recursive: true });
        // Recordings are local-only diagnostics, deliberately absent in CI.
        if (existsSync(resolve(root, 'spec/public/recordings'))) {
          cpSync(resolve(root, 'spec/public/recordings'), resolve(output, 'recordings'), { recursive: true });
        }
        if (existsSync(resolve(root, 'assets/fonts'))) {
          cpSync(resolve(root, 'assets/fonts'), resolve(output, 'assets/fonts'), { recursive: true });
        }
      },
      'astro:server:setup': ({ server }) => {
        server.middlewares.use((req, res, next) => {
          const url = new URL(req.url ?? '/', 'http://localhost');
          const pathname = url.pathname.replace(/^\/psz-godot/, '');
          if (!pathname.startsWith('/local/')) return next();
          let file;
          try { file = resolve(root, decodeURIComponent(pathname.slice('/local/'.length))); }
          catch { res.statusCode = 400; res.end(); return; }
          // Only extracted assets are exposed, never root configuration/secrets.
          const assets = resolve(root, 'assets') + sep;
          if (!file.startsWith(assets) || !existsSync(file) || !statSync(file).isFile()) {
            res.statusCode = 404; res.end(); return;
          }
          if (file.endsWith('.glb')) res.setHeader('Content-Type', 'model/gltf-binary');
          if (file.endsWith('.png')) res.setHeader('Content-Type', 'image/png');
          createReadStream(file).pipe(res);
        });
      },
    },
  };
}
