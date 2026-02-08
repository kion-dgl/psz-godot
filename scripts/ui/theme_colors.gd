class_name ThemeColors
## RPG UI color palette — PSZ-inspired dark blue/purple with cyan accents.

# Backgrounds
const BG_DARK := Color(0.039, 0.055, 0.102)          # #0a0e1a — deep navy
const BG_PANEL := Color(0.078, 0.118, 0.208)          # #141e35 — panel fill
const BG_PANEL_LIGHT := Color(0.118, 0.176, 0.302)    # #1e2d4d — hover/selected

# Borders
const BORDER := Color(0.165, 0.361, 0.541)            # #2a5c8a — panel borders
const BORDER_ACCENT := Color(0.251, 0.627, 0.816)     # #40a0d0 — highlighted

# Text
const TEXT_PRIMARY := Color(0.878, 0.910, 0.941)       # #e0e8f0 — body text
const TEXT_SECONDARY := Color(0.502, 0.565, 0.659)     # #8090a8 — muted/hint
const TEXT_HIGHLIGHT := Color(1.0, 0.816, 0.251)       # #ffd040 — gold/selected
const TEXT_DISABLED := Color(0.251, 0.282, 0.345)      # #404858 — grayed out

# Bars
const HP_BAR := Color(0.188, 0.753, 0.314)            # #30c050 — green
const HP_BAR_BG := Color(0.102, 0.188, 0.125)         # #1a3020 — dark green
const PP_BAR := Color(0.251, 0.502, 0.878)            # #4080e0 — blue
const PP_BAR_BG := Color(0.102, 0.125, 0.251)         # #1a2040 — dark blue
const EXP_BAR := Color(0.502, 0.314, 0.878)           # #8050e0 — purple
const EXP_BAR_BG := Color(0.125, 0.102, 0.251)        # #201a40 — dark purple

# Status
const DANGER := Color(0.878, 0.251, 0.251)            # #e04040 — low HP/errors
const SUCCESS := Color(0.251, 0.753, 0.439)           # #40c070 — confirmations
const WARNING := Color(0.878, 0.627, 0.125)           # #e0a020 — cautions
const MESETA_GOLD := Color(0.941, 0.753, 0.188)       # #f0c030 — meseta amounts

# Equip restriction colors
const RESTRICT_CLASS := Color(0.6, 0.2, 0.2)          # dim red — wrong class
const RESTRICT_LEVEL := Color(0.7, 0.5, 0.15)         # dim orange — level too low
const RESTRICT_ID := Color(0.7, 0.3, 0.7)             # magenta — mismatched ID
const EQUIPPABLE := Color(0.4, 0.9, 0.5)              # green — can equip
const STAT_POSITIVE := Color(0.2, 1.0, 0.2)           # bright green — stat increase
const STAT_NEGATIVE := Color(1.0, 0.3, 0.3)           # bright red — stat decrease

# Category headers (reuse border accent)
const HEADER := Color(0.251, 0.627, 0.816)            # #40a0d0 — section headers
const COMPLETED := Color(0.5, 0.8, 0.5)               # soft green — cleared missions
