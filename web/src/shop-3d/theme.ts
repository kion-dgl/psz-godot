// PSZ shop-menu theme — the canonical "pale icy blue, white pill rows, black
// text, orange selection" palette, lifted from storybook/MenuDesign.tsx so the
// 3D shop overlays read as the SAME UI language as the flat menu mocks. Kept
// self-contained (no import from MenuDesign) so these experiments can diverge
// freely without disturbing the reference mock.

export const C = {
  // Backgrounds
  bgLight: '#a8cce8',       // Pale icy blue (main panel bg)
  bgMid: '#8ab8d8',         // Slightly darker blue
  bgDark: '#2a3448',        // Dark navy (title bar, dividers)
  bgDarker: '#1e2838',      // Darker navy
  // Items
  itemBg: 'rgba(255,255,255,0.85)',
  itemBgHover: 'rgba(255,255,255,0.95)',
  selectedGradient: 'linear-gradient(90deg, #f0a020 0%, #f8c840 100%)',
  // Text
  text: '#1a1a2a',
  textLight: '#3a4a5a',
  textWhite: '#ffffff',
  textOnSelected: '#1a1a2a',
  // Accents
  hintBg: 'rgba(255,255,255,0.7)',
  hintBorder: '#8aa8c8',
  separator: '#7aa0c0',
  // HP/PP
  hp: '#44bb44',
  hpBg: '#d8e8d8',
  pp: '#4488ee',
  ppBg: '#d8d8f0',
  // Currency / rarity
  meseta: '#886600',
  photon: '#8844cc',
  rare: '#cc2222',
  common: '#1a1a2a',
} as const;

// Scanline overlay for the DS-panel texture feel.
export const SCANLINES = `repeating-linear-gradient(
  0deg,
  transparent,
  transparent 2px,
  rgba(120,160,200,0.08) 2px,
  rgba(120,160,200,0.08) 4px
)`;

export const FONT = "'Segoe UI', 'Helvetica Neue', Arial, sans-serif";

// A translucent variant of the panel background, for overlay panels that must
// let the 3D scene read through them (the whole point of the diegetic menu).
export const glassPanelBg = (alpha = 0.82) =>
  `rgba(168, 204, 232, ${alpha})`;
