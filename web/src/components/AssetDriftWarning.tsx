// Dev-only banner that warns when a tool's asset source has drifted from the
// other source the pipeline reads (local /assets/ tree vs the R2 CDN).
//
// Why: assetUrl() resolves to R2 when VITE_ASSETS_BASE is set, but the
// city-walk-mock (and Godot itself) read the local repo tree. A stale/broken
// local copy shadowing the canonical R2 file made a traced floor collider
// look "desynced" with no indication why (the s00e_sa2 counter incident).
// This banner names the drift the moment a tool loads an affected file.

import { useEffect, useState } from 'react';
import { checkAssetDrift, type AssetDrift } from '../utils/assets';

function kb(n: number): string {
  return n >= 1024 ? `${(n / 1024).toFixed(n >= 10240 ? 0 : 1)} KB` : `${n} B`;
}

interface Props {
  /** URLs or repo-relative paths this tool loaded; non-asset entries are ignored. */
  paths: (string | null | undefined)[];
  /** Which copy THIS tool renders: 'local' (dev-server path) or 'cdn' (assetUrl → R2). */
  shows: 'local' | 'cdn';
}

export default function AssetDriftWarning({ paths, shows }: Props) {
  const [drifts, setDrifts] = useState<AssetDrift[]>([]);

  useEffect(() => {
    let alive = true;
    const targets = paths.filter((p): p is string => !!p);
    Promise.all(targets.map((p) => checkAssetDrift(p))).then((results) => {
      if (!alive) return;
      const seen = new Set<string>();
      setDrifts(results.filter((d): d is AssetDrift => {
        if (!d || seen.has(d.path)) return false;
        seen.add(d.path);
        return true;
      }));
    });
    return () => { alive = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [paths.join('|')]);

  if (!drifts.length) return null;
  return (
    <div style={{
      background: '#5c3c00', border: '1px solid #d29922', color: '#ffd88a',
      borderRadius: 4, padding: '8px 12px', fontSize: 12, lineHeight: 1.5,
      maxWidth: 560,
    }}>
      {drifts.map((d) => (
        <div key={d.path}>
          <b>⚠ {d.path}</b> — local copy ({kb(d.localSize)}) differs from R2 ({kb(d.cdnSize)}).{' '}
          {shows === 'cdn'
            ? <>This tool is showing the <b>R2</b> file; the game (and city-walk-mock) render the <b>local</b> file.</>
            : <>This tool and the game render the <b>local</b> file; the floor-collider-builder shows the <b>R2</b> file.</>}
          {' '}Re-export or <code>npm run sync-tree</code> until they match.
        </div>
      ))}
    </div>
  );
}
