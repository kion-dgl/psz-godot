class_name DebugConfig
## Global debug toggle states. Checked by the field controller each frame.

static var show_floor_collision := false
static var show_gate_dots := false
static var show_time_room := false
static var show_hitboxes := false
static var show_combo_timing := false  # Show rhythm combo window indicator
static var profile_frames := false  # Log slow frame breakdowns to console
static var show_player_position := false
# Testers: reveal the full area map (fog of war off) so a grid's layout is
# visible without exploring — spec /states/area-map.
static var reveal_map := false  # Top-of-screen overlay with player.global_position
# Bypass equip legality so ANY weapon can be equipped — for verifying weapon
# models/orientation regardless of class. Defaults on when the weapon-test flag
# is set (pairs with storage's PSZ_DEBUG_WEAPONS seed). Toggle in System menu.
static var equip_all := OS.has_environment("PSZ_DEBUG_WEAPONS")
# Gate the verbose [ValleyField]/[FieldElements]/[CellObjects] field-controller
# logs (see #215-E). Off in normal/release play so logcat isn't spammed; on
# automatically during autopilot/regression runs so matrix failures stay
# diagnosable.
static var verbose_field := OS.has_environment("PSZ_AUTOPILOT")
