/**
 * FieldSolver — generator + solver preview for GENERATED free fields.
 *
 * Same fidelity rule as the /field-generator grid page: the field is the
 * GridGenerator dump, never a re-implementation — the "generator" here is
 * the area + seed picker over rolls the engine itself produced. What this
 * page adds is the AREA VIEW (real room footprints composed like the
 * in-game map, MinimapSection) and the SOLVER (the route a player walks:
 * fights, key detours, gate spends, warps — the autopilot planner ported
 * to TS so it can be stepped through).
 *
 * Chrome copies the quest editor's edit page: tab shell on top, a right-hand
 * inspector for the selected cell, the same dark palette.
 */

import { useEffect, useMemo, useRef, useState } from 'react';
import { Link } from 'react-router-dom';
import MinimapSection, { ATTR_INFO } from './MinimapSection';
import {
  attrOf,
  byPos,
  checkSolvability,
  enemyCount,
  keysHeldBy,
  planRoute,
  type Cell,
  type Dump,
  type Section,
  type SolverStep,
} from './solver';
import { assetUrl } from '../utils/assets';

/** area_id → asset folder, GridGenerator.AREA_CONFIG's own mapping. */
const AREA_FOLDER: Record<string, string> = {
  gurhacia: 'valley',
  ozette: 'wetlands',
  rioh: 'snowfield',
  makara: 'ruins',
  paru: 'paru',
  arca: 'arca',
  dark: 'shrine',
  tower: 'tower',
  city: 'city',
};

type TabId = 'map' | 'solver';
const TABS: { id: TabId; label: string }[] = [
  { id: 'map', label: 'Area Map' },
  { id: 'solver', label: 'Solver' },
];

const STEP_MS = 850;

function objectCounts(cell: Cell) {
  const objects = cell.objects ?? [];
  const n = (...types: string[]) => objects.filter((o) => types.includes(o.type)).length;
  return {
    enemies: n('enemy'),
    boxes: n('box', 'rare_box'),
    walls: n('wall'),
    fences: n('fence'),
    switches: n('step_switch'),
    traps: objects.filter((o) => o.type.endsWith('_trap')).length,
  };
}

function CellInspector({ cell, solvable }: { cell: Cell | null; solvable?: boolean }) {
  if (!cell) {
    return (
      <div style={{ color: '#667', fontSize: 12, padding: '10px 2px' }}>
        Click a room on the map to inspect it.
      </div>
    );
  }
  const c = objectCounts(cell);
  const rows: [string, React.ReactNode][] = [
    ['stage', <span style={{ fontFamily: 'monospace' }}>{cell.stage_id}</span>],
    ['rotation', `${cell.rotation}°`],
    [
      'doors',
      <span>
        {Object.keys(cell.connections).length === 0
          ? 'none (single room)'
          : Object.keys(cell.connections).map((dir) => {
              const attr = attrOf(cell, dir);
              const info = ATTR_INFO[attr];
              return (
                <span key={dir} style={{ color: info?.color ?? '#888', marginRight: 8 }}>
                  {dir}:{info?.label ?? '?'}
                </span>
              );
            })}
      </span>,
    ],
    ['portals', Object.keys(cell.portals ?? {}).join(', ') || 'none'],
    [
      'content',
      `${c.enemies} enemies · ${c.boxes} boxes · ${c.traps} traps · ${c.walls} walls · ${c.fences} fences · ${c.switches} switches`,
    ],
    [
      'keys',
      keysHeldBy(cell) > 0
        ? `holds ${keysHeldBy(cell)} for the gate at ${cell.key_for_cell}`
        : 'none',
    ],
    [
      'gate',
      cell.is_key_gate
        ? `demands ${cell.required_keys ?? 1} key(s) on ${cell.key_gate_direction}`
        : 'none',
    ],
    ['warp edge', cell.warp_edge || 'none'],
    ['way back', cell.entry_warp_edge || 'none'],
    ['path order', String(cell.path_order)],
  ];
  if (solvable !== undefined) {
    rows.push(['reachable pre-route', solvable ? 'yes (purse-walk)' : 'NO — unsolvable']);
  }
  return (
    <div style={{ fontSize: 12 }}>
      <div style={{ fontFamily: 'monospace', color: '#fff', marginBottom: 8 }}>
        {cell.pos} · {cell.stage_id}
      </div>
      {rows.map(([k, v]) => (
        <div key={k} style={{ display: 'flex', gap: 8, marginBottom: 4 }}>
          <span style={{ color: '#667', width: 110, flexShrink: 0 }}>{k}</span>
          <span style={{ color: '#bcc'}}>{v}</span>
        </div>
      ))}
    </div>
  );
}

const KIND_STYLE: Record<SolverStep['kind'], { color: string; icon: string }> = {
  enter: { color: '#9aa', icon: '→' },
  clear: { color: '#ff9a9a', icon: '⚔' },
  key: { color: '#e0c97a', icon: '🔑' },
  gate: { color: '#e08a3c', icon: '🔓' },
  warp: { color: '#4a9eff', icon: '➜' },
  boss: { color: '#c98aff', icon: '★' },
};

function SectionHeader({
  section,
  solvable,
}: {
  section: Section;
  solvable: ReturnType<typeof checkSolvability>;
}) {
  return (
    <div style={{ fontSize: 12, color: '#aab', marginBottom: 6 }}>
      section <strong style={{ color: '#fff' }}>{section.area}</strong> ({section.type}) —{' '}
      {section.cells.length} cells, start {section.start_pos} → end {section.end_pos}
      {solvable.keysDemanded > 0 && (
        <span style={{ color: solvable.keysPlaced === solvable.keysDemanded ? '#8a90b8' : '#ff6b6b' }}>
          {' '}· keys {solvable.keysPlaced}/{solvable.keysDemanded}
        </span>
      )}
      <span style={{ color: solvable.solvable ? '#6ec98a' : '#ff6b6b', marginLeft: 10 }}>
        {solvable.solvable ? 'solvable' : 'UNSOLVABLE'}
      </span>
    </div>
  );
}

export default function FieldSolver() {
  const [dump, setDump] = useState<Dump | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [areaIdx, setAreaIdx] = useState(0);
  const [rollIdx, setRollIdx] = useState(0);
  const [tab, setTab] = useState<TabId>('map');
  const [selected, setSelected] = useState<{ sec: number; pos: string } | null>(null);

  // Solver state
  const [secIdx, setSecIdx] = useState(0);
  const [stepIdx, setStepIdx] = useState(0);
  const [playing, setPlaying] = useState(false);
  const logRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    fetch(assetUrl('/field-dumps/generated-fields.json'))
      .then((r) => {
        if (!r.ok) throw new Error(`${r.status} loading generated-fields.json`);
        return r.json();
      })
      .then(setDump)
      .catch((e) => setError(String(e)));
  }, []);

  const area = dump?.areas[areaIdx];
  const roll = area?.rolls[rollIdx];
  const folder = area ? (AREA_FOLDER[area.area_id] ?? 'valley') : 'valley';

  const solvabilities = useMemo(
    () => (roll ? roll.sections.map(checkSolvability) : []),
    [roll],
  );
  const routes = useMemo(
    () => (roll ? roll.sections.map(planRoute) : []),
    [roll],
  );

  // Clamp solver state when the roll changes.
  useEffect(() => {
    setSecIdx((s) => Math.min(s, (roll?.sections.length ?? 1) - 1));
    setStepIdx(0);
    setPlaying(false);
  }, [roll]);

  const section = roll?.sections[secIdx];
  const route = routes[secIdx];
  const solvable = solvabilities[secIdx];
  const step = route?.steps[Math.min(stepIdx, route.steps.length - 1)];

  // Autoplay ticker
  useEffect(() => {
    if (!playing || !route) return;
    const t = setInterval(() => {
      setStepIdx((i) => {
        if (i + 1 >= route.steps.length) {
          setPlaying(false);
          return i;
        }
        return i + 1;
      });
    }, STEP_MS);
    return () => clearInterval(t);
  }, [playing, route]);

  // Keep the log scrolled to the current step.
  useEffect(() => {
    const el = logRef.current?.querySelector('[data-current="true"]');
    el?.scrollIntoView({ block: 'nearest' });
  }, [stepIdx, tab]);

  // Walk state at the current step: rooms entered so far + the trail edge.
  const walkState = useMemo(() => {
    if (!route) return { visited: new Set<string>(), trail: null as null | { from: string; to: string } };
    const visited = new Set<string>();
    let lastEnter = '';
    let prevEnter = '';
    for (let i = 0; i <= Math.min(stepIdx, route.steps.length - 1); i++) {
      const s = route.steps[i];
      if (s.kind === 'enter') {
        prevEnter = lastEnter;
        lastEnter = s.pos;
        visited.add(s.pos);
      }
    }
    return {
      visited,
      trail: prevEnter && prevEnter !== lastEnter ? { from: prevEnter, to: lastEnter } : null,
    };
  }, [route, stepIdx]);

  if (error) {
    return (
      <div style={{ padding: 24, color: '#ff6b6b', fontFamily: 'system-ui' }}>
        <p>{error}</p>
        <p style={{ color: '#aab' }}>
          Regenerate with:{' '}
          <code>godot --headless --path . --script res://scripts/tools/dump_generated_fields.gd</code>
        </p>
      </div>
    );
  }
  if (!dump || !area || !roll) {
    return <div style={{ padding: 24, color: '#aab' }}>Loading…</div>;
  }

  const selectedCell: Cell | null =
    selected && roll.sections[selected.sec]
      ? (byPos(roll.sections[selected.sec]).get(selected.pos) ?? null)
      : null;

  const tabBtn = (id: TabId, label: string) => (
    <button
      key={id}
      onClick={() => setTab(id)}
      style={{
        background: tab === id ? '#2d2d55' : 'transparent',
        color: tab === id ? '#fff' : '#8a90b8',
        border: 'none',
        borderBottom: tab === id ? '2px solid #88aaff' : '2px solid transparent',
        padding: '8px 14px',
        fontSize: 13,
        cursor: 'pointer',
      }}
    >
      {label}
    </button>
  );

  return (
    <div
      style={{
        padding: 20,
        background: '#0f0f1e',
        height: '100%',
        overflowY: 'auto',
        boxSizing: 'border-box',
        color: '#e8e8f0',
        fontFamily: 'system-ui, sans-serif',
      }}
    >
      <h1 style={{ fontSize: 20, marginBottom: 4 }}>Generated field solver</h1>
      <p style={{ color: '#8a90b8', fontSize: 13, maxWidth: 760, marginBottom: 12 }}>
        The area view composes each room's real minimap footprint the way the in-game
        area map does; the solver steps through the route a player walks — fights, key
        detours, gate spends, warps. Fields come from the GridGenerator dump (never a
        re-implementation); <code>GridGenerator.set_seed(seed)</code> reproduces a roll
        exactly in-engine. The door-audit grid view lives on{' '}
        <Link to="/field-generator" style={{ color: '#88aaff' }}>Field Preview</Link>.
      </p>

      {/* Header controls — area, seed, tabs */}
      <div style={{ display: 'flex', gap: 20, alignItems: 'center', marginBottom: 8, flexWrap: 'wrap' }}>
        <label style={{ fontSize: 13 }}>
          Area{' '}
          <select
            value={areaIdx}
            onChange={(e) => {
              setAreaIdx(Number(e.target.value));
              setRollIdx(0);
              setSelected(null);
            }}
            style={{ background: '#1a1a2e', color: '#fff', border: '1px solid #333', padding: '4px 8px', borderRadius: 4 }}
          >
            {dump.areas.map((a, i) => (
              <option key={a.area_id} value={i}>
                {a.display_name} ({a.prefix})
              </option>
            ))}
          </select>
        </label>
        <div style={{ display: 'flex', gap: 6, alignItems: 'center', fontSize: 13 }}>
          Seed
          {area.rolls.map((r, i) => (
            <button
              key={r.seed}
              onClick={() => {
                setRollIdx(i);
                setSelected(null);
              }}
              style={{
                background: i === rollIdx ? '#3a3a6a' : 'transparent',
                color: i === rollIdx ? '#fff' : '#9aa',
                border: '1px solid #333',
                borderRadius: 4,
                padding: '4px 10px',
                cursor: 'pointer',
              }}
            >
              {r.seed}
            </button>
          ))}
        </div>
        <div style={{ display: 'flex', gap: 4, marginLeft: 'auto' }}>
          {TABS.map((t) => tabBtn(t.id, t.label))}
        </div>
      </div>

      {/* Legend */}
      <div style={{ display: 'flex', gap: 12, fontSize: 11, color: '#8a90b8', marginBottom: 14, flexWrap: 'wrap' }}>
        <span>edges:</span>
        <span style={{ color: ATTR_INFO[0].color }}>▬ open</span>
        <span style={{ color: ATTR_INFO[1].color }}>▬ one-key</span>
        <span style={{ color: ATTR_INFO[2].color }}>▬ two-key</span>
        <span style={{ color: ATTR_INFO[4].color }}>▬ enemy-defeat</span>
        <span style={{ color: '#4a9eff' }}>▬ section warp</span>
        <span style={{ color: '#4af0ff' }}>▬ way back (entry warp)</span>
        <span>· S start · E end · 🔑 key room · 🔒N gate demand</span>
      </div>

      {tab === 'map' && (
        <div style={{ display: 'flex', gap: 16, alignItems: 'flex-start', flexWrap: 'wrap' }}>
          <div>
            {roll.sections.map((sec, si) => {
              const s = solvabilities[si];
              return (
                <div key={sec.area} style={{ marginBottom: '1.25rem' }}>
                  <SectionHeader section={sec} solvable={s} />
                  <MinimapSection
                    section={sec}
                    areaFolder={folder}
                    selectedPos={selected?.sec === si ? selected.pos : null}
                    onCellClick={(pos) => setSelected({ sec: si, pos })}
                  />
                </div>
              );
            })}
          </div>
          <div
            style={{
              minWidth: 280,
              maxWidth: 340,
              background: '#12122a',
              border: '1px solid #2a2a4a',
              borderRadius: 8,
              padding: 12,
              position: 'sticky',
              top: 0,
            }}
          >
            <div style={{ fontSize: 12, color: '#88aaff', marginBottom: 6 }}>Room inspector</div>
            <CellInspector cell={selectedCell} />
          </div>
        </div>
      )}

      {tab === 'solver' && section && route && solvable && step && (
        <div style={{ display: 'flex', gap: 16, alignItems: 'flex-start', flexWrap: 'wrap' }}>
          <div>
            <div style={{ display: 'flex', gap: 6, marginBottom: 8, alignItems: 'center' }}>
              <span style={{ fontSize: 12, color: '#8a90b8' }}>section</span>
              {roll.sections.map((sec, si) => (
                <button
                  key={sec.area}
                  onClick={() => {
                    setSecIdx(si);
                    setStepIdx(0);
                    setPlaying(false);
                  }}
                  style={{
                    background: si === secIdx ? '#3a3a6a' : 'transparent',
                    color: si === secIdx ? '#fff' : '#9aa',
                    border: '1px solid #333',
                    borderRadius: 4,
                    padding: '3px 10px',
                    fontSize: 12,
                    cursor: 'pointer',
                  }}
                >
                  {sec.area} ({sec.type})
                </button>
              ))}
            </div>
            <SectionHeader section={section} solvable={solvable} />
            <MinimapSection
              section={section}
              areaFolder={folder}
              windowPx={128}
              highlightPos={step.pos}
              visited={walkState.visited}
              routeEdge={walkState.trail}
              onCellClick={(pos) => setSelected({ sec: secIdx, pos })}
            />
          </div>

          <div
            style={{
              minWidth: 320,
              flex: '0 1 380px',
              background: '#12122a',
              border: '1px solid #2a2a4a',
              borderRadius: 8,
              padding: 12,
            }}
          >
            <div style={{ display: 'flex', gap: 6, alignItems: 'center', marginBottom: 8 }}>
              <button
                onClick={() => {
                  setStepIdx(0);
                  setPlaying(false);
                }}
                style={ctrlBtn}
              >
                ⏮
              </button>
              <button onClick={() => setStepIdx((i) => Math.max(0, i - 1))} style={ctrlBtn}>
                ◀
              </button>
              <button onClick={() => setPlaying((p) => !p)} style={ctrlBtn}>
                {playing ? '⏸ pause' : '▶ play'}
              </button>
              <button
                onClick={() =>
                  setStepIdx((i) => Math.min(route.steps.length - 1, i + 1))
                }
                style={ctrlBtn}
              >
                ⏭
              </button>
              <span style={{ marginLeft: 'auto', fontSize: 12, color: '#e0c97a' }}>
                🔑 {step.keysAfter} in hand
              </span>
            </div>

            <div
              ref={logRef}
              style={{ maxHeight: 420, overflowY: 'auto', fontSize: 12, lineHeight: 1.5 }}
            >
              {route.steps.map((s, i) => {
                const ks = KIND_STYLE[s.kind];
                const isCur = i === Math.min(stepIdx, route.steps.length - 1);
                const isPast = i < stepIdx;
                return (
                  <div
                    key={i}
                    data-current={isCur}
                    onClick={() => {
                      setStepIdx(i);
                      setPlaying(false);
                    }}
                    style={{
                      display: 'flex',
                      gap: 8,
                      padding: '3px 6px',
                      borderRadius: 4,
                      cursor: 'pointer',
                      background: isCur ? '#1f1f3f' : 'transparent',
                      color: isPast ? '#667' : ks.color,
                    }}
                  >
                    <span style={{ width: 14 }}>{ks.icon}</span>
                    <span style={{ color: isPast ? '#667' : ks.color }}>{s.text}</span>
                  </div>
                );
              })}
            </div>

            <div style={{ marginTop: 10, fontSize: 11, color: '#667' }}>
              {route.steps.length} steps · {route.walk.length} room visits · detour
              round-trips included. Keys for gates off the main path are neither
              collected nor needed — the purse-walk above proves the whole section
              regardless.
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

const ctrlBtn: React.CSSProperties = {
  background: '#1a1a2e',
  color: '#fff',
  border: '1px solid #333',
  borderRadius: 4,
  padding: '4px 10px',
  fontSize: 12,
  cursor: 'pointer',
};
