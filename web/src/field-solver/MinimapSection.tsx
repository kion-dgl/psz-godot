/**
 * MinimapSection — one generated section rendered the way the in-game AREA
 * MAP reads: every cell draws its stage's real minimap SVG footprint
 * (the same files the room minimap parses), fitted into a cell window with
 * door notches on the edges — not the abstract square grid of the
 * /field-generator page.
 *
 * Geometry mirrors area_map_overlay.gd: the FULL 0..400 SVG viewBox maps
 * onto the window (so room sizes stay comparable and door notches land on
 * the edges their rooms actually open), windows sit on a stride so the
 * notches of adjacent rooms meet across the gap, and warp edges draw as
 * longer, thicker bars that read as "leads out of the grid".
 */

import { useEffect, useMemo, useState } from 'react';
import { getStageSubfolder } from '../stage-editor/constants';
import { assetUrl } from '../utils/assets';
import {
  attrOf,
  keysHeldBy,
  enemyCount,
  ATTR_OPEN,
  ATTR_ONE_KEY,
  ATTR_TWO_KEY,
  ATTR_ENEMY_DEFEAT,
  type Cell,
  type Section,
} from './solver';

const ATTR_INFO: Record<number, { label: string; color: string }> = {
  [ATTR_OPEN]: { label: 'open', color: '#6ec98a' },
  [ATTR_ONE_KEY]: { label: 'one-key', color: '#e0c97a' },
  [ATTR_TWO_KEY]: { label: 'two-key', color: '#e08a3c' },
  [ATTR_ENEMY_DEFEAT]: { label: 'enemy-defeat', color: '#ff6b6b' },
};

const WARP_COLOR = '#4a9eff';
const RETURN_WARP_COLOR = '#4af0ff';
const PAD = 18;

function parsePos(pos: string): [number, number] {
  const [r, c] = pos.split(',').map((n) => parseInt(n, 10));
  return [r, c];
}

// ── Minimap SVG loading ─────────────────────────────────────────────────────
//
// The footprints render as <image> elements, NOT inlined SVG text. Two
// reasons, both load-bearing:
//
//  - prod serves /assets/* from the R2 CDN (static.yml sets VITE_ASSETS_BASE),
//    and the bucket sends no CORS headers — fetch() of the text is blocked
//    from the page's origin, while <image>/<img> display is not. Every room
//    silently fell back to the placeholder before this switched over.
//  - the pre-rotated variants (_minimap_r{90,180,270}.svg) mean rotation is
//    just a URL pick; no transform juggling of embedded markup.
//
// A cheap Image() probe per stage+rotation decides footprint vs the dashed
// placeholder (the s01z boss arena ships no SVG).

const probeCache = new Map<string, Promise<boolean>>();

function probeUrl(url: string): Promise<boolean> {
  if (!probeCache.has(url)) {
    probeCache.set(
      url,
      new Promise<boolean>((resolve) => {
        const img = new Image();
        img.onload = () => resolve(true);
        img.onerror = () => resolve(false);
        img.src = url;
      }),
    );
  }
  return probeCache.get(url) as Promise<boolean>;
}

function minimapUrls(stageId: string, areaFolder: string, rotation: number) {
  const sub = getStageSubfolder(stageId, areaFolder);
  const base = `assets/stages/${sub}/${stageId}/lndmd/${stageId}_minimap`;
  return {
    rotated: rotation !== 0 ? assetUrl(`${base}_r${rotation}.svg`) : null,
    plain: assetUrl(`${base}.svg`),
  };
}

function RoomShape({
  stageId,
  areaFolder,
  rotation,
  x,
  y,
  win,
}: {
  stageId: string;
  areaFolder: string;
  rotation: number;
  x: number;
  y: number;
  win: number;
}) {
  const [img, setImg] = useState<{ url: string; deg: number } | null>(null);
  useEffect(() => {
    let cancelled = false;
    setImg(null);
    const { rotated, plain } = minimapUrls(stageId, areaFolder, rotation);
    (rotated ? probeUrl(rotated).then((ok) => (ok ? rotated : null)) : Promise.resolve(null))
      .then((r) =>
        r ? r : probeUrl(plain).then((ok) => (ok ? plain : null)),
      )
      .then((u) => {
        if (!cancelled && u) setImg({ url: u, deg: u === plain ? rotation : 0 });
      });
    return () => {
      cancelled = true;
    };
  }, [stageId, areaFolder, rotation]);

  if (!img) {
    // Still loading, or no footprint (the s01z boss arena has none) — the
    // game's plain-square fallback, so the room still reads as a room.
    return (
      <rect
        x={x + win * 0.1}
        y={y + win * 0.1}
        width={win * 0.8}
        height={win * 0.8}
        rx={6}
        fill="#242438"
        stroke="#3a3a5a"
        strokeDasharray="4 3"
      />
    );
  }
  const image = (
    <image
      href={img.url}
      x={x}
      y={y}
      width={win}
      height={win}
      opacity={0.92}
      preserveAspectRatio="xMidYMid meet"
    />
  );
  // Base SVG only (no pre-rotated variant): rotate it in place.
  return img.deg !== 0 ? (
    <g transform={`rotate(${img.deg} ${x + win / 2} ${y + win / 2})`}>{image}</g>
  ) : (
    image
  );
}

// ── The composed section map ────────────────────────────────────────────────

export interface MinimapSectionProps {
  section: Section;
  areaFolder: string;
  windowPx?: number;
  selectedPos?: string | null;
  highlightPos?: string | null;
  visited?: Set<string>;
  routeEdge?: { from: string; to: string } | null;
  onCellClick?: (pos: string) => void;
}

export default function MinimapSection({
  section,
  areaFolder,
  windowPx = 112,
  selectedPos,
  highlightPos,
  visited,
  routeEdge,
  onCellClick,
}: MinimapSectionProps) {
  const stride = windowPx + 12;
  const notchLen = windowPx * 0.32;
  const notchThick = windowPx * 0.09;
  const warpLen = windowPx * 0.42;
  const warpThick = windowPx * 0.13;

  const { width, height, minRow, minCol } = useMemo(() => {
    const coords = section.cells.map((c) => parsePos(c.pos));
    const rows = coords.map(([r]) => r);
    const cols = coords.map(([, c]) => c);
    const minRow = Math.min(...rows);
    const minCol = Math.min(...cols);
    const maxRow = Math.max(...rows);
    const maxCol = Math.max(...cols);
    return {
      minRow,
      minCol,
      width: (maxCol - minCol + 1) * stride + PAD * 2,
      height: (maxRow - minRow + 1) * stride + PAD * 2,
    };
  }, [section, stride]);

  const cellOrigin = (pos: string): [number, number] => {
    const [r, c] = parsePos(pos);
    return [PAD + (c - minCol) * stride, PAD + (r - minRow) * stride];
  };

  const byPosMap = useMemo(
    () => new Map(section.cells.map((c) => [c.pos, c])),
    [section],
  );

  /** Door / warp notch centered on one edge of a cell window. */
  const notch = (
    pos: string,
    dir: string,
    color: string,
    isWarp: boolean,
    key: string,
  ) => {
    const [x, y] = cellOrigin(pos);
    const cx = x + windowPx / 2;
    const cy = y + windowPx / 2;
    const length = isWarp ? warpLen : notchLen;
    const thick = isWarp ? warpThick : notchThick;
    let rx = cx - length / 2;
    let ry = cy - thick / 2;
    let w = length;
    let h = thick;
    if (dir === 'north') ry = y - thick / 2;
    if (dir === 'south') ry = y + windowPx - thick / 2;
    if (dir === 'west') {
      rx = x - thick / 2;
      ry = cy - length / 2;
      w = thick;
      h = length;
    }
    if (dir === 'east') {
      rx = x + windowPx - thick / 2;
      ry = cy - length / 2;
      w = thick;
      h = length;
    }
    return (
      <rect
        key={key}
        x={rx}
        y={ry}
        width={w}
        height={h}
        rx={1.5}
        fill={color}
        opacity={isWarp ? 1 : 0.9}
      />
    );
  };

  return (
    <div
      style={{
        background: '#15152a',
        border: '1px solid #2a2a45',
        borderRadius: 8,
        width: 'fit-content',
        padding: 0,
      }}
    >
      <svg width={width} height={height}>
        {/* Route trail: the solver's current crossing, drawn under the marks. */}
        {routeEdge &&
          (() => {
            const a = byPosMap.get(routeEdge.from);
            if (!a) return null;
            const dir = Object.entries(a.connections).find(
              ([, t]) => t === routeEdge.to,
            )?.[0];
            if (!dir) return null;
            const [x1, y1] = cellOrigin(routeEdge.from);
            const [x2, y2] = cellOrigin(routeEdge.to);
            return (
              <line
                x1={x1 + windowPx / 2}
                y1={y1 + windowPx / 2}
                x2={x2 + windowPx / 2}
                y2={y2 + windowPx / 2}
                stroke="#00e5ff"
                strokeWidth={3}
                strokeLinecap="round"
                opacity={0.85}
              />
            );
          })()}

        {section.cells.map((cell) => {
          const [x, y] = cellOrigin(cell.pos);
          const isSel = selectedPos === cell.pos;
          const isHi = highlightPos === cell.pos;
          const isVisited = visited?.has(cell.pos) ?? false;
          const keys = keysHeldBy(cell);
          const enemies = enemyCount(cell);
          return (
            <g key={cell.pos}>
              <RoomShape
                stageId={cell.stage_id}
                areaFolder={areaFolder}
                rotation={cell.rotation}
                x={x}
                y={y}
                win={windowPx}
              />

              {/* Visited tint + selection rings, over the footprint. */}
              {isVisited && (
                <rect
                  x={x}
                  y={y}
                  width={windowPx}
                  height={windowPx}
                  fill="rgba(80,140,255,0.16)"
                />
              )}
              {(isSel || isHi) && (
                <rect
                  x={x - 2}
                  y={y - 2}
                  width={windowPx + 4}
                  height={windowPx + 4}
                  fill="none"
                  stroke={isHi ? '#00e5ff' : '#fff'}
                  strokeWidth={2}
                  rx={6}
                />
              )}

              {/* Door notches per connection, in the attribute's colour. */}
              {Object.keys(cell.connections).map((dir) =>
                notch(
                  cell.pos,
                  dir,
                  ATTR_INFO[attrOf(cell, dir)]?.color ?? '#888',
                  false,
                  `${cell.pos}-${dir}`,
                ),
              )}
              {/* The section's warp out, and the start's way back in. */}
              {cell.warp_edge &&
                notch(cell.pos, cell.warp_edge, WARP_COLOR, true, `${cell.pos}-warp`)}
              {cell.entry_warp_edge &&
                notch(
                  cell.pos,
                  cell.entry_warp_edge,
                  RETURN_WARP_COLOR,
                  true,
                  `${cell.pos}-return`,
                )}

              {/* Badges: start / end / keys / gate demand / stage code. */}
              <text
                x={x + 4}
                y={y + 11}
                fill="#cfd4ff"
                fontSize={9}
                fontFamily="monospace"
              >
                {cell.stage_id.split('_')[1] ?? cell.stage_id}
              </text>
              {cell.is_start && (
                <text x={x + windowPx - 10} y={y + 13} fill="#6ec98a" fontSize={11} fontWeight="bold">
                  S
                </text>
              )}
              {cell.is_end && (
                <text x={x + windowPx - 10} y={y + 13} fill="#e0a05a" fontSize={11} fontWeight="bold">
                  E
                </text>
              )}
              {enemies > 0 && (
                <text
                  x={x + windowPx - 10}
                  y={y + windowPx - 5}
                  fill="#ff9a9a"
                  fontSize={9}
                  textAnchor="end"
                  fontFamily="monospace"
                >
                  {enemies}e
                </text>
              )}
              {keys > 0 && (
                <g>
                  <text
                    x={x + windowPx / 2}
                    y={y + windowPx - 6}
                    fill="#e0c97a"
                    fontSize={11}
                    textAnchor="middle"
                  >
                    {'🔑'.repeat(Math.min(keys, 2))}
                  </text>
                </g>
              )}
              {cell.is_key_gate && (cell.required_keys ?? 0) > 0 && (
                <text
                  x={x + windowPx / 2}
                  y={y + 16}
                  fill="#e08a3c"
                  fontSize={9}
                  textAnchor="middle"
                  fontFamily="monospace"
                >
                  🔒{cell.required_keys}
                </text>
              )}

              {onCellClick && (
                <rect
                  x={x}
                  y={y}
                  width={windowPx}
                  height={windowPx}
                  fill="transparent"
                  style={{ cursor: 'pointer' }}
                  onClick={() => onCellClick(cell.pos)}
                />
              )}
            </g>
          );
        })}
      </svg>
    </div>
  );
}

export { ATTR_INFO };
