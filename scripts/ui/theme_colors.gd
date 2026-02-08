class_name ThemeColors
## PSZ DS-faithful UI color palette — bright and airy, light blue with white menus.

# Backgrounds
const BG_LIGHT := Color(0.478, 0.722, 0.878)             # #7ab8e0 — sky blue main bg
const BG_GRADIENT_TOP := Color(0.353, 0.612, 0.816)       # #5a9cd0 — darker blue gradient top
const BG_GRADIENT_BOT := Color(0.627, 0.847, 0.941)       # #a0d8f0 — lighter blue gradient bot

# Header/Title bar
const HEADER_BAR := Color(0.165, 0.227, 0.353)            # #2a3a5a — dark steel blue title bg
const HEADER_TEXT := Color(1.0, 1.0, 1.0)                 # #ffffff — white title text

# Menu items
const MENU_BG := Color(0.941, 0.941, 0.941)               # #f0f0f0 — white/off-white row bg
const MENU_TEXT := Color(0.125, 0.125, 0.125)              # #202020 — near-black menu text
const MENU_SELECTED := Color(0.941, 0.627, 0.125)         # #f0a020 — yellow/orange selected bg
const MENU_SEL_TEXT := Color(0.125, 0.125, 0.125)          # #202020 — black text on selected

# Hint bar
const HINT_BAR := Color(0.102, 0.165, 0.251)              # #1a2a40 — dark navy hint bg
const HINT_TEXT := Color(0.816, 0.847, 0.878)              # #d0d8e0 — light gray hint text

# Legacy aliases — used by many screens for dynamic labels
const BG_DARK := Color(0.478, 0.722, 0.878)               # alias → BG_LIGHT (sky blue)
const BG_PANEL := Color(0.878, 0.910, 0.941)              # #e0e8f0 — light panel fill
const BG_PANEL_LIGHT := Color(0.941, 0.941, 0.941)        # #f0f0f0 — hover/selected panel

# Borders
const BORDER := Color(0.753, 0.816, 0.878)                # #c0d0e0 — subtle light border
const BORDER_ACCENT := Color(0.941, 0.627, 0.125)         # #f0a020 — highlighted (orange)

# Text
const TEXT_PRIMARY := Color(0.125, 0.125, 0.125)          # #202020 — near-black body text
const TEXT_SECONDARY := Color(0.400, 0.440, 0.500)        # #667080 — muted/hint
const TEXT_HIGHLIGHT := Color(0.878, 0.502, 0.063)        # #e08010 — orange/selected
const TEXT_DISABLED := Color(0.690, 0.710, 0.740)         # #b0b5bc — grayed out

# Bars
const HP_BAR := Color(0.188, 0.753, 0.314)                # #30c050 — green
const HP_BAR_BG := Color(0.102, 0.188, 0.125)             # #1a3020 — dark green
const PP_BAR := Color(0.251, 0.502, 0.878)                # #4080e0 — blue
const PP_BAR_BG := Color(0.102, 0.125, 0.251)             # #1a2040 — dark blue
const EXP_BAR := Color(0.502, 0.314, 0.878)               # #8050e0 — purple
const EXP_BAR_BG := Color(0.125, 0.102, 0.251)            # #201a40 — dark purple

# Status
const DANGER := Color(0.878, 0.251, 0.251)                # #e04040 — low HP/errors
const SUCCESS := Color(0.251, 0.753, 0.439)               # #40c070 — confirmations
const WARNING := Color(0.878, 0.627, 0.125)               # #e0a020 — cautions
const MESETA_GOLD := Color(0.878, 0.627, 0.063)           # #e0a010 — meseta amounts

# Equip restriction colors
const RESTRICT_CLASS := Color(0.7, 0.25, 0.25)            # red — wrong class
const RESTRICT_LEVEL := Color(0.8, 0.55, 0.15)            # orange — level too low
const RESTRICT_ID := Color(0.7, 0.3, 0.7)                 # magenta — mismatched ID
const EQUIPPABLE := Color(0.2, 0.65, 0.35)                # green — can equip
const STAT_POSITIVE := Color(0.1, 0.7, 0.1)               # green — stat increase
const STAT_NEGATIVE := Color(0.85, 0.2, 0.2)              # red — stat decrease

# Category headers
const HEADER := Color(0.165, 0.227, 0.353)                # #2a3a5a — section headers (dark steel)
const COMPLETED := Color(0.3, 0.65, 0.35)                 # green — cleared missions
