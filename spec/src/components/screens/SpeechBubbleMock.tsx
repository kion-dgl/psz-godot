import React, { useMemo, useRef, useState } from 'react';

type AspectId = '16:9' | '4:3' | '21:9';
type BackdropId = 'snowfield' | 'valley' | 'ruins' | 'office';
type PresetId =
  | 'center'
  | 'left-edge'
  | 'right-edge'
  | 'top-hud'
  | 'palette-corner'
  | 'behind-camera'
  | 'two-npcs';

interface Rect {
  x: number;
  y: number;
  w: number;
  h: number;
}

interface SpeakerInput {
  id: string;
  speaker: string;
  text: string;
  /** Normalized viewport anchor X (0..1, can go outside -0.15..1.15 to simulate off-screen). */
  nx: number;
  /** Normalized viewport anchor Y (0..1). */
  ny: number;
  behindCamera?: boolean;
}

interface PlacementResult {
  box: Rect;
  total: Rect;
  anchorPx: { x: number; y: number };
  tailBaseX: number;
  tailTip: { x: number; y: number };
  clampedEdge: boolean;
  nudgedHud: boolean;
  nudgedOverlap: boolean;
  behindCamera: boolean;
}

const ASPECT_SIZES: Record<AspectId, { w: number; h: number; label: string }> = {
  '16:9': { w: 1280, h: 720, label: '16:9 (1280×720)' },
  '4:3': { w: 1280, h: 960, label: '4:3 (1280×960)' },
  '21:9': { w: 1680, h: 720, label: '21:9 (1680×720)' },
};

const SAFE_MARGIN_X = 24;
const SAFE_MARGIN_TOP = 20;
const SAFE_MARGIN_BOTTOM = 28;
const MIN_WIDTH = 140;
const MAX_WIDTH = 360;
const PAD_X = 15;
const PAD_Y = 10;
const CORNER_RADIUS = 10;
const TAIL_HALF_W = 8;
const TAIL_H = 11;
const OVERLAP_GAP = 8;
const HUD_GAP = 8;

const BACKDROPS: Record<BackdropId, { label: string; css: string; inCity: boolean }> = {
  snowfield: {
    label: 'Rioh Snowfield (bright glare)',
    css: 'linear-gradient(180deg, #dbe9f6 0%, #eef5fc 46%, #cddff0 100%)',
    inCity: false,
  },
  valley: {
    label: 'Gurhacia Valley (warm sand)',
    css: 'linear-gradient(180deg, #8ec0e4 0%, #d8b589 52%, #a67c52 100%)',
    inCity: false,
  },
  ruins: {
    label: 'Makara Ruins (dark stone)',
    css: 'linear-gradient(180deg, #16202c 0%, #243444 55%, #121a24 100%)',
    inCity: false,
  },
  office: {
    label: "Principal's Office (city)",
    css: 'linear-gradient(180deg, #2b3f5c 0%, #4b382a 55%, #2c2119 100%)',
    inCity: true,
  },
};

const PRESETS: Record<PresetId, { label: string; backdrop: BackdropId; speakers: SpeakerInput[] }> = {
  center: {
    label: 'Centered speaker',
    backdrop: 'valley',
    speakers: [
      {
        id: 'kai',
        speaker: 'Kai',
        text: "Hold up — there's a message log half-buried near those rocks.",
        nx: 0.5,
        ny: 0.56,
      },
    ],
  },
  'left-edge': {
    label: 'Left viewport edge',
    backdrop: 'snowfield',
    speakers: [
      {
        id: 'sarisa',
        speaker: 'Sarisa',
        text: 'Watch the snowbank on our flank! Hostiles moving in.',
        nx: 0.04,
        ny: 0.54,
      },
    ],
  },
  'right-edge': {
    label: 'Right off-frame speaker',
    backdrop: 'valley',
    speakers: [
      {
        id: 'kai',
        speaker: 'Kai',
        text: 'Gate switch is over this way — follow me!',
        nx: 1.05,
        ny: 0.5,
      },
    ],
  },
  'top-hud': {
    label: 'Top-left HUD collision',
    backdrop: 'snowfield',
    speakers: [
      {
        id: 'elio',
        speaker: 'Elio',
        text: 'Signal reading spikes right under the upper ridge.',
        nx: 0.11,
        ny: 0.18,
      },
    ],
  },
  'palette-corner': {
    label: 'Action Palette collision',
    backdrop: 'ruins',
    speakers: [
      {
        id: 'kai',
        speaker: 'Kai',
        text: 'Careful, needle traps cycle every few seconds in this hall.',
        nx: 0.88,
        ny: 0.81,
      },
    ],
  },
  'behind-camera': {
    label: 'Companion behind camera',
    backdrop: 'ruins',
    speakers: [
      {
        id: 'sarisa',
        speaker: 'Sarisa',
        text: "Wait up! I found the second keycard back by the fountain!",
        nx: 0.34,
        ny: 0.95,
        behindCamera: true,
      },
    ],
  },
  'two-npcs': {
    label: 'Two nearby speakers (de-overlap)',
    backdrop: 'office',
    speakers: [
      {
        id: 'principal',
        speaker: 'Principal',
        text: 'Your job is simple — investigate the valley outpost and report back.',
        nx: 0.5,
        ny: 0.44,
      },
      {
        id: 'kai',
        speaker: 'Kai',
        text: "Don't worry, rookie. Stick close and we'll clear it fast.",
        nx: 0.44,
        ny: 0.5,
      },
    ],
  },
};

function hudExclusionRects(vw: number, vh: number, inCity: boolean): { label: string; rect: Rect }[] {
  const zones: { label: string; rect: Rect }[] = [
    { label: 'HudStats (HP / PP / EXP)', rect: { x: 0, y: 0, w: 224, h: 128 } },
  ];
  if (inCity) {
    zones.push({ label: 'FPS', rect: { x: vw - 96, y: 0, w: 96, h: 34 } });
  } else {
    zones.push({ label: 'RoomMinimap + FPS', rect: { x: vw - 172, y: 0, w: 172, h: 164 } });
    zones.push({ label: 'ActionPalette', rect: { x: vw - 276, y: vh - 152, w: 276, h: 152 } });
    zones.push({ label: 'TargetInfo / QuickWeapon', rect: { x: 0, y: vh - 116, w: 280, h: 116 } });
  }
  return zones;
}

function rectsIntersect(a: Rect, b: Rect): boolean {
  return a.x < b.x + b.w && a.x + a.w > b.x && a.y < b.y + b.h && a.y + a.h > b.y;
}

function measureBubble(speaker: string, text: string): { w: number; h: number; lines: string[] } {
  const charW = 9.0; // 15px JetBrains Mono ≈ 9px advance
  const maxInnerW = MAX_WIDTH - PAD_X * 2;
  const maxCharsPerLine = Math.max(12, Math.floor(maxInnerW / charW));
  const words = text.trim().split(/\s+/).filter(Boolean);
  const lines: string[] = [];
  let current = '';
  for (const word of words) {
    const candidate = current ? `${current} ${word}` : word;
    if (candidate.length <= maxCharsPerLine || !current) {
      current = candidate;
    } else {
      lines.push(current);
      current = word;
    }
  }
  if (current) lines.push(current);
  if (lines.length === 0) lines.push('');

  const longestLinePx = Math.max(...lines.map((l) => l.length * charW));
  const speakerPx = speaker ? speaker.length * 7.6 + 8 : 0;
  const contentW = Math.max(longestLinePx, speakerPx);
  const w = Math.max(MIN_WIDTH, Math.min(MAX_WIDTH, Math.ceil(contentW + PAD_X * 2)));
  const speakerH = speaker ? 18 : 0;
  const bodyH = lines.length * 21;
  const h = PAD_Y * 2 + speakerH + bodyH;
  return { w, h, lines };
}

function computePlacement(
  vw: number,
  vh: number,
  size: { w: number; h: number },
  rawAnchor: { x: number; y: number },
  behindCamera: boolean,
  hudRects: Rect[],
  occupiedRects: Rect[],
): PlacementResult {
  const { w, h } = size;
  const totalH = h + TAIL_H;
  const leftBound = SAFE_MARGIN_X;
  const rightBound = Math.max(leftBound, vw - SAFE_MARGIN_X - w);
  const topBound = SAFE_MARGIN_TOP;
  const bottomBound = Math.max(topBound, vh - SAFE_MARGIN_BOTTOM - totalH);

  const anchorPx = behindCamera
    ? {
        x: Math.max(vw * 0.12, Math.min(vw * 0.88, rawAnchor.x)),
        y: vh - SAFE_MARGIN_BOTTOM,
      }
    : rawAnchor;

  const idealX = anchorPx.x - w * 0.5;
  const idealY = anchorPx.y - totalH;

  let bx = Math.max(leftBound, Math.min(rightBound, idealX));
  let by = Math.max(topBound, Math.min(bottomBound, idealY));
  const clampedEdge = Math.abs(bx - idealX) > 0.5 || Math.abs(by - idealY) > 0.5;

  let nudgedHud = false;
  for (const hud of hudRects) {
    const cur: Rect = { x: bx, y: by, w, h: totalH };
    if (!rectsIntersect(cur, hud)) continue;
    const candidates: { x: number; y: number }[] = [
      { x: bx, y: hud.y + hud.h + HUD_GAP },
      { x: bx, y: hud.y - totalH - HUD_GAP },
      { x: hud.x + hud.w + HUD_GAP, y: by },
      { x: hud.x - w - HUD_GAP, y: by },
    ].filter(
      (c) =>
        c.x >= leftBound - 0.5 &&
        c.x <= rightBound + 0.5 &&
        c.y >= topBound - 0.5 &&
        c.y <= bottomBound + 0.5 &&
        !hudRects.some((hz) => rectsIntersect({ x: c.x, y: c.y, w, h: totalH }, hz)),
    );
    if (candidates.length > 0) {
      candidates.sort(
        (a, b) => Math.hypot(a.x - bx, a.y - by) - Math.hypot(b.x - bx, b.y - by),
      );
      bx = Math.max(leftBound, Math.min(rightBound, candidates[0].x));
      by = Math.max(topBound, Math.min(bottomBound, candidates[0].y));
      nudgedHud = true;
    }
  }

  let nudgedOverlap = false;
  for (const occ of occupiedRects) {
    const cur: Rect = { x: bx, y: by, w, h: totalH };
    if (!rectsIntersect(cur, occ)) continue;
    const upY = occ.y - totalH - OVERLAP_GAP;
    const downY = occ.y + occ.h + OVERLAP_GAP;
    if (upY >= topBound) {
      by = upY;
    } else if (downY <= bottomBound) {
      by = downY;
    }
    nudgedOverlap = true;
  }

  const minTailX = bx + CORNER_RADIUS + TAIL_HALF_W + 4;
  const maxTailX = bx + w - CORNER_RADIUS - TAIL_HALF_W - 4;
  const tailBaseX = Math.max(minTailX, Math.min(maxTailX, anchorPx.x));
  const tailTipX = Math.max(bx + CORNER_RADIUS + 2, Math.min(bx + w - CORNER_RADIUS - 2, anchorPx.x));

  return {
    box: { x: bx, y: by, w, h },
    total: { x: bx, y: by, w, h: totalH },
    anchorPx,
    tailBaseX,
    tailTip: { x: tailTipX, y: by + h + TAIL_H },
    clampedEdge,
    nudgedHud,
    nudgedOverlap,
    behindCamera,
  };
}

function bubblePolygonPath(box: Rect, tailBaseX: number, tailTip: { x: number; y: number }): string {
  const { x, y, w, h } = box;
  const r = CORNER_RADIUS;
  const tl = Math.max(x + r + 2, tailBaseX - TAIL_HALF_W);
  const tr = Math.min(x + w - r - 2, tailBaseX + TAIL_HALF_W);
  return [
    `M ${x + r} ${y}`,
    `L ${x + w - r} ${y}`,
    `Q ${x + w} ${y} ${x + w} ${y + r}`,
    `L ${x + w} ${y + h - r}`,
    `Q ${x + w} ${y + h} ${x + w - r} ${y + h}`,
    `L ${tr} ${y + h}`,
    `L ${tailTip.x} ${tailTip.y}`,
    `L ${tl} ${y + h}`,
    `L ${x + r} ${y + h}`,
    `Q ${x} ${y + h} ${x} ${y + h - r}`,
    `L ${x} ${y + r}`,
    `Q ${x} ${y} ${x + r} ${y}`,
    'Z',
  ].join(' ');
}

export default function SpeechBubbleMock() {
  const [aspect, setAspect] = useState<AspectId>('16:9');
  const [preset, setPreset] = useState<PresetId>('center');
  const [backdrop, setBackdrop] = useState<BackdropId>('valley');
  const [speakers, setSpeakers] = useState<SpeakerInput[]>(PRESETS.center.speakers);
  const [draggingId, setDraggingId] = useState<string | null>(null);
  const svgRef = useRef<SVGSVGElement | null>(null);

  const vp = ASPECT_SIZES[aspect];
  const bg = BACKDROPS[backdrop];
  const hudZones = useMemo(() => hudExclusionRects(vp.w, vp.h, bg.inCity), [vp.w, vp.h, bg.inCity]);

  const applyPreset = (id: PresetId) => {
    setPreset(id);
    setBackdrop(PRESETS[id].backdrop);
    setSpeakers(PRESETS[id].speakers.map((s) => ({ ...s })));
  };

  const placements = useMemo(() => {
    const ordered = [...speakers].sort((a, b) => b.ny - a.ny);
    const occupied: Rect[] = [];
    const out = new Map<string, { measured: ReturnType<typeof measureBubble>; placement: PlacementResult }>();
    for (const sp of ordered) {
      const measured = measureBubble(sp.speaker, sp.text);
      const rawAnchor = { x: sp.nx * vp.w, y: sp.ny * vp.h };
      const placement = computePlacement(
        vp.w,
        vp.h,
        measured,
        rawAnchor,
        Boolean(sp.behindCamera),
        hudZones.map((z) => z.rect),
        occupied,
      );
      occupied.push(placement.total);
      out.set(sp.id, { measured, placement });
    }
    return out;
  }, [speakers, vp.w, vp.h, hudZones]);

  const onPointerMove = (e: React.PointerEvent<SVGSVGElement>) => {
    if (!draggingId || !svgRef.current) return;
    const rect = svgRef.current.getBoundingClientRect();
    const nx = Math.max(-0.08, Math.min(1.08, (e.clientX - rect.left) / rect.width));
    const ny = Math.max(0.02, Math.min(0.98, (e.clientY - rect.top) / rect.height));
    setSpeakers((prev) =>
      prev.map((s) => (s.id === draggingId ? { ...s, nx, ny } : s)),
    );
  };

  const primary = speakers[0];
  const primaryPlacement = primary ? placements.get(primary.id)?.placement : undefined;

  return (
    <div style={{ margin: '1.25rem 0', fontFamily: 'system-ui, sans-serif' }}>
      <div
        style={{
          display: 'flex',
          flexWrap: 'wrap',
          gap: '0.5rem',
          alignItems: 'center',
          marginBottom: '0.75rem',
        }}
      >
        <strong style={{ fontSize: 13 }}>Scenario:</strong>
        {(Object.keys(PRESETS) as PresetId[]).map((id) => (
          <button
            key={id}
            type="button"
            onClick={() => applyPreset(id)}
            style={{
              padding: '4px 10px',
              borderRadius: 6,
              border: preset === id ? '2px solid #f0a020' : '1px solid #4a627a',
              background: preset === id ? '#f0a020' : '#1b2838',
              color: preset === id ? '#141820' : '#e6eef8',
              fontSize: 12,
              fontWeight: preset === id ? 700 : 500,
              cursor: 'pointer',
            }}
          >
            {PRESETS[id].label}
          </button>
        ))}
      </div>

      <div
        style={{
          display: 'flex',
          flexWrap: 'wrap',
          gap: '1rem',
          alignItems: 'center',
          marginBottom: '0.75rem',
          fontSize: 13,
        }}
      >
        <label>
          <strong>Aspect: </strong>
          <select
            value={aspect}
            onChange={(e) => setAspect(e.target.value as AspectId)}
            style={{ padding: '3px 8px', borderRadius: 4 }}
          >
            {(Object.keys(ASPECT_SIZES) as AspectId[]).map((k) => (
              <option key={k} value={k}>
                {ASPECT_SIZES[k].label}
              </option>
            ))}
          </select>
        </label>

        <label>
          <strong>Backdrop: </strong>
          <select
            value={backdrop}
            onChange={(e) => setBackdrop(e.target.value as BackdropId)}
            style={{ padding: '3px 8px', borderRadius: 4 }}
          >
            {(Object.keys(BACKDROPS) as BackdropId[]).map((k) => (
              <option key={k} value={k}>
                {BACKDROPS[k].label}
              </option>
            ))}
          </select>
        </label>

        {primary && (
          <label style={{ display: 'inline-flex', alignItems: 'center', gap: 6 }}>
            <input
              type="checkbox"
              checked={Boolean(primary.behindCamera)}
              onChange={(e) =>
                setSpeakers((prev) =>
                  prev.map((s, i) => (i === 0 ? { ...s, behindCamera: e.target.checked } : s)),
                )
              }
            />
            Speaker behind camera
          </label>
        )}
        <span style={{ opacity: 0.75, fontSize: 12 }}>
          Drag the orange head-anchor pin to test clamping &amp; HUD avoidance live.
        </span>
      </div>

      <div
        style={{
          width: '100%',
          maxWidth: 860,
          borderRadius: 10,
          overflow: 'hidden',
          border: '2px solid #354b63',
          boxShadow: '0 6px 20px rgba(0,0,0,0.3)',
          background: bg.css,
        }}
      >
        <svg
          ref={svgRef}
          viewBox={`0 0 ${vp.w} ${vp.h}`}
          style={{ width: '100%', height: 'auto', display: 'block', userSelect: 'none', touchAction: 'none' }}
          onPointerMove={onPointerMove}
          onPointerUp={() => setDraggingId(null)}
          onPointerLeave={() => setDraggingId(null)}
        >
          {/* Layer 0 — 3D Scene: NPC silhouettes (behind SpeechBubble layer 40 and HUD layer 200) */}
          {speakers.map((sp) => {
            if (sp.behindCamera) return null;
            const ax = sp.nx * vp.w;
            const ay = sp.ny * vp.h;
            return (
              <g key={`npc-${sp.id}`} opacity={0.9} style={{ pointerEvents: 'none' }}>
                <rect
                  x={ax - 22}
                  y={ay + 12}
                  width={44}
                  height={108}
                  rx={20}
                  fill="#2b4c70"
                  stroke="#dcebff"
                  strokeWidth={2}
                />
                <circle cx={ax} cy={ay + 30} r={15} fill="#5082b4" />
              </g>
            );
          })}

          {/* Safe-frame guide */}
          <rect
            x={SAFE_MARGIN_X}
            y={SAFE_MARGIN_TOP}
            width={vp.w - SAFE_MARGIN_X * 2}
            height={vp.h - SAFE_MARGIN_TOP - SAFE_MARGIN_BOTTOM}
            fill="none"
            stroke="rgba(255,255,255,0.28)"
            strokeDasharray="6 6"
            strokeWidth={1.5}
            style={{ pointerEvents: 'none' }}
          />

          {/* Layer 40 — SpeechBubble CanvasLayer (above 3D scene, below HUD layer 200) */}
          {speakers.map((sp) => {
            const item = placements.get(sp.id);
            if (!item) return null;
            const { measured, placement } = item;
            const d = bubblePolygonPath(placement.box, placement.tailBaseX, placement.tailTip);
            const shadowD = bubblePolygonPath(
              { ...placement.box, y: placement.box.y + 3 },
              placement.tailBaseX,
              { x: placement.tailTip.x, y: placement.tailTip.y + 3 },
            );
            return (
              <g key={`bubble-${sp.id}`} style={{ pointerEvents: 'none' }}>
                <path d={shadowD} fill="rgba(0, 10, 26, 0.36)" />
                <path
                  d={d}
                  fill="rgba(250, 252, 255, 0.96)"
                  stroke="rgba(56, 82, 117, 0.95)"
                  strokeWidth={2.2}
                  strokeLinejoin="round"
                />
                {sp.speaker && (
                  <text
                    x={placement.box.x + PAD_X}
                    y={placement.box.y + PAD_Y + 11}
                    fill="#335c9e"
                    fontSize={12}
                    fontWeight={700}
                    fontFamily="'JetBrains Mono', monospace"
                  >
                    {sp.speaker}
                  </text>
                )}
                {measured.lines.map((line, idx) => (
                  <text
                    key={idx}
                    x={placement.box.x + PAD_X}
                    y={placement.box.y + PAD_Y + (sp.speaker ? 18 : 0) + 15 + idx * 21}
                    fill="#1a1a2b"
                    fontSize={15}
                    fontFamily="'JetBrains Mono', monospace"
                  >
                    {line}
                  </text>
                ))}
              </g>
            );
          })}

          {/* Layer 200 — FieldHud / HudStats CanvasLayer (in front of 3D scene & speech bubbles) */}
          {hudZones.map((z) => (
            <g key={z.label} style={{ pointerEvents: 'none' }}>
              <rect
                x={z.rect.x + 8}
                y={z.rect.y + 8}
                width={z.rect.w - 16}
                height={z.rect.h - 16}
                rx={8}
                fill="#0e182a"
                stroke="rgba(120, 175, 230, 0.9)"
                strokeWidth={2}
              />
              <text
                x={z.rect.x + z.rect.w / 2}
                y={z.rect.y + z.rect.h / 2 + 4}
                textAnchor="middle"
                fill="#cde2f8"
                fontSize={13}
                fontFamily="'JetBrains Mono', monospace"
              >
                {z.label}
              </text>
            </g>
          ))}

          {/* Interactive gizmo: draggable head-anchor handle (dashed ghost when behind HUD) */}
          {speakers.map((sp) => {
            const ax = sp.nx * vp.w;
            const ay = sp.ny * vp.h;
            const occludedByHud = hudZones.some(
              (z) =>
                ax >= z.rect.x + 8 &&
                ax <= z.rect.x + z.rect.w - 8 &&
                ay >= z.rect.y + 8 &&
                ay <= z.rect.y + z.rect.h - 8,
            );
            return (
              <g
                key={`pin-${sp.id}`}
                style={{ cursor: 'grab' }}
                onPointerDown={(e) => {
                  e.currentTarget.setPointerCapture(e.pointerId);
                  setDraggingId(sp.id);
                }}
              >
                <circle
                  cx={ax}
                  cy={ay}
                  r={11}
                  fill={occludedByHud ? 'rgba(240, 160, 32, 0.18)' : '#f0a020'}
                  stroke={occludedByHud ? 'rgba(240, 160, 32, 0.75)' : '#101824'}
                  strokeDasharray={occludedByHud ? '3 3' : undefined}
                  strokeWidth={2.5}
                />
                {!occludedByHud && <circle cx={ax} cy={ay} r={3.5} fill="#101824" />}
              </g>
            );
          })}
        </svg>
      </div>

      {primaryPlacement && (
        <div
          style={{
            marginTop: '0.6rem',
            fontSize: 12,
            fontFamily: "'JetBrains Mono', monospace",
            display: 'flex',
            flexWrap: 'wrap',
            gap: '0.9rem',
            opacity: 0.9,
          }}
        >
          <span>
            box=({Math.round(primaryPlacement.box.x)}, {Math.round(primaryPlacement.box.y)},{' '}
            {Math.round(primaryPlacement.box.w)}×{Math.round(primaryPlacement.box.h)})
          </span>
          <span>tailTipX={Math.round(primaryPlacement.tailTip.x)}</span>
          <span>edgeClamped={String(primaryPlacement.clampedEdge)}</span>
          <span>hudNudged={String(primaryPlacement.nudgedHud)}</span>
          <span>overlapNudged={String(primaryPlacement.nudgedOverlap)}</span>
          <span>behindCamera={String(primaryPlacement.behindCamera)}</span>
        </div>
      )}
    </div>
  );
}
