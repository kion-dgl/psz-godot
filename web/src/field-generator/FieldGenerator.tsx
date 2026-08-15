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

interface FieldObject {
  type: string;
  enemy_id?: string;
  /** Room-local (x, y, z). Authored props carry one; ring-placed enemies do too. */
  position?: [number, number, number];
  rotation?: number;
  authored?: boolean;
  destructible?: boolean;
}

interface Cell {
  pos: string;
  stage_id: string;
  rotation: number;
  connections: Record<string, string>;
  portals?: Record<string, string>;
  objects?: FieldObject[];
  is_start: boolean;
  is_end: boolean;
  is_branch: boolean;
  has_key: boolean;
  key_for_cell: string;
  is_key_gate: boolean;
  key_gate_direction: string;
  warp_edge: string;
  path_order: number;
  /**
   * Door attribute per direction, using the original game's own numbers
   * (see GridGenerator.ATTR_*): 1 one-key, 2 two-key, 4 enemy-defeat.
   *
   * AN OPEN DOOR IS OMITTED, not written as 0 — so "absent" means "walk
   * straight through", which is exactly the case that is easy to misread.
   *
   * Optional because transition and boss sections are single hand-built cells
   * that carry 15 keys rather than the 19 a grid cell has.
   */
  door_attributes?: Record<string, number>;
  /** The start room's way back to wherever the player warped in from. */
  entry_warp_edge?: string;
  /** Keys this room holds (cap 2), and how many its own gate demands. */
  key_count?: number;
  required_keys?: number;
}

/** Door attribute → label + colour. `undefined`/0 is an ungated doorway. */
const ATTR_OPEN = 0;
const ATTR_ONE_KEY = 1;
const ATTR_TWO_KEY = 2;
const ATTR_ENEMY_DEFEAT = 4;

const ATTR_INFO: Record<number, { label: string; color: string }> = {
  [ATTR_OPEN]: { label: 'open', color: '#6ec98a' },
  [ATTR_ONE_KEY]: { label: 'one-key', color: '#e0c97a' },
  [ATTR_TWO_KEY]: { label: 'two-key', color: '#e08a3c' },
  [ATTR_ENEMY_DEFEAT]: { label: 'enemy-defeat', color: '#ff6b6b' },
};

function attrOf(cell: Cell, dir: string): number {
  return cell.door_attributes?.[dir] ?? ATTR_OPEN;
}

/** Object-type counts for a cell, collapsed into the groups worth eyeballing. */
function contentCounts(cell: Cell) {
  const objects = cell.objects ?? [];
  const n = (...types: string[]) =>
    objects.filter((o) => types.includes(o.type)).length;
  return {
    enemies: n('enemy'),
    boxes: n('box', 'rare_box'),
    walls: n('wall'),
    fences: n('fence'),
    switches: n('step_switch'),
    traps: objects.filter((o) => o.type.endsWith('_trap')).length,
  };
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
  const c = contentCounts(cell);
  const bad = problems.length > 0;
  const doors = Object.keys(cell.connections)
    .map((d) => `${d}=${ATTR_INFO[attrOf(cell, d)]?.label ?? '?'}`)
    .join(', ');

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
        `doors: ${doors || 'none'}\n` +
        `portals: ${Object.keys(cell.portals ?? {}).join(', ') || 'none'}\n` +
        `${c.enemies} enemies, ${c.boxes} boxes, ${c.walls} walls, ` +
        `${c.traps} traps, ${c.fences} fences, ${c.switches} switches\n` +
        `keys held: ${cell.key_count ?? (cell.has_key ? 1 : 0)}` +
        (cell.required_keys ? `, gate demands ${cell.required_keys}` : '') +
        (cell.entry_warp_edge ? `\nway back: ${cell.entry_warp_edge}` : '') +
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
        {c.enemies > 0 && <span>{c.enemies}e </span>}
        {c.boxes > 0 && <span>{c.boxes}b </span>}
        {c.traps > 0 && <span style={{ color: '#e08a3c' }}>{c.traps}t </span>}
        {c.walls > 0 && <span>{c.walls}w</span>}
      </div>
      <div style={{ color: '#9aa' }}>
        {c.fences > 0 && <span style={{ color: '#88aaff' }}>{c.fences}f </span>}
        {c.switches > 0 && <span style={{ color: '#88aaff' }}>{c.switches}s</span>}
      </div>
      <div style={{ color: '#e0c97a' }}>
        {(cell.key_count ?? 0) > 1 ? `🔑×${cell.key_count}` : cell.has_key && '🔑'}
        {cell.is_key_gate && '🔒'}
        {cell.warp_edge && '➜'}
      </div>
    </div>
  );
}

/** Connections and their gates.
 *
 * TWO marks, deliberately separate, because the earlier version conflated them
 * and read as a contradiction: a connection was drawn as a coloured stub from
 * each side, so a door that is enemy-defeat one way and the way back the other
 * produced a red stub meeting a green one across the gap, as though the game
 * could not make its mind up.
 *
 * Now the gap between cells carries only a neutral CONNECTION line — present or
 * absent, which is what makes a one-way pair visible — and the gate is a bar
 * drawn INSIDE the cell's own edge, in its attribute colour, because a gate
 * belongs to the room that owns that doorway. Same idea as the quest editor's
 * layout grid, where a gate is a mark on the cell rather than on the link.
 */
function ConnectionStubs({ cell }: { cell: Cell }) {
  const edge = CELL_PX - 10;
  const mid = edge / 2;
  return (
    <>
      {Object.keys(cell.connections).map((dir) => {
        const d = dir as Dir;
        const horizontal = d === 'east' || d === 'west';
        const len = 12;

        // The link itself: neutral, so it says "connected" and nothing more.
        const link: React.CSSProperties = {
          position: 'absolute',
          background: '#4a5080',
          width: horizontal ? len : 2,
          height: horizontal ? 2 : len,
        };
        if (d === 'north') Object.assign(link, { left: mid, top: -len });
        if (d === 'south') Object.assign(link, { left: mid, top: edge });
        if (d === 'west') Object.assign(link, { left: -len, top: mid });
        if (d === 'east') Object.assign(link, { left: edge, top: mid });

        // The gate: on this cell's edge, in this cell's colour for this door.
        const attr = attrOf(cell, d);
        const gate: React.CSSProperties | null =
          attr === ATTR_OPEN
            ? null
            : {
                position: 'absolute',
                background: ATTR_INFO[attr].color,
                borderRadius: 1,
                width: horizontal ? 4 : 24,
                height: horizontal ? 24 : 4,
                // ABOVE the cell. ConnectionStubs renders before CellBox and
                // CellBox has an opaque background, so a bar inside the cell
                // footprint is painted over by it — which is why every gate
                // bar vanished while the links out in the gap survived.
                zIndex: 2,
              };
        if (gate) {
          if (d === 'north') Object.assign(gate, { left: mid - 11, top: 1 });
          if (d === 'south') Object.assign(gate, { left: mid - 11, top: edge - 4 });
          if (d === 'west') Object.assign(gate, { left: 1, top: mid - 11 });
          if (d === 'east') Object.assign(gate, { left: edge - 4, top: mid - 11 });
        }

        return (
          <div key={dir}>
            <div style={link} />
            {gate && <div style={gate} />}
          </div>
        );
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
        // App.tsx wraps every route in `overflow: hidden`, so a page taller than
        // the viewport is clipped rather than scrolled — sections b and z were
        // unreachable. Pages own their own scrolling here (the quest editor's
        // LayoutTab does the same), so this is the scroll container.
        height: '100%',
        overflowY: 'auto',
        boxSizing: 'border-box',
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

      {/* Door attributes, the thing this view exists to make readable. A thin
          stub is an ungated doorway you can walk straight through; a thick one
          has a gate standing in it. */}
      <div style={{ display: 'flex', gap: 12, fontSize: 11, color: '#8a90b8', marginBottom: 14, flexWrap: 'wrap' }}>
        <span>doors:</span>
        <span style={{ color: '#4a5080' }}>— connection</span>
        <span style={{ color: ATTR_INFO[ATTR_OPEN].color }}>(no bar) open</span>
        <span style={{ color: ATTR_INFO[ATTR_ONE_KEY].color }}>▬ one-key</span>
        <span style={{ color: ATTR_INFO[ATTR_TWO_KEY].color }}>▬ two-key</span>
        <span style={{ color: ATTR_INFO[ATTR_ENEMY_DEFEAT].color }}>▬ enemy-defeat</span>
        <span>· counts: e enemies, b boxes, t traps, w walls, f fences, s switches</span>
      </div>

      {roll.sections.map((section) => (
        <SectionGrid key={section.area} section={section} />
      ))}
    </div>
  );
}
