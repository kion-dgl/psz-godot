import React, { useMemo, useRef, useState } from 'react';

type AspectId = '16:9' | '4:3' | '21:9';
type BackdropId = 'forest' | 'pioneer' | 'snowfield' | 'ruins' | 'office';
type BubbleTone = 'normal' | 'shout' | 'thought';
type PresetId =
  | 'pso-field'
  | 'pso-angled'
  | 'cast-cyan'
  | 'offscreen-dir'
  | 'behind-camera'
  | 'palette-corner'
  | 'two-npcs'
  | 'tones';

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
  tone: BubbleTone;
  nx: number;
  ny: number;
  behindCamera?: boolean;
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

const ASPECT_SIZES: Record<AspectId, { w: number; h: number; label: string }> = {
  '16:9': { w: 1280, h: 720, label: '16:9 (1280×720)' },
  '4:3': { w: 1280, h: 960, label: '4:3 (1280×960)' },
  '21:9': { w: 1680, h: 720, label: '21:9 (1680×720)' },
};

const SAFE_MARGIN_X = 28;
const SAFE_MARGIN_TOP = 22;
const SAFE_MARGIN_BOTTOM = 30;
const MIN_WIDTH = 176;
const MAX_WIDTH = 392;
const PAD_X = 26;
const PAD_Y = 14;
const CORNER_RADIUS = 18;
const SLANT_RATIO = 0.26; // PSO forward slant `/`
const FLOAT_GAP = 86; // PSO comfortable vertical gap so long tail connects to speaker
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
        tone: 'normal',
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
        tone: 'normal',
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
        tone: 'normal',
        text: 'He asked me to collect some for him. I accepted it for the Meseta.',
        nx: 0.44,
        ny: 0.44,
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
        tone: 'shout',
        text: 'Gate switch is over on the east ridge — this way!',
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
        tone: 'normal',
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
        tone: 'normal',
        text: 'Careful, needle traps cycle every few seconds in this hall.',
        nx: 0.78,
        ny: 0.82,
      },
    ],
  },
  'two-npcs': {
    label: 'Multi-character colors',
    backdrop: 'office',
    speakers: [
      {
        id: 'p1',
        speaker: 'Principal',
        tone: 'normal',
        text: 'Find that android in Rioh Snowfield and bring him home safely.',
        nx: 0.52,
        ny: 0.44,
      },
      {
        id: 'p2',
        speaker: 'Kai',
        tone: 'normal',
        text: "Leave the heavy lifting to us. Ready when you are, partner.",
        nx: 0.38,
        ny: 0.56,
      },
    ],
  },
  tones: {
    label: '3 Tone shapes (Normal / Shout / Thought)',
    backdrop: 'pioneer',
    speakers: [
      {
        id: 't1',
        speaker: 'Kai',
        tone: 'shout',
        text: 'Ambush! Hostiles dropping from the ceiling!',
        nx: 0.25,
        ny: 0.56,
      },
      {
        id: 't2',
        speaker: 'Ogi',
        tone: 'normal',
        text: 'Shields holding. Prioritize the leader.',
        nx: 0.53,
        ny: 0.58,
      },
      {
        id: 't3',
        speaker: 'Sarisa',
        tone: 'thought',
        text: '...That photon signature felt familiar somehow.',
        nx: 0.81,
        ny: 0.56,
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

function measureBubble(text: string): { w: number; h: number; lines: string[] } {
  const charW = 9.2; // 15px bold JetBrains Mono advance
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
  const w = Math.max(MIN_WIDTH, Math.min(MAX_WIDTH, Math.ceil(longestLinePx + PAD_X * 2)));
  const h = PAD_Y * 2 + lines.length * 22;
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
  rawAnchor: Pt,
  behindCamera: boolean,
  hudRects: Rect[],
  occupiedRects: Rect[],
): PlacementResult {
  const { w, h } = size;
  const halfSlant = (h * SLANT_RATIO) * 0.5;
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

  // PSO bias: sit comfortably above the speaker (sometimes slightly offset so angled tails read cleanly)
  const idealX = anchorPx.x - w * 0.54;
  const idealY = behindCamera
    ? vh - SAFE_MARGIN_BOTTOM - h - 44
    : anchorPx.y - h - FLOAT_GAP;

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

  // Compute tail base on bottom (or side-bottom) of slanted card and tip pointing back to speaker
  const bottomLeftX = bx - halfSlant + CORNER_RADIUS + TAIL_BASE_HALF_W + 4;
  const bottomRightX = bx + w - halfSlant - CORNER_RADIUS - TAIL_BASE_HALF_W - 4;
  const baseX = Math.max(bottomLeftX, Math.min(bottomRightX, anchorPx.x * 0.35 + (bx + w * 0.5 - halfSlant) * 0.65));
  const tailBase: Pt = { x: baseX, y: by + h };

  // Target tip: if speaker is on-screen below the box, stretch all the way to (anchorPx.x, anchorPx.y - 8) like PSO!
  // If speaker is off-screen or behind camera, point a crisp directional arrow toward where they are coming from.
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

/** Build a rounded polygon SVG path from ordered corner vertices, inserting an optional bottom tail. */
function buildSlantedNormalPath(box: Rect, tailBase: Pt, tailTip: Pt, includeTail: boolean): string {
  const { x, y, w, h } = box;
  const s = (h * SLANT_RATIO) * 0.5;
  // 4 slanted parallelogram corners (clockwise: TL, TR, BR, BL)
  const tl: Pt = { x: x + s, y };
  const tr: Pt = { x: x + w + s, y };
  const br: Pt = { x: x + w - s, y: y + h };
  const bl: Pt = { x: x - s, y: y + h };
  const r = Math.min(CORNER_RADIUS, h * 0.42, w * 0.22);

  const stepAlong = (a: Pt, b: Pt, dist: number): Pt => {
    const len = Math.hypot(b.x - a.x, b.y - a.y) || 1;
    return { x: a.x + ((b.x - a.x) / len) * dist, y: a.y + ((b.y - a.y) / len) * dist };
  };

  const tlIn = stepAlong(tl, bl, r);
  const tlOut = stepAlong(tl, tr, r);
  const trIn = stepAlong(tr, tl, r);
  const trOut = stepAlong(tr, br, r);
  const brIn = stepAlong(br, tr, r);
  const brOut = stepAlong(br, bl, r);
  const blIn = stepAlong(bl, br, r);
  const blOut = stepAlong(bl, tl, r);

  const minTx = bl.x + r + TAIL_BASE_HALF_W + 2;
  const maxTx = br.x - r - TAIL_BASE_HALF_W - 2;
  const tx = Math.max(minTx, Math.min(maxTx, tailBase.x));

  const parts = [
    `M ${tlOut.x.toFixed(1)} ${tlOut.y.toFixed(1)}`,
    `L ${trIn.x.toFixed(1)} ${trIn.y.toFixed(1)}`,
    `Q ${tr.x.toFixed(1)} ${tr.y.toFixed(1)} ${trOut.x.toFixed(1)} ${trOut.y.toFixed(1)}`,
    `L ${brIn.x.toFixed(1)} ${brIn.y.toFixed(1)}`,
    `Q ${br.x.toFixed(1)} ${br.y.toFixed(1)} ${brOut.x.toFixed(1)} ${brOut.y.toFixed(1)}`,
  ];

  if (includeTail) {
    parts.push(
      `L ${(tx + TAIL_BASE_HALF_W).toFixed(1)} ${(y + h).toFixed(1)}`,
      `L ${tailTip.x.toFixed(1)} ${tailTip.y.toFixed(1)}`,
      `L ${(tx - TAIL_BASE_HALF_W).toFixed(1)} ${(y + h).toFixed(1)}`,
    );
  }

  parts.push(
    `L ${blIn.x.toFixed(1)} ${blIn.y.toFixed(1)}`,
    `Q ${bl.x.toFixed(1)} ${bl.y.toFixed(1)} ${blOut.x.toFixed(1)} ${blOut.y.toFixed(1)}`,
    `L ${tlIn.x.toFixed(1)} ${tlIn.y.toFixed(1)}`,
    `Q ${tl.x.toFixed(1)} ${tl.y.toFixed(1)} ${tlOut.x.toFixed(1)} ${tlOut.y.toFixed(1)}`,
    'Z',
  );
  return parts.join(' ');
}

/** Sample perimeter points along a rounded rectangle for uniform normal-extruded burst/cloud shapes. */
function sampleRoundedPerimeter(box: Rect, count: number): { pt: Pt; normal: Pt }[] {
  const { x, y, w, h } = box;
  const r = Math.min(22, h * 0.45, w * 0.25);
  const straightW = Math.max(0, w - 2 * r);
  const straightH = Math.max(0, h - 2 * r);
  const arcLen = 0.5 * Math.PI * r;
  const totalLen = 2 * straightW + 2 * straightH + 4 * arcLen;

  const atDist = (s: number): { pt: Pt; normal: Pt } => {
    let d = ((s % totalLen) + totalLen) % totalLen;
    // Top edge: (x+r, y) -> (x+w-r, y), normal (0, -1)
    if (d < straightW) return { pt: { x: x + r + d, y }, normal: { x: 0, y: -1 } };
    d -= straightW;
    // Top-right arc: center (x+w-r, y+r), angle -PI/2 -> 0
    if (d < arcLen) {
      const a = -Math.PI * 0.5 + (d / arcLen) * (Math.PI * 0.5);
      return { pt: { x: x + w - r + Math.cos(a) * r, y: y + r + Math.sin(a) * r }, normal: { x: Math.cos(a), y: Math.sin(a) } };
    }
    d -= arcLen;
    // Right edge: (x+w, y+r) -> (x+w, y+h-r), normal (1, 0)
    if (d < straightH) return { pt: { x: x + w, y: y + r + d }, normal: { x: 1, y: 0 } };
    d -= straightH;
    // Bottom-right arc: center (x+w-r, y+h-r), angle 0 -> PI/2
    if (d < arcLen) {
      const a = (d / arcLen) * (Math.PI * 0.5);
      return { pt: { x: x + w - r + Math.cos(a) * r, y: y + h - r + Math.sin(a) * r }, normal: { x: Math.cos(a), y: Math.sin(a) } };
    }
    d -= arcLen;
    // Bottom edge: (x+w-r, y+h) -> (x+r, y+h), normal (0, 1)
    if (d < straightW) return { pt: { x: x + w - r - d, y: y + h }, normal: { x: 0, y: 1 } };
    d -= straightW;
    // Bottom-left arc: center (x+r, y+h-r), angle PI/2 -> PI
    if (d < arcLen) {
      const a = Math.PI * 0.5 + (d / arcLen) * (Math.PI * 0.5);
      return { pt: { x: x + r + Math.cos(a) * r, y: y + h - r + Math.sin(a) * r }, normal: { x: Math.cos(a), y: Math.sin(a) } };
    }
    d -= arcLen;
    // Left edge: (x, y+h-r) -> (x, y+r), normal (-1, 0)
    if (d < straightH) return { pt: { x, y: y + h - r - d }, normal: { x: -1, y: 0 } };
    d -= straightH;
    // Top-left arc: center (x+r, y+r), angle PI -> 1.5*PI
    const a = Math.PI + (d / arcLen) * (Math.PI * 0.5);
    return { pt: { x: x + r + Math.cos(a) * r, y: y + r + Math.sin(a) * r }, normal: { x: Math.cos(a), y: Math.sin(a) } };
  };

  const samples: { pt: Pt; normal: Pt }[] = [];
  for (let i = 0; i < count; i++) {
    const raw = atDist((i * totalLen) / count);
    // Apply subtle PSO forward slant
    const slantShift = ((box.y + box.h * 0.5 - raw.pt.y) / box.h) * (box.h * SLANT_RATIO);
    samples.push({ pt: { x: raw.pt.x + slantShift, y: raw.pt.y }, normal: raw.normal });
  }
  return samples;
}

/** PSO spiky starburst polygon for `shout` tone, with uniform normal-extruded teeth + pointer tail. */
function buildShoutBurstPath(box: Rect, _tailBase: Pt, tailTip: Pt): string {
  const spikes = 22;
  const samples = sampleRoundedPerimeter(box, spikes * 2);
  let bestTailIdx = 0;
  let bestDist = Infinity;
  for (let i = 0; i < samples.length; i += 2) {
    const d = Math.hypot(samples[i].pt.x - tailTip.x, samples[i].pt.y - tailTip.y);
    if (d < bestDist) {
      bestDist = d;
      bestTailIdx = i;
    }
  }
  const pts: Pt[] = samples.map((s, idx) => {
    if (idx === bestTailIdx) return tailTip;
    const extrude = idx % 2 === 0 ? 12 : -2;
    return { x: s.pt.x + s.normal.x * extrude, y: s.pt.y + s.normal.y * extrude };
  });
  return (
    pts.map((p, idx) => `${idx === 0 ? 'M' : 'L'} ${p.x.toFixed(1)} ${p.y.toFixed(1)}`).join(' ') +
    ' Z'
  );
}

/** PSO scalloped cloud perimeter + trailing thought dots toward speaker. */
function buildThoughtCloud(box: Rect, tailBase: Pt, tailTip: Pt): { cloudPath: string; dots: { x: number; y: number; r: number }[] } {
  const lobes = 16;
  const samples = sampleRoundedPerimeter(box, lobes * 2);
  const parts: string[] = [];

  for (let i = 0; i < lobes; i++) {
    const s0 = samples[i * 2];
    const sm = samples[i * 2 + 1];
    const s1 = samples[(i * 2 + 2) % samples.length];
    const p0: Pt = { x: s0.pt.x - s0.normal.x * 1.5, y: s0.pt.y - s0.normal.y * 1.5 };
    const p1: Pt = { x: s1.pt.x - s1.normal.x * 1.5, y: s1.pt.y - s1.normal.y * 1.5 };
    const ctrl: Pt = { x: sm.pt.x + sm.normal.x * 14, y: sm.pt.y + sm.normal.y * 14 };
    if (i === 0) parts.push(`M ${p0.x.toFixed(1)} ${p0.y.toFixed(1)}`);
    parts.push(`Q ${ctrl.x.toFixed(1)} ${ctrl.y.toFixed(1)} ${p1.x.toFixed(1)} ${p1.y.toFixed(1)}`);
  }
  parts.push('Z');

  const dots = [0.28, 0.58, 0.85].map((t, idx) => ({
    x: tailBase.x + (tailTip.x - tailBase.x) * t,
    y: tailBase.y + 8 + (tailTip.y - tailBase.y) * t,
    r: [8.5, 6.0, 3.8][idx],
  }));

  return { cloudPath: parts.join(' '), dots };
}

export default function SpeechBubbleMock() {
  const [aspect, setAspect] = useState<AspectId>('16:9');
  const [preset, setPreset] = useState<PresetId>('pso-field');
  const [backdrop, setBackdrop] = useState<BackdropId>('forest');
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

  const placements = useMemo(() => {
    const ordered = [...speakers].sort((a, b) => b.ny - a.ny);
    const occupied: Rect[] = [];
    const out = new Map<string, { measured: ReturnType<typeof measureBubble>; placement: PlacementResult }>();
    for (const sp of ordered) {
      const measured = measureBubble(sp.text);
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
      const halfSlant = (measured.h * SLANT_RATIO) * 0.5;
      occupied.push({
        x: placement.box.x - halfSlant,
        y: placement.box.y,
        w: measured.w + halfSlant * 2,
        h: measured.h + 16,
      });
      out.set(sp.id, { measured, placement });
    }
    return out;
  }, [speakers, vp.w, vp.h, hudZones]);

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

      {/* Primary speaker character tint & tone shape controls */}
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
            <strong>Speaker color: </strong>
            <select
              value={primary.speaker}
              onChange={(e) =>
                setSpeakers((prev) =>
                  prev.map((s, i) => (i === 0 ? { ...s, speaker: e.target.value } : s)),
                )
              }
              style={{ padding: '3px 8px', borderRadius: 4 }}
            >
              {SPEAKER_PALETTE.map((p) => (
                <option key={p.key} value={p.label}>
                  {p.label} ({p.fill})
                </option>
              ))}
            </select>
          </label>

          <div style={{ display: 'inline-flex', gap: 5, alignItems: 'center' }}>
            <strong>Tone shape:</strong>
            {(['normal', 'shout', 'thought'] as BubbleTone[]).map((t) => (
              <button
                key={t}
                type="button"
                onClick={() =>
                  setSpeakers((prev) => prev.map((s, i) => (i === 0 ? { ...s, tone: t } : s)))
                }
                style={{
                  padding: '3px 9px',
                  borderRadius: 5,
                  border: primary.tone === t ? '2px solid #78afe6' : '1px solid #4a627a',
                  background: primary.tone === t ? '#274466' : '#15202e',
                  color: '#eef5ff',
                  fontSize: 12,
                  fontWeight: primary.tone === t ? 700 : 400,
                  cursor: 'pointer',
                  textTransform: 'capitalize',
                }}
              >
                {t}
              </button>
            ))}
          </div>

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
        {SPEAKER_PALETTE.slice(0, 10).map((p) => (
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
              padding: '3px 8px',
              borderRadius: 999,
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
          {/* Layer 0 — 3D Scene: NPC silhouettes (behind SpeechBubble layer 40 and HUD layer 200) */}
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

          {/* Layer 40 — PSO Speech Bubbles (solid #000 backdrop + tinted slanted/tone shape + stretching arrow) */}
          {speakers.map((sp) => {
            const item = placements.get(sp.id);
            if (!item) return null;
            const { measured, placement } = item;
            const fill = colorForSpeaker(sp.speaker);

            if (sp.tone === 'thought') {
              const { cloudPath, dots } = buildThoughtCloud(
                placement.box,
                placement.tailBase,
                placement.tailTip,
              );
              return (
                <g key={`bubble-${sp.id}`} style={{ pointerEvents: 'none' }}>
                  {/* Solid black offset backdrop */}
                  <g transform={`translate(${BACKDROP_DX - 1}, ${BACKDROP_DY - 1})`}>
                    <path d={cloudPath} fill="#000000" />
                    {dots.map((d, idx) => (
                      <circle key={`bd-${idx}`} cx={d.x} cy={d.y} r={d.r} fill="#000000" />
                    ))}
                  </g>
                  <path d={cloudPath} fill={fill} stroke="#0a0c10" strokeWidth={1.5} strokeLinejoin="round" />
                  {dots.map((d, idx) => (
                    <circle key={`fg-${idx}`} cx={d.x} cy={d.y} r={d.r} fill={fill} stroke="#0a0c10" strokeWidth={1.5} />
                  ))}
                  {measured.lines.map((line, idx) => (
                    <text
                      key={idx}
                      x={placement.box.x + PAD_X}
                      y={placement.box.y + PAD_Y + 16 + idx * 22}
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
            }

            const shapePath =
              sp.tone === 'shout'
                ? buildShoutBurstPath(placement.box, placement.tailBase, placement.tailTip)
                : buildSlantedNormalPath(placement.box, placement.tailBase, placement.tailTip, true);

            return (
              <g key={`bubble-${sp.id}`} style={{ pointerEvents: 'none' }}>
                {/* PSO solid jet-black hard backdrop */}
                <path
                  d={shapePath}
                  transform={`translate(${BACKDROP_DX}, ${BACKDROP_DY})`}
                  fill="#000000"
                />
                {/* Foreground tinted PSO bubble */}
                <path
                  d={shapePath}
                  fill={fill}
                  stroke="rgba(10, 14, 20, 0.72)"
                  strokeWidth={1.4}
                  strokeLinejoin="round"
                />
                {measured.lines.map((line, idx) => (
                  <text
                    key={idx}
                    x={placement.box.x + PAD_X}
                    y={placement.box.y + PAD_Y + 16 + idx * 22}
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
          <span>tone={primary.tone}</span>
          <span>
            box=({Math.round(primaryPlacement.box.x)}, {Math.round(primaryPlacement.box.y)},{' '}
            {Math.round(primaryPlacement.box.w)}×{Math.round(primaryPlacement.box.h)})
          </span>
          <span>tailAngle={primaryPlacement.tailAngleDeg}°</span>
          <span>offscreenArrow={String(primaryPlacement.offscreen)}</span>
          <span>hudNudged={String(primaryPlacement.nudgedHud)}</span>
        </div>
      )}
    </div>
  );
}
