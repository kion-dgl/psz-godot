import React, { useMemo, useRef, useState } from 'react';

type AspectId = '16:9' | '4:3' | '21:9';
type BackdropId = 'forest' | 'pioneer' | 'snowfield' | 'ruins' | 'office';
type ShapeStyleId = 'squared-slant' | 'chamfer-slant' | 'sharp-box' | 'classic-pso';
type PresetId =
  | 'pso-field'
  | 'pso-angled'
  | 'cast-cyan'
  | 'offscreen-dir'
  | 'behind-camera'
  | 'palette-corner'
  | 'two-npcs';

interface Rect {
  x: number;
  y: number;
  w: number;
  h: number;
}

interface Pt {
  x: number;
  y: number;
}

interface SpeakerInput {
  id: string;
  speaker: string;
  text: string;
  nx: number;
  ny: number;
  behindCamera?: boolean;
}

interface ShapeTuning {
  cornerRadius: number;
  slantRatio: number;
  maxWidth: number;
  padX: number;
  padY: number;
  chamfer: boolean;
}

interface PlacementResult {
  box: Rect;
  anchorPx: Pt;
  tailBase: Pt;
  tailTip: Pt;
  tailAngleDeg: number;
  clampedEdge: boolean;
  nudgedHud: boolean;
  nudgedOverlap: boolean;
  behindCamera: boolean;
  offscreen: boolean;
}

export const SPEAKER_PALETTE: { key: string; label: string; fill: string; role: string }[] = [
  { key: 'default', label: 'Default / Town NPC', fill: '#FFFFFF', role: 'Crisp PSO white' },
  { key: 'principal', label: 'Principal', fill: '#F5F7FF', role: 'Cool ivory white' },
  { key: 'kai', label: 'Kai', fill: '#FFF1BE', role: 'Warm hunter gold-cream' },
  { key: 'sarisa', label: 'Sarisa', fill: '#FFDDF0', role: 'Soft blossom pink' },
  { key: 'ogi', label: 'Ogi', fill: '#C6F3FF', role: 'PSO CAST ice cyan' },
  { key: 'elio', label: 'Elio', fill: '#D6F7E2', role: 'Soft mint green' },
  { key: 'fern', label: 'Fern', fill: '#E8F7C8', role: 'Meadow lime pastel' },
  { key: 'dr_carlo', label: 'Dr. Carlo', fill: '#DAE7FF', role: 'Archive periwinkle' },
  { key: 'ren', label: 'Ren', fill: '#CCF6F4', role: 'Soft aqua cyan' },
  { key: 'dorn', label: 'Dorn', fill: '#FFE4C8', role: 'Forge peach-amber' },
  { key: 'mira', label: 'Mira', fill: '#EADBFF', role: 'Soft lavender' },
  { key: 'ana', label: 'Ana', fill: '#EEF0FF', role: 'Moonlight pearl' },
  { key: 'vash', label: 'Vash', fill: '#E2E8EE', role: 'Cool slate mist' },
];

export function colorForSpeaker(speaker: string): string {
  const norm = speaker.trim().toLowerCase().replace(/\./g, '').replace(/\s+/g, '_');
  const found = SPEAKER_PALETTE.find(
    (p) => p.key === norm || p.label.toLowerCase() === speaker.trim().toLowerCase(),
  );
  return found ? found.fill : '#FFFFFF';
}

const SHAPE_PRESETS: Record<ShapeStyleId, { label: string; desc: string; tuning: ShapeTuning }> = {
  'squared-slant': {
    label: 'Squared PSO Slant (Default)',
    desc: 'Tight 5px corners, subtle 0.16 forward slant, boxier 316px wrap',
    tuning: { cornerRadius: 5, slantRatio: 0.16, maxWidth: 316, padX: 22, padY: 16, chamfer: false },
  },
  'chamfer-slant': {
    label: 'Chamfered Hunter Tag',
    desc: 'Crisp 8px angled corner cuts + 0.14 forward slant',
    tuning: { cornerRadius: 8, slantRatio: 0.14, maxWidth: 316, padX: 22, padY: 16, chamfer: true },
  },
  'sharp-box': {
    label: 'Crisp Square Block',
    desc: 'Nearly upright (0.06 slant), 4px corners, compact comic block',
    tuning: { cornerRadius: 4, slantRatio: 0.06, maxWidth: 304, padX: 20, padY: 16, chamfer: false },
  },
  'classic-pso': {
    label: 'Classic Rounded PSO',
    desc: 'Wider 18px rounded pill corners + 0.26 PSO slant',
    tuning: { cornerRadius: 18, slantRatio: 0.26, maxWidth: 372, padX: 26, padY: 14, chamfer: false },
  },
};

const ASPECT_SIZES: Record<AspectId, { w: number; h: number; label: string }> = {
  '16:9': { w: 1280, h: 720, label: '16:9 (1280×720)' },
  '4:3': { w: 1280, h: 960, label: '4:3 (1280×960)' },
  '21:9': { w: 1680, h: 720, label: '21:9 (1680×720)' },
};

const SAFE_MARGIN_X = 28;
const SAFE_MARGIN_TOP = 22;
const SAFE_MARGIN_BOTTOM = 30;
const MIN_WIDTH = 164;
const FLOAT_GAP = 86;
const TAIL_BASE_HALF_W = 11;
const MAX_OFFSCREEN_TAIL = 56;
const BACKDROP_DX = 6;
const BACKDROP_DY = 5;
const OVERLAP_GAP = 12;
const HUD_GAP = 12;

const BACKDROPS: Record<BackdropId, { label: string; css: string; inCity: boolean }> = {
  forest: {
    label: 'Forest / Gurhacia (PSO green & sky)',
    css: 'linear-gradient(180deg, #4b82c8 0%, #7daae0 36%, #3f6d28 37%, #2b4d1b 100%)',
    inCity: false,
  },
  pioneer: {
    label: 'City Counter / Pioneer Deck',
    css: 'linear-gradient(180deg, #0d182c 0%, #1d3554 44%, #3c4d63 45%, #283548 100%)',
    inCity: true,
  },
  snowfield: {
    label: 'Rioh Snowfield (bright glare)',
    css: 'linear-gradient(180deg, #dbe9f6 0%, #eef5fc 46%, #cddff0 100%)',
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
  'pso-field': {
    label: 'PSO long tail (Sarisa)',
    backdrop: 'forest',
    speakers: [
      {
        id: 'p1',
        speaker: 'Sarisa',
        text: 'Are you mad because I let the Mags run away?',
        nx: 0.49,
        ny: 0.58,
      },
    ],
  },
  'pso-angled': {
    label: 'PSO diagonal tail (Kai)',
    backdrop: 'forest',
    speakers: [
      {
        id: 'p1',
        speaker: 'Kai',
        text: "A Mag left me when I wasn't paying attention.",
        nx: 0.61,
        ny: 0.56,
      },
    ],
  },
  'cast-cyan': {
    label: 'CAST cyan (Ogi)',
    backdrop: 'pioneer',
    speakers: [
      {
        id: 'p1',
        speaker: 'Ogi',
        text: 'He asked me to collect some for him. I accepted it for the Meseta.',
        nx: 0.44,
        ny: 0.46,
      },
    ],
  },
  'offscreen-dir': {
    label: 'Off-screen directional arrow',
    backdrop: 'snowfield',
    speakers: [
      {
        id: 'p1',
        speaker: 'Kai',
        text: 'Gate switch is over on the east ridge — follow me!',
        nx: 1.07,
        ny: 0.52,
      },
    ],
  },
  'behind-camera': {
    label: 'Behind camera arrow',
    backdrop: 'ruins',
    speakers: [
      {
        id: 'p1',
        speaker: 'Sarisa',
        text: 'Wait up! I found the second keycard back by the fountain!',
        nx: 0.36,
        ny: 0.96,
        behindCamera: true,
      },
    ],
  },
  'palette-corner': {
    label: 'Action Palette occlusion',
    backdrop: 'ruins',
    speakers: [
      {
        id: 'p1',
        speaker: 'Ogi',
        text: 'Careful, needle traps cycle every few seconds in this hall.',
        nx: 0.78,
        ny: 0.82,
      },
    ],
  },
  'two-npcs': {
    label: 'Multi-character exchange',
    backdrop: 'office',
    speakers: [
      {
        id: 'p1',
        speaker: 'Principal',
        text: 'Find that android in Rioh Snowfield and bring him home safely.',
        nx: 0.54,
        ny: 0.45,
      },
      {
        id: 'p2',
        speaker: 'Kai',
        text: 'Leave the heavy lifting to us. Ready when you are, partner.',
        nx: 0.36,
        ny: 0.57,
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

function measureBubble(text: string, tuning: ShapeTuning): { w: number; h: number; lines: string[] } {
  const charW = 9.2;
  const maxInnerW = tuning.maxWidth - tuning.padX * 2;
  const maxCharsPerLine = Math.max(10, Math.floor(maxInnerW / charW));
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
  const w = Math.max(MIN_WIDTH, Math.min(tuning.maxWidth, Math.ceil(longestLinePx + tuning.padX * 2)));
  const h = tuning.padY * 2 + lines.length * 22;
  return { w, h, lines };
}

function clampPointToBoundary(from: Pt, to: Pt, maxLen: number): Pt {
  const dx = to.x - from.x;
  const dy = to.y - from.y;
  const d = Math.hypot(dx, dy);
  if (d <= maxLen || d < 0.001) return to;
  return { x: from.x + (dx / d) * maxLen, y: from.y + (dy / d) * maxLen };
}

function computePlacement(
  vw: number,
  vh: number,
  size: { w: number; h: number },
  tuning: ShapeTuning,
  rawAnchor: Pt,
  behindCamera: boolean,
  hudRects: Rect[],
  occupiedRects: Rect[],
): PlacementResult {
  const { w, h } = size;
  const halfSlant = (h * tuning.slantRatio) * 0.5;
  const leftBound = SAFE_MARGIN_X + halfSlant;
  const rightBound = Math.max(leftBound, vw - SAFE_MARGIN_X - w - halfSlant - BACKDROP_DX);
  const topBound = SAFE_MARGIN_TOP;
  const bottomBound = Math.max(topBound, vh - SAFE_MARGIN_BOTTOM - h - 42);

  const offscreen =
    behindCamera ||
    rawAnchor.x < 8 ||
    rawAnchor.x > vw - 8 ||
    rawAnchor.y < 8 ||
    rawAnchor.y > vh - 8;

  const anchorPx: Pt = behindCamera
    ? {
        x: Math.max(vw * 0.14, Math.min(vw * 0.86, rawAnchor.x)),
        y: vh + 36,
      }
    : rawAnchor;

  const idealX = anchorPx.x - w * 0.54;
  const idealY = behindCamera ? vh - SAFE_MARGIN_BOTTOM - h - 44 : anchorPx.y - h - FLOAT_GAP;

  let bx = Math.max(leftBound, Math.min(rightBound, idealX));
  let by = Math.max(topBound, Math.min(bottomBound, idealY));
  const clampedEdge = Math.abs(bx - idealX) > 0.5 || Math.abs(by - idealY) > 0.5;

  let nudgedHud = false;
  for (const hud of hudRects) {
    const cur: Rect = { x: bx - halfSlant, y: by, w: w + halfSlant * 2, h: h + 18 };
    if (!rectsIntersect(cur, hud)) continue;
    const candidates: Pt[] = [
      { x: bx, y: hud.y + hud.h + HUD_GAP },
      { x: bx, y: hud.y - h - 28 - HUD_GAP },
      { x: hud.x + hud.w + HUD_GAP + halfSlant, y: by },
      { x: hud.x - w - HUD_GAP - halfSlant, y: by },
    ].filter(
      (c) =>
        c.x >= leftBound - 0.5 &&
        c.x <= rightBound + 0.5 &&
        c.y >= topBound - 0.5 &&
        c.y <= bottomBound + 0.5 &&
        !hudRects.some((hz) =>
          rectsIntersect({ x: c.x - halfSlant, y: c.y, w: w + halfSlant * 2, h: h + 18 }, hz),
        ),
    );
    if (candidates.length > 0) {
      candidates.sort((a, b) => Math.hypot(a.x - bx, a.y - by) - Math.hypot(b.x - bx, b.y - by));
      bx = Math.max(leftBound, Math.min(rightBound, candidates[0].x));
      by = Math.max(topBound, Math.min(bottomBound, candidates[0].y));
      nudgedHud = true;
    }
  }

  let nudgedOverlap = false;
  for (const occ of occupiedRects) {
    const cur: Rect = { x: bx - halfSlant, y: by, w: w + halfSlant * 2, h: h + 16 };
    if (!rectsIntersect(cur, occ)) continue;
    const upY = occ.y - h - OVERLAP_GAP - 14;
    const downY = occ.y + occ.h + OVERLAP_GAP;
    if (upY >= topBound) {
      by = upY;
    } else if (downY <= bottomBound) {
      by = downY;
    }
    nudgedOverlap = true;
  }

  const inset = Math.max(6, tuning.cornerRadius) + TAIL_BASE_HALF_W + 4;
  const bottomLeftX = bx - halfSlant + inset;
  const bottomRightX = Math.max(bottomLeftX, bx + w - halfSlant - inset);
  const baseX = Math.max(bottomLeftX, Math.min(bottomRightX, anchorPx.x * 0.35 + (bx + w * 0.5 - halfSlant) * 0.65));
  const tailBase: Pt = { x: baseX, y: by + h };

  let rawTip: Pt = { x: anchorPx.x, y: Math.max(by + h + 16, anchorPx.y - 8) };
  if (offscreen) {
    rawTip = clampPointToBoundary(tailBase, anchorPx, MAX_OFFSCREEN_TAIL);
    rawTip.x = Math.max(10, Math.min(vw - 10, rawTip.x));
    rawTip.y = Math.max(by + h + 14, Math.min(vh - 10, rawTip.y));
  } else {
    rawTip = clampPointToBoundary(tailBase, rawTip, 185);
  }

  const tailAngleDeg = Math.round((Math.atan2(rawTip.y - tailBase.y, rawTip.x - tailBase.x) * 180) / Math.PI);

  return {
    box: { x: bx, y: by, w, h },
    anchorPx,
    tailBase,
    tailTip: rawTip,
    tailAngleDeg,
    clampedEdge,
    nudgedHud,
    nudgedOverlap,
    behindCamera,
    offscreen,
  };
}

/** Build the PSO slanted speech bubble path (rounded or crisp-chamfered corners + stretching tail). */
function buildBubblePath(box: Rect, tuning: ShapeTuning, tailBase: Pt, tailTip: Pt): string {
  const { x, y, w, h } = box;
  const s = (h * tuning.slantRatio) * 0.5;
  const tl: Pt = { x: x + s, y };
  const tr: Pt = { x: x + w + s, y };
  const br: Pt = { x: x + w - s, y: y + h };
  const bl: Pt = { x: x - s, y: y + h };
  const r = Math.min(tuning.cornerRadius, h * 0.42, w * 0.22);

  const stepAlong = (a: Pt, b: Pt, dist: number): Pt => {
    const segLen = Math.hypot(b.x - a.x, b.y - a.y) || 1;
    return { x: a.x + ((b.x - a.x) / segLen) * dist, y: a.y + ((b.y - a.y) / segLen) * dist };
  };

  const tlIn = stepAlong(tl, bl, r);
  const tlOut = stepAlong(tl, tr, r);
  const trIn = stepAlong(tr, tl, r);
  const trOut = stepAlong(tr, br, r);
  const brIn = stepAlong(br, tr, r);
  const brOut = stepAlong(br, bl, r);
  const blIn = stepAlong(bl, br, r);
  const blOut = stepAlong(bl, tl, r);

  const minTx = bl.x + r + TAIL_BASE_HALF_W + 3;
  const maxTx = Math.max(minTx, br.x - r - TAIL_BASE_HALF_W - 3);
  const tx = Math.max(minTx, Math.min(maxTx, tailBase.x));

  const corner = (ctrl: Pt, outPt: Pt) =>
    r <= 0.5
      ? `L ${ctrl.x.toFixed(1)} ${ctrl.y.toFixed(1)}`
      : tuning.chamfer
        ? `L ${outPt.x.toFixed(1)} ${outPt.y.toFixed(1)}`
        : `Q ${ctrl.x.toFixed(1)} ${ctrl.y.toFixed(1)} ${outPt.x.toFixed(1)} ${outPt.y.toFixed(1)}`;

  return [
    `M ${tlOut.x.toFixed(1)} ${tlOut.y.toFixed(1)}`,
    `L ${trIn.x.toFixed(1)} ${trIn.y.toFixed(1)}`,
    corner(tr, trOut),
    `L ${brIn.x.toFixed(1)} ${brIn.y.toFixed(1)}`,
    corner(br, brOut),
    `L ${(tx + TAIL_BASE_HALF_W).toFixed(1)} ${(y + h).toFixed(1)}`,
    `L ${tailTip.x.toFixed(1)} ${tailTip.y.toFixed(1)}`,
    `L ${(tx - TAIL_BASE_HALF_W).toFixed(1)} ${(y + h).toFixed(1)}`,
    `L ${blIn.x.toFixed(1)} ${blIn.y.toFixed(1)}`,
    corner(bl, blOut),
    `L ${tlIn.x.toFixed(1)} ${tlIn.y.toFixed(1)}`,
    corner(tl, tlOut),
    'Z',
  ].join(' ');
}

export default function SpeechBubbleMock() {
  const [aspect, setAspect] = useState<AspectId>('16:9');
  const [preset, setPreset] = useState<PresetId>('pso-field');
  const [backdrop, setBackdrop] = useState<BackdropId>('forest');
  const [shapePreset, setShapePreset] = useState<ShapeStyleId>('squared-slant');
  const [tuning, setTuning] = useState<ShapeTuning>(SHAPE_PRESETS['squared-slant'].tuning);
  const [speakers, setSpeakers] = useState<SpeakerInput[]>(PRESETS['pso-field'].speakers);
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

  const applyShapePreset = (id: ShapeStyleId) => {
    setShapePreset(id);
    setTuning({ ...SHAPE_PRESETS[id].tuning });
  };

  const placements = useMemo(() => {
    const ordered = [...speakers].sort((a, b) => b.ny - a.ny);
    const occupied: Rect[] = [];
    const out = new Map<string, { measured: ReturnType<typeof measureBubble>; placement: PlacementResult }>();
    for (const sp of ordered) {
      const measured = measureBubble(sp.text, tuning);
      const rawAnchor = { x: sp.nx * vp.w, y: sp.ny * vp.h };
      const placement = computePlacement(
        vp.w,
        vp.h,
        measured,
        tuning,
        rawAnchor,
        Boolean(sp.behindCamera),
        hudZones.map((z) => z.rect),
        occupied,
      );
      const halfSlant = (measured.h * tuning.slantRatio) * 0.5;
      occupied.push({
        x: placement.box.x - halfSlant,
        y: placement.box.y,
        w: measured.w + halfSlant * 2,
        h: measured.h + 16,
      });
      out.set(sp.id, { measured, placement });
    }
    return out;
  }, [speakers, tuning, vp.w, vp.h, hudZones]);

  const onPointerMove = (e: React.PointerEvent<SVGSVGElement>) => {
    if (!draggingId || !svgRef.current) return;
    const rect = svgRef.current.getBoundingClientRect();
    const nx = Math.max(-0.1, Math.min(1.1, (e.clientX - rect.left) / rect.width));
    const ny = Math.max(0.04, Math.min(1.04, (e.clientY - rect.top) / rect.height));
    setSpeakers((prev) => prev.map((s) => (s.id === draggingId ? { ...s, nx, ny } : s)));
  };

  const primary = speakers[0];
  const primaryPlacement = primary ? placements.get(primary.id)?.placement : undefined;

  return (
    <div style={{ margin: '1.25rem 0', fontFamily: 'system-ui, sans-serif' }}>
      {/* Shape identity presets + fine sliders */}
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: '0.45rem', alignItems: 'center', marginBottom: '0.6rem' }}>
        <strong style={{ fontSize: 13 }}>Shape identity:</strong>
        {(Object.keys(SHAPE_PRESETS) as ShapeStyleId[]).map((id) => (
          <button
            key={id}
            type="button"
            onClick={() => applyShapePreset(id)}
            title={SHAPE_PRESETS[id].desc}
            style={{
              padding: '4px 10px',
              borderRadius: 6,
              border: shapePreset === id ? '2px solid #78afe6' : '1px solid #4a627a',
              background: shapePreset === id ? '#274466' : '#15202e',
              color: '#eef5ff',
              fontSize: 12,
              fontWeight: shapePreset === id ? 700 : 500,
              cursor: 'pointer',
            }}
          >
            {SHAPE_PRESETS[id].label}
          </button>
        ))}
      </div>

      <div
        style={{
          display: 'flex',
          flexWrap: 'wrap',
          gap: '1.1rem',
          alignItems: 'center',
          marginBottom: '0.75rem',
          fontSize: 12,
          opacity: 0.92,
        }}
      >
        <label style={{ display: 'inline-flex', alignItems: 'center', gap: 6 }}>
          <span>Corner: <strong>{tuning.cornerRadius}px</strong></span>
          <input
            type="range"
            min={0}
            max={20}
            step={1}
            value={tuning.cornerRadius}
            onChange={(e) => setTuning((t) => ({ ...t, cornerRadius: Number(e.target.value) }))}
          />
        </label>
        <label style={{ display: 'inline-flex', alignItems: 'center', gap: 6 }}>
          <span>Slant: <strong>{tuning.slantRatio.toFixed(2)}</strong></span>
          <input
            type="range"
            min={0}
            max={0.3}
            step={0.02}
            value={tuning.slantRatio}
            onChange={(e) => setTuning((t) => ({ ...t, slantRatio: Number(e.target.value) }))}
          />
        </label>
        <label style={{ display: 'inline-flex', alignItems: 'center', gap: 6 }}>
          <span>Max width: <strong>{tuning.maxWidth}px</strong></span>
          <input
            type="range"
            min={260}
            max={400}
            step={8}
            value={tuning.maxWidth}
            onChange={(e) => setTuning((t) => ({ ...t, maxWidth: Number(e.target.value) }))}
          />
        </label>
        <label style={{ display: 'inline-flex', alignItems: 'center', gap: 5 }}>
          <input
            type="checkbox"
            checked={tuning.chamfer}
            onChange={(e) => setTuning((t) => ({ ...t, chamfer: e.target.checked }))}
          />
          Chamfer cut
        </label>
      </div>

      {/* Scenario preset pills */}
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: '0.45rem', alignItems: 'center', marginBottom: '0.7rem' }}>
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

      {/* Aspect, backdrop & speaker controls */}
      {primary && (
        <div
          style={{
            display: 'flex',
            flexWrap: 'wrap',
            gap: '0.85rem',
            alignItems: 'center',
            marginBottom: '0.7rem',
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
            Behind camera
          </label>
        </div>
      )}

      {/* Character color swatch bar */}
      <div
        style={{
          display: 'flex',
          flexWrap: 'wrap',
          gap: '0.4rem',
          marginBottom: '0.75rem',
          fontSize: 11,
          fontFamily: "'JetBrains Mono', monospace",
        }}
      >
        {SPEAKER_PALETTE.map((p) => (
          <button
            key={p.key}
            type="button"
            onClick={() =>
              setSpeakers((prev) => prev.map((s, i) => (i === 0 ? { ...s, speaker: p.label } : s)))
            }
            style={{
              display: 'inline-flex',
              alignItems: 'center',
              gap: 6,
              padding: '3px 9px',
              borderRadius: 4,
              background: p.fill,
              color: '#0a0c10',
              border: '1.5px solid #000',
              boxShadow: '2px 2px 0 #000',
              fontWeight: 700,
              cursor: 'pointer',
            }}
            title={p.role}
          >
            {p.label.split(' ')[0]}
          </button>
        ))}
      </div>

      {/* Interactive viewport */}
      <div
        style={{
          width: '100%',
          maxWidth: 880,
          borderRadius: 10,
          overflow: 'hidden',
          border: '2px solid #354b63',
          boxShadow: '0 6px 20px rgba(0,0,0,0.35)',
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
          {/* Layer 0 — 3D Scene: NPC silhouettes */}
          {speakers.map((sp) => {
            if (sp.behindCamera) return null;
            const ax = sp.nx * vp.w;
            const ay = sp.ny * vp.h;
            const tint = colorForSpeaker(sp.speaker);
            return (
              <g key={`npc-${sp.id}`} opacity={0.92} style={{ pointerEvents: 'none' }}>
                <rect
                  x={ax - 22}
                  y={ay + 22}
                  width={44}
                  height={110}
                  rx={20}
                  fill="#29435c"
                  stroke={tint}
                  strokeWidth={2.5}
                />
                <circle cx={ax} cy={ay + 12} r={15} fill={tint} stroke="#101824" strokeWidth={2} />
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
            stroke="rgba(255,255,255,0.24)"
            strokeDasharray="6 6"
            strokeWidth={1.5}
            style={{ pointerEvents: 'none' }}
          />

          {/* Layer 40 — Squared PSO Speech Bubbles (solid #000 backdrop + character pastel + stretching arrow) */}
          {speakers.map((sp) => {
            const item = placements.get(sp.id);
            if (!item) return null;
            const { measured, placement } = item;
            const fill = colorForSpeaker(sp.speaker);
            const shapePath = buildBubblePath(placement.box, tuning, placement.tailBase, placement.tailTip);

            return (
              <g key={`bubble-${sp.id}`} style={{ pointerEvents: 'none' }}>
                <path
                  d={shapePath}
                  transform={`translate(${BACKDROP_DX}, ${BACKDROP_DY})`}
                  fill="#000000"
                />
                <path
                  d={shapePath}
                  fill={fill}
                  stroke="rgba(10, 14, 20, 0.82)"
                  strokeWidth={1.6}
                  strokeLinejoin="miter"
                />
                {measured.lines.map((line, idx) => (
                  <text
                    key={idx}
                    x={placement.box.x + tuning.padX}
                    y={placement.box.y + tuning.padY + 16 + idx * 22}
                    fill="#080a10"
                    fontSize={15}
                    fontWeight={700}
                    fontFamily="'JetBrains Mono', monospace"
                  >
                    {line}
                  </text>
                ))}
              </g>
            );
          })}

          {/* Layer 200 — FieldHud / HudStats CanvasLayer (solidly in front of 3D scene & speech bubbles) */}
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

          {/* Interactive gizmo: draggable head-anchor handle */}
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
                  r={10}
                  fill={occludedByHud ? 'rgba(240, 160, 32, 0.18)' : '#f0a020'}
                  stroke={occludedByHud ? 'rgba(240, 160, 32, 0.75)' : '#101824'}
                  strokeDasharray={occludedByHud ? '3 3' : undefined}
                  strokeWidth={2.5}
                />
                {!occludedByHud && <circle cx={ax} cy={ay} r={3} fill="#101824" />}
              </g>
            );
          })}
        </svg>
      </div>

      {primaryPlacement && primary && (
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
          <span>speaker={primary.speaker} ({colorForSpeaker(primary.speaker)})</span>
          <span>corner={tuning.cornerRadius}px</span>
          <span>slant={tuning.slantRatio.toFixed(2)}</span>
          <span>
            box=({Math.round(primaryPlacement.box.x)}, {Math.round(primaryPlacement.box.y)},{' '}
            {Math.round(primaryPlacement.box.w)}×{Math.round(primaryPlacement.box.h)})
          </span>
          <span>tailAngle={primaryPlacement.tailAngleDeg}°</span>
          <span>offscreenArrow={String(primaryPlacement.offscreen)}</span>
        </div>
      )}
    </div>
  );
}
