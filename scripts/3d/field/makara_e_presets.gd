extends RefCounted
## Shared E preview recipes; gameplay defaults to day. Lab keys select a recipe.
const NAMES := ["Day", "Twilight", "Night", "Rain day", "Rain night"]
static var selected := 0


static func resolve() -> Dictionary:
	var index := selected
	var override := OS.get_environment("PSZ_MAKARA_E_PRESET")
	if not override.is_empty():
		index = clampi(int(override), 0, 4)
	var night := index in [2, 4]
	var rain := index in [3, 4]
	var twilight := index == 1
	return {
		"preset_name": NAMES[index],
		"hour": 22.0 if night else (18.5 if twilight else 10.0),
		"sun_energy": (0.18 if rain else 0.28) if night else (0.28 if rain or twilight else 0.65),
		"sun_color": Color(0.5, 0.65, 1.0) if night else (Color(1.0, 0.58, 0.32) if twilight else Color(1.0, 0.92, 0.8)),
		"sun_pitch": -40.0 if night else (-18.0 if twilight else -45.0),
		"sun_origin": [-25.0, 30.0, 40.0],
		"ambient_energy": 0.16 if night else (0.28 if twilight else 0.5),
		"ambient_color": Color(0.48, 0.58, 0.8) if night else Color(0.75, 0.8, 0.9),
		"moon_energy": 0.0,
		"sun_shadows": true,
		"shadow_catcher": false,
		"lit_surfaces": ["*"],
		"weather": "makara_rain" if rain else "",
		"sky_night": night,
		"sky_rain": rain,
		"sky_twilight": twilight,
	}
