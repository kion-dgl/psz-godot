import { useEffect, useMemo, useState } from 'react';
import { assetUrl } from '../utils/assets';

/**
 * Grid viewer for GENERATED free fields.
 *
 * Deliberately renders a JSON dump produced by GridGenerator itself
 * (scripts/tools/dump_generated_fields.gd) rather than re-implementing the
 * generator in TypeScript. A second implementation would drift from the one the
 * game ships, and then this page would be validating the wrong generator — the
 * opposite of what it is for.
 *
 * Each roll carries the seed that produced it, so anything that looks wrong here
 * is reproducible in-engine with GridGenerator.set_seed(seed), and comparable
 * against the real game's output once psz-re can dump a field for a known seed.
 */

interface Cell {
  pos: string;
  stage_id: string;
  rotation: number;
  connections: Record<string, string>;
  portals?: Record<string, string>;
  objects?: { type: string; enemy_id?: string }[];
  is_start: boolean;
  is_end: boolean;
  is_branch: boolean;
  has_key: boolean;
  key_for_cell: string;
  is_key_gate: boolean;
  key_gate_direction: string;
  warp_edge: string;
  path_order: number;
}

interface Section {
  type: string;
  area: string;
  cells: Cell[];
  start_pos: string;
  end_pos: string;
}

interface Roll {
  seed: number;
  sections: Section[];
}

interface Area {
  area_id: string;
  display_name: string;
  prefix: string;
  rolls: Roll[];
}

interface Dump {
  difficulty: string;
  grid_size: number;
  areas: Area[];
}

const DIRS = ['north', 'east', 'south', 'west'] as const;
type Dir = (typeof DIRS)[number];

/** Grid offsets must match GridGenerator.DIR_OFFSET: north is row-1. */
const DIR_OFFSET: Record<Dir, [number, number]> = {
  north: [-1, 0],
  south: [1, 0],
  east: [0, 1],
  west: [0, -1],
};
const OPPOSITE: Record<Dir, Dir> = {
  north: 'south',
  south: 'north',
  east: 'west',
  west: 'east',
};

const CELL_PX = 108;

function parsePos(pos: string): [number, number] {
  const [r, c] = pos.split(',').map((n) => parseInt(n, 10));
  return [r, c];
}

/** Same invariants the Godot test pins, recomputed here so the page can show
 *  WHERE a problem is rather than just that the suite went red. */
function auditSection(section: Section): Record<string, string[]> {
  const byPos = new Map(section.cells.map((c) => [c.pos, c]));
  const problems: Record<string, string[]> = {};
  const add = (pos: string, msg: string) => {
    (problems[pos] ||= []).push(msg);
  };

  for (const cell of section.cells) {
    for (const [dir, target] of Object.entries(cell.connections)) {
      const other = byPos.get(target);
      if (!other) {
        add(cell.pos, `${dir} → ${target}, which is not in this section`);
        continue;
      }
      if (other.connections[OPPOSITE[dir as Dir]] !== cell.pos) {
        add(cell.pos, `one-way ${dir} → ${target}`);
      }
      if (cell.portals && !(dir in cell.portals)) {
        add(cell.pos, `connection ${dir} has no portal`);
      }
    }
  }

  // start must reach end
  const { start_pos, end_pos } = section;
  if (byPos.has(start_pos) && byPos.has(end_pos) && start_pos !== end_pos) {
    const seen = new Set([start_pos]);
    const queue = [start_pos];
    let found = false;
    while (queue.length) {
      const cur = queue.shift() as string;
      if (cur === end_pos) {
        found = true;
        break;
      }
      for (const next of Object.values(byPos.get(cur)!.connections)) {
        if (byPos.has(next) && !seen.has(next)) {
          seen.add(next);
          queue.push(next);
        }
      }
    }
    if (!found) add(start_pos, `cannot reach end cell ${end_pos}`);
  }
  return problems;
}

function CellBox({
  cell,
  problems,
}: {
  cell: Cell;
  problems: string[];
}) {
  const enemies = (cell.objects ?? []).filter((o) => o.type === 'enemy').length;
  const boxes = (cell.objects ?? []).filter((o) => o.type === 'box').length;
  const bad = problems.length > 0;

  let bg = '#242438';
  if (cell.is_start) bg = '#1d4d3a';
  else if (cell.is_end) bg = '#4d331d';
  else if (cell.is_branch) bg = '#2d2440';
  if (bad) bg = '#5a1f1f';

  return (
    <div
      title={
        `${cell.stage_id}  rot=${cell.rotation}°\n` +
        `connections: ${Object.entries(cell.connections).map(([d, t]) => `${d}→${t}`).join(', ') || 'none'}\n` +
        `portals: ${Object.keys(cell.portals ?? {}).join(', ') || 'none'}\n` +
        `${enemies} enemies, ${boxes} boxes` +
        (problems.length ? `\n\nPROBLEMS:\n- ${problems.join('\n- ')}` : '')
      }
      style={{
        position: 'absolute',
        left: 0,
        top: 0,
        width: CELL_PX - 10,
        height: CELL_PX - 10,
        background: bg,
        border: `1px solid ${bad ? '#ff6b6b' : '#3a3a5a'}`,
        borderRadius: 6,
        padding: 5,
        boxSizing: 'border-box',
        fontSize: 10,
        lineHeight: 1.25,
        overflow: 'hidden',
      }}
    >
      <div style={{ fontFamily: 'monospace', color: '#cfd4ff' }}>
        {cell.stage_id.split('_')[1] ?? cell.stage_id}
      </div>
      <div style={{ color: '#8a90b8' }}>{cell.rotation}°</div>
      <div style={{ color: '#9aa' }}>
        {enemies > 0 && <span>{enemies}e </span>}
        {boxes > 0 && <span>{boxes}b</span>}
      </div>
      <div style={{ color: '#e0c97a' }}>
        {cell.has_key && '🔑'}
        {cell.is_key_gate && '🔒'}
        {cell.warp_edge && '➜'}
      </div>
    </div>
  );
}

/** A connection drawn as a stub from the cell edge, so a one-way pair shows as
 *  a stub with nothing meeting it. */
function ConnectionStubs({ cell }: { cell: Cell }) {
  return (
    <>
      {Object.keys(cell.connections).map((dir) => {
        const d = dir as Dir;
        const horizontal = d === 'east' || d === 'west';
        const len = 12;
        const style: React.CSSProperties = {
          position: 'absolute',
          background: '#6b74b8',
          width: horizontal ? len : 3,
          height: horizontal ? 3 : len,
        };
        const mid = (CELL_PX - 10) / 2;
        if (d === 'north') Object.assign(style, { left: mid, top: -len });
        if (d === 'south') Object.assign(style, { left: mid, top: CELL_PX - 10 });
        if (d === 'west') Object.assign(style, { left: -len, top: mid });
        if (d === 'east') Object.assign(style, { left: CELL_PX - 10, top: mid });
        return <div key={dir} style={style} />;
      })}
    </>
  );
}

function SectionGrid({ section }: { section: Section }) {
  const problems = useMemo(() => auditSection(section), [section]);
  const problemCount = Object.values(problems).reduce((n, list) => n + list.length, 0);

  // The generator emits sparse coordinates on a gridSize x gridSize board but a
  // section only occupies part of it. Frame to the cells actually used, or most
  // of the board is empty padding.
  const coords = section.cells.map((c) => parsePos(c.pos));
  const rows = coords.map(([r]) => r);
  const cols = coords.map(([, c]) => c);
  const minRow = Math.min(...rows);
  const minCol = Math.min(...cols);
  const maxRow = Math.max(...rows);
  const maxCol = Math.max(...cols);

  return (
    <div style={{ marginBottom: '1.25rem' }}>
      <div style={{ fontSize: 12, color: '#aab', marginBottom: 6 }}>
        section <strong style={{ color: '#fff' }}>{section.area}</strong> ({section.type}) —{' '}
        {section.cells.length} cells, start {section.start_pos} → end {section.end_pos}
        {problemCount > 0 && (
          <span style={{ color: '#ff6b6b' }}> · {problemCount} door problem(s)</span>
        )}
      </div>
      <div
        style={{
          position: 'relative',
          width: (maxCol - minCol + 1) * CELL_PX,
          height: (maxRow - minRow + 1) * CELL_PX,
          background: '#15152a',
          border: '1px solid #2a2a45',
          borderRadius: 8,
        }}
      >
        {section.cells.map((cell) => {
          const [r, c] = parsePos(cell.pos);
          return (
            <div
              key={cell.pos}
              style={{
                position: 'absolute',
                left: (c - minCol) * CELL_PX + 5,
                top: (r - minRow) * CELL_PX + 5,
                width: CELL_PX - 10,
                height: CELL_PX - 10,
              }}
            >
              <ConnectionStubs cell={cell} />
              <CellBox cell={cell} problems={problems[cell.pos] ?? []} />
            </div>
          );
        })}
      </div>
    </div>
  );
}

export default function FieldGenerator() {
  const [dump, setDump] = useState<Dump | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [areaIdx, setAreaIdx] = useState(0);
  const [rollIdx, setRollIdx] = useState(0);

  useEffect(() => {
    fetch(assetUrl('/field-dumps/generated-fields.json'))
      .then((r) => {
        if (!r.ok) throw new Error(`${r.status} loading generated-fields.json`);
        return r.json();
      })
      .then(setDump)
      .catch((e) => setError(String(e)));
  }, []);

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
  if (!dump) return <div style={{ padding: 24, color: '#aab' }}>Loading…</div>;

  const area = dump.areas[areaIdx];
  const roll = area.rolls[rollIdx];
  const totalProblems = roll.sections.reduce(
    (n, s) => n + Object.values(auditSection(s)).reduce((m, l) => m + l.length, 0),
    0,
  );

  return (
    <div
      style={{
        padding: 20,
        background: '#0f0f1e',
        minHeight: '100%',
        color: '#e8e8f0',
        fontFamily: 'system-ui, sans-serif',
      }}
    >
      <h1 style={{ fontSize: 20, marginBottom: 4 }}>Generated field grids</h1>
      <p style={{ color: '#8a90b8', fontSize: 13, maxWidth: 760, marginBottom: 16 }}>
        Rendered from a dump of GridGenerator itself, not a re-implementation — so what you see is
        what the game builds. Each roll records the seed that produced it;{' '}
        <code>GridGenerator.set_seed(seed)</code> reproduces it exactly in-engine.
      </p>

      <div style={{ display: 'flex', gap: 20, alignItems: 'center', marginBottom: 16, flexWrap: 'wrap' }}>
        <label style={{ fontSize: 13 }}>
          Area{' '}
          <select
            value={areaIdx}
            onChange={(e) => {
              setAreaIdx(Number(e.target.value));
              setRollIdx(0);
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
              onClick={() => setRollIdx(i)}
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

        <div
          style={{
            fontSize: 13,
            color: totalProblems ? '#ff6b6b' : '#6ec98a',
          }}
        >
          {totalProblems ? `${totalProblems} door problem(s)` : 'doors line up'}
        </div>
      </div>

      <div style={{ display: 'flex', gap: 12, fontSize: 11, color: '#8a90b8', marginBottom: 14, flexWrap: 'wrap' }}>
        <span>🔑 holds key</span>
        <span>🔒 key gate</span>
        <span>➜ section exit</span>
        <span style={{ color: '#6ec98a' }}>■ start</span>
        <span style={{ color: '#c9a06e' }}>■ end</span>
        <span style={{ color: '#a08ac9' }}>■ branch</span>
        <span style={{ color: '#ff6b6b' }}>■ problem (hover for detail)</span>
      </div>

      {roll.sections.map((section) => (
        <SectionGrid key={section.area} section={section} />
      ))}
    </div>
  );
}
