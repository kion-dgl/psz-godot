import { useState } from 'react';
import ObjectViewer from '../object-viewer/ObjectViewer.tsx';
import roster from '../../data/weapons-gallery.json';

const TYPE_NAMES: Record<number, string> = {
  0: 'Saber', 1: 'Sword', 2: 'Dagger', 3: 'Claw', 4: 'Double Saber', 5: 'Partisan',
  6: 'Slicer', 9: 'Handgun', 10: 'Mechgun', 11: 'Rifle', 12: 'Launcher', 14: 'Rod', 15: 'Wand',
};

interface Entry {
  glb: string;
  label: string;
  type: number;
  uses?: number;
  source: 'PSO' | 'Ein';
}

/**
 * Visual review surface for the in-game weapon roster — click through every
 * modeled weapon and inspect its model, texture, and (baked) orientation
 * without launching the game. Grouped by weapon type so the PSO model and the
 * Ein model of the same type sit together for orientation comparison.
 *
 * Autorotate is off and world axes are shown (X red, Y green, Z blue) so every
 * weapon is read against a fixed frame. Source toggle: Local working tree
 * (/local, uncommitted edits) vs Published (R2, last shipped model).
 */
export default function WeaponGallery() {
  const all: Entry[] = [
    ...roster.basic.map((b: any) => ({ ...b, source: 'PSO' as const })),
    ...roster.ein.map((e: any) => ({ ...e, source: 'Ein' as const })),
  ];

  // group by weapon type, ordered by the type id
  const byType = new Map<number, Entry[]>();
  for (const w of all) {
    if (!byType.has(w.type)) byType.set(w.type, []);
    byType.get(w.type)!.push(w);
  }
  const typeIds = [...byType.keys()].sort((a, b) => a - b);

  const [sel, setSel] = useState<Entry>(all[0]);
  const [local, setLocal] = useState(
    typeof window !== 'undefined' && window.location.hostname === 'localhost',
  );

  const url = local ? `/local/${sel.glb}` : sel.glb; // bare path → assetUrl → /cdn

  return (
    <div style={{ display: 'flex', gap: 16, alignItems: 'flex-start', flexWrap: 'wrap', maxWidth: '100%' }}>
      <div style={{ flex: '0 0 230px', maxHeight: 560, overflowY: 'auto' }}>
        {typeIds.map((tid) => (
          <div key={tid} style={{ marginBottom: 10 }}>
            <div style={{ fontSize: 11, textTransform: 'uppercase', letterSpacing: 0.6, color: '#8b949e', margin: '6px 0' }}>
              {TYPE_NAMES[tid] ?? `Type ${tid}`}
            </div>
            {byType.get(tid)!.map((w) => {
              const active = w.glb === sel.glb;
              return (
                <button
                  key={w.glb + w.label}
                  onClick={() => setSel(w)}
                  style={{
                    display: 'flex', justifyContent: 'space-between', gap: 8, width: '100%',
                    textAlign: 'left', cursor: 'pointer', padding: '5px 8px', marginBottom: 2,
                    fontSize: 12.5, borderRadius: 4,
                    border: '1px solid ' + (active ? '#58a6ff' : '#30363d'),
                    background: active ? '#1f2937' : '#161b22',
                    color: active ? '#58a6ff' : '#c9d1d9',
                  }}
                >
                  <span>{w.label}</span>
                  <span style={{ fontSize: 10, color: w.source === 'Ein' ? '#a371f7' : '#6e7681' }}>{w.source}</span>
                </button>
              );
            })}
          </div>
        ))}
      </div>

      <div style={{ flex: '1 1 480px', minWidth: 320 }}>
        <div style={{ display: 'flex', gap: 10, alignItems: 'center', marginBottom: 8, flexWrap: 'wrap' }}>
          <strong style={{ fontSize: 13, color: '#e6edf3' }}>{sel.label}</strong>
          <span style={{ fontSize: 11, color: '#8b949e' }}>{TYPE_NAMES[sel.type] ?? ''} · {sel.source}</span>
          <button
            onClick={() => setLocal((v) => !v)}
            style={{
              cursor: 'pointer', padding: '4px 10px', fontSize: 12, borderRadius: 4,
              border: '1px solid #30363d', background: '#161b22', color: '#c9d1d9', marginLeft: 'auto',
            }}
          >
            Source: {local ? 'Local (working tree)' : 'Published (R2)'}
          </button>
        </div>
        <ObjectViewer key={url} glb={url} autoRotate={false} showAxes={true} />
        <p style={{ fontSize: 11.5, color: '#8b949e', marginTop: 6 }}>
          Drag to orbit · scroll to zoom · axes: <span style={{ color: '#ff6b6b' }}>X</span>{' '}
          <span style={{ color: '#51cf66' }}>Y</span> <span style={{ color: '#5c7cff' }}>Z</span> ·{' '}
          <code style={{ fontSize: 11 }}>{sel.glb}</code>
        </p>
      </div>
    </div>
  );
}
