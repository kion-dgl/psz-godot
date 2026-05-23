export type SlatsPalette = {
  id: string;
  rootBg: string;
  // Per-type accent colours used for stripes, name glow, stat bars, bonus pill.
  typeColors: { Hunter: string; Ranger: string; Force: string };
  ambientGlowAlpha: string; // hex alpha appended to the active type color
  // Header
  eyebrowColor: string;
  titleColor: string;
  rightSecondaryColor: string;
  headerBorderColor: string;
  headerShadowColor: string;
  // Slats
  unselectedOpacity: number;
  unselectedFilter: string;
  vertNameColor: string;
  vertNameShadow: string;
  // Expanded info panel
  panelGradient: string;
  expandedNameColor: string;
  expandedNameShadowAlpha: string; // hex alpha applied to type color in the text-shadow
  // Stats
  statLabelColor: string;
  statBarTrackColor: string;
  statValueColor: string;
  statBarShadowAlpha: string;
  // Bonuses
  bonusBgAlpha: string;
  bonusTextColor: string;
  // Footer
  footerColor: string;
  footerBorderColor: string;
  footerAccentColor: string;
  // Confirm primary button in the footer right-side
  confirmButtonBg: string;
  confirmButtonText: string;
  confirmButtonBorder: string;
  confirmButtonShadow: string;
  // Optional PSZ-style chrome — when null/0/transparent, no scanlines / accent
  // bar / header & footer panel bg are drawn. Existing palettes
  // (dark/light/sky/steel) leave these off; the PSZ palette uses them to get
  // the reference look from web/public/menu-design/character_select_layout.png.
  scanlinesPattern: string | null;
  topAccentBar: string | null;
  topAccentBarHeight: number;
  headerBg: string;
  titleItalic: boolean;
  titleShadow: string;
  footerBg: string;
};

// Original dark variant (PSO-feeling, kept for comparison).
export const DARK_SLATS_PALETTE: SlatsPalette = {
  id: 'dark',
  rootBg: 'linear-gradient(180deg, #1a2240 0%, #0c1330 55%, #050917 100%)',
  typeColors: {
    Hunter: '#ff6b6b',
    Ranger: '#51cf66',
    Force: '#6b8afd',
  },
  ambientGlowAlpha: '26',
  eyebrowColor: '#88aaff',
  titleColor: '#ffffff',
  rightSecondaryColor: '#88aaff',
  headerBorderColor: 'rgba(253, 224, 71, 0.18)',
  headerShadowColor: 'rgba(253, 224, 71, 0.30)',
  unselectedOpacity: 0.32,
  unselectedFilter: 'grayscale(0.4) brightness(0.8)',
  vertNameColor: '#ffffff',
  vertNameShadow: '0 1px 4px rgba(0,0,0,0.85)',
  panelGradient:
    'linear-gradient(180deg, transparent 0%, rgba(5, 9, 23, 0.65) 35%, rgba(5, 9, 23, 0.92) 100%)',
  expandedNameColor: '#ffffff',
  expandedNameShadowAlpha: '88',
  statLabelColor: '#a0b0d0',
  statBarTrackColor: 'rgba(255,255,255,0.08)',
  statValueColor: '#ffffff',
  statBarShadowAlpha: 'aa',
  bonusBgAlpha: '22',
  bonusTextColor: '#d0d8e8',
  footerColor: 'rgba(136, 170, 255, 0.7)',
  footerBorderColor: 'rgba(253, 224, 71, 0.12)',
  footerAccentColor: '#fde047',
  confirmButtonBg: '#fde047',
  confirmButtonText: '#0c1330',
  confirmButtonBorder: 'transparent',
  confirmButtonShadow: '0 0 10px rgba(253, 224, 71, 0.45)',
  scanlinesPattern: null,
  topAccentBar: null,
  topAccentBarHeight: 0,
  headerBg: 'transparent',
  titleItalic: false,
  titleShadow: 'none',
  footerBg: 'transparent',
};

// PSZ A: parchment / warm-light. Cream→sky gradient, navy text, gold accents.
export const LIGHT_SLATS_PALETTE: SlatsPalette = {
  id: 'light',
  rootBg:
    'linear-gradient(180deg, #fef9c3 0%, #fef3c7 22%, #e0f2fe 62%, #bae6fd 100%)',
  typeColors: {
    Hunter: '#ca8a04', // warm gold
    Ranger: '#475569', // slate gray
    Force: '#0284c7', // deep sky
  },
  ambientGlowAlpha: '33',
  eyebrowColor: '#1e3a8a',
  titleColor: '#172554',
  rightSecondaryColor: '#1e3a8a',
  headerBorderColor: 'rgba(30, 58, 138, 0.25)',
  headerShadowColor: 'rgba(202, 138, 4, 0.45)',
  unselectedOpacity: 0.42,
  unselectedFilter: 'grayscale(0.25) brightness(0.95)',
  vertNameColor: '#172554',
  vertNameShadow: '0 1px 3px rgba(255,255,255,0.85), 0 0 6px rgba(255,255,255,0.5)',
  panelGradient:
    'linear-gradient(180deg, transparent 0%, rgba(254, 249, 195, 0.85) 35%, rgba(253, 230, 138, 0.95) 100%)',
  expandedNameColor: '#172554',
  expandedNameShadowAlpha: '55',
  statLabelColor: '#475569',
  statBarTrackColor: 'rgba(30, 58, 138, 0.15)',
  statValueColor: '#172554',
  statBarShadowAlpha: '99',
  bonusBgAlpha: '33',
  bonusTextColor: '#1e293b',
  footerColor: 'rgba(30, 58, 138, 0.65)',
  footerBorderColor: 'rgba(30, 58, 138, 0.18)',
  footerAccentColor: '#a16207',
  confirmButtonBg: '#f59e0b',
  confirmButtonText: '#172554',
  confirmButtonBorder: 'transparent',
  confirmButtonShadow: '0 0 10px rgba(245, 158, 11, 0.45)',
  scanlinesPattern: null,
  topAccentBar: null,
  topAccentBarHeight: 0,
  headerBg: 'transparent',
  titleItalic: false,
  titleShadow: 'none',
  footerBg: 'transparent',
};

// PSZ B: sky wash. Full sky-blue gradient bg (matches the asset-loader),
// white-ish type accents, gold highlight on the selected slat.
export const SKY_SLATS_PALETTE: SlatsPalette = {
  id: 'sky',
  rootBg: 'linear-gradient(180deg, #7dd3fc 0%, #38bdf8 55%, #2563eb 100%)',
  typeColors: {
    Hunter: '#fde047', // sun yellow
    Ranger: '#f8fafc', // near-white silver
    Force: '#bae6fd', // pale sky
  },
  ambientGlowAlpha: '40',
  eyebrowColor: '#1e3a8a',
  titleColor: '#ffffff',
  rightSecondaryColor: '#e0f2fe',
  headerBorderColor: 'rgba(253, 224, 71, 0.5)',
  headerShadowColor: 'rgba(253, 224, 71, 0.6)',
  unselectedOpacity: 0.55,
  unselectedFilter: 'saturate(0.85) brightness(1.05)',
  vertNameColor: '#ffffff',
  vertNameShadow: '0 1px 4px rgba(12, 30, 61, 0.85), 0 0 8px rgba(12, 30, 61, 0.5)',
  panelGradient:
    'linear-gradient(180deg, transparent 0%, rgba(255, 255, 255, 0.7) 35%, rgba(255, 255, 255, 0.95) 100%)',
  expandedNameColor: '#172554',
  expandedNameShadowAlpha: '66',
  statLabelColor: '#1e3a8a',
  statBarTrackColor: 'rgba(30, 58, 138, 0.2)',
  statValueColor: '#172554',
  statBarShadowAlpha: 'aa',
  bonusBgAlpha: '44',
  bonusTextColor: '#172554',
  footerColor: 'rgba(255, 255, 255, 0.85)',
  footerBorderColor: 'rgba(253, 224, 71, 0.45)',
  footerAccentColor: '#fde047',
  confirmButtonBg: '#fde047',
  confirmButtonText: '#172554',
  confirmButtonBorder: 'transparent',
  confirmButtonShadow: '0 0 12px rgba(253, 224, 71, 0.65)',
  scanlinesPattern: null,
  topAccentBar: null,
  topAccentBarHeight: 0,
  headerBg: 'transparent',
  titleItalic: false,
  titleShadow: 'none',
  footerBg: 'transparent',
};

// PSZ C: steel + sun. Charcoal / slate background, silver type for Ranger,
// gold for Hunter, sky for Force. White text, gold highlights.
export const STEEL_SLATS_PALETTE: SlatsPalette = {
  id: 'steel',
  rootBg: 'linear-gradient(180deg, #64748b 0%, #475569 45%, #1e293b 100%)',
  typeColors: {
    Hunter: '#fbbf24', // warm yellow
    Ranger: '#cbd5e1', // silver
    Force: '#7dd3fc', // sky
  },
  ambientGlowAlpha: '33',
  eyebrowColor: '#7dd3fc',
  titleColor: '#ffffff',
  rightSecondaryColor: '#cbd5e1',
  headerBorderColor: 'rgba(253, 224, 71, 0.28)',
  headerShadowColor: 'rgba(253, 224, 71, 0.4)',
  unselectedOpacity: 0.4,
  unselectedFilter: 'grayscale(0.3) brightness(0.9)',
  vertNameColor: '#f1f5f9',
  vertNameShadow: '0 1px 4px rgba(0,0,0,0.85)',
  panelGradient:
    'linear-gradient(180deg, transparent 0%, rgba(15, 23, 42, 0.72) 35%, rgba(15, 23, 42, 0.95) 100%)',
  expandedNameColor: '#ffffff',
  expandedNameShadowAlpha: '88',
  statLabelColor: '#cbd5e1',
  statBarTrackColor: 'rgba(255,255,255,0.1)',
  statValueColor: '#ffffff',
  statBarShadowAlpha: 'aa',
  bonusBgAlpha: '2c',
  bonusTextColor: '#e2e8f0',
  footerColor: 'rgba(203, 213, 225, 0.75)',
  footerBorderColor: 'rgba(253, 224, 71, 0.2)',
  footerAccentColor: '#fde047',
  confirmButtonBg: '#fde047',
  confirmButtonText: '#1e293b',
  confirmButtonBorder: 'transparent',
  confirmButtonShadow: '0 0 10px rgba(253, 224, 71, 0.5)',
  scanlinesPattern: null,
  topAccentBar: null,
  topAccentBarHeight: 0,
  headerBg: 'transparent',
  titleItalic: false,
  titleShadow: 'none',
  footerBg: 'transparent',
};

// PSZ D: closest to the in-game PSZ menu look. Pulls scanlines + colour values
// directly from web/src/storybook/MenuDesign.tsx and the reference layouts at
// web/public/menu-design/character_select_*.png:
//   bgLight        #a8cce8 — pale icy blue
//   bgDark         #2a3448 — dark navy used for title bars + panels
//   selectedGrad   #f0a020 → #f8c840 — orange/yellow CTA
//   separator      #7aa0c0 — gray-blue list separator
//   scanlines      4px repeating-linear-gradient with rgba(120,160,200,0.08)
export const PSZ_SLATS_PALETTE: SlatsPalette = {
  id: 'psz',
  rootBg: 'linear-gradient(180deg, #cce0f0 0%, #a8cce8 55%, #c8dcea 100%)',
  typeColors: {
    Hunter: '#f0a020', // gold, matches selectedGradient start
    Ranger: '#7aa0c0', // separator gray-blue
    Force: '#2a3448', // bgDark navy
  },
  ambientGlowAlpha: '20',
  eyebrowColor: '#5a7896',
  titleColor: '#f8c840', // gold-yellow title, italic, on navy header
  rightSecondaryColor: '#c8d8e8',
  headerBorderColor: 'transparent', // accent bar replaces the separator
  headerShadowColor: 'transparent',
  unselectedOpacity: 0.55,
  unselectedFilter: 'saturate(0.9) brightness(0.98)',
  vertNameColor: '#ffffff',
  vertNameShadow: '0 1px 0 rgba(42, 52, 72, 1), 1px 1px 2px rgba(42, 52, 72, 0.85)',
  // Dark navy panel (bgDarker→bgDark) — matches PSZ menu list items.
  panelGradient:
    'linear-gradient(180deg, transparent 0%, rgba(30, 40, 56, 0.6) 28%, rgba(30, 40, 56, 0.95) 100%)',
  expandedNameColor: '#ffffff',
  expandedNameShadowAlpha: '88',
  statLabelColor: '#a8c0d0',
  statBarTrackColor: 'rgba(122, 160, 192, 0.28)',
  statValueColor: '#ffffff',
  statBarShadowAlpha: 'aa',
  bonusBgAlpha: '2a',
  bonusTextColor: '#d8e4f0',
  footerColor: '#3a4a5a',
  footerBorderColor: 'transparent',
  footerAccentColor: '#f0a020',
  confirmButtonBg: '#f0a020',
  confirmButtonText: '#1a1a2a',
  confirmButtonBorder: '#c88010',
  confirmButtonShadow: '0 2px 0 rgba(200, 128, 16, 0.7), 0 0 14px rgba(240, 160, 32, 0.45)',
  // PSZ menu chrome
  scanlinesPattern: `repeating-linear-gradient(
    0deg,
    transparent,
    transparent 2px,
    rgba(120, 160, 200, 0.10) 2px,
    rgba(120, 160, 200, 0.10) 4px
  )`,
  topAccentBar:
    'linear-gradient(180deg, #f8c840 0%, #f0a020 55%, #c88010 100%)',
  topAccentBarHeight: 12,
  headerBg: 'linear-gradient(180deg, #2a3448 0%, #1e2838 100%)',
  titleItalic: true,
  titleShadow: '1px 1px 0 rgba(0,0,0,0.55), 0 0 12px rgba(240, 160, 32, 0.4)',
  footerBg: 'rgba(255, 255, 255, 0.65)',
};

export const SLATS_PALETTES = {
  dark: DARK_SLATS_PALETTE,
  light: LIGHT_SLATS_PALETTE,
  sky: SKY_SLATS_PALETTE,
  steel: STEEL_SLATS_PALETTE,
  psz: PSZ_SLATS_PALETTE,
} as const;
