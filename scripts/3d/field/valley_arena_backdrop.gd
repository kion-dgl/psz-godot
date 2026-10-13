extends RefCounted
## Preserve the authored canyon silhouettes while replacing only their baked sky.
## These per-column skyline coordinates are pinned to the two 128px source
## panoramas. A silhouette mask avoids chroma-key holes in blue shadowed rock.
const CLOUD_SKY := preload("res://scripts/3d/field/makara_sky.gd")
const CANYON_SHADER := preload("res://scripts/3d/field/valley_canyon.gdshader")
const SKYLINE_VIEW2 := [
	18,18,19,20,23,23,23,23,22,22,19,18,17,17,17,17,
	16,16,16,16,17,17,18,20,19,20,24,26,26,26,25,26,
	27,26,31,36,36,36,38,39,40,40,41,44,45,47,49,50,
	50,52,52,52,52,56,57,58,57,56,55,55,56,57,59,65,
	66,67,67,66,66,64,63,62,62,62,61,58,58,57,58,56,
	56,56,58,60,61,62,61,60,57,55,52,51,50,50,50,50,
	50,50,50,44,38,37,34,34,36,31,27,21,20,20,20,20,
	19,18,16,15,16,15,15,16,20,19,19,17,16,16,16,16,
]
const SKYLINE_VIEW3 := [
	18,18,19,20,23,23,23,23,22,22,19,18,17,17,17,17,
	16,16,16,16,17,17,18,20,20,20,20,19,19,19,19,20,
	20,20,19,18,18,18,20,20,20,15,8,6,6,7,8,5,
	4,2,1,4,4,1,1,4,5,5,4,2,2,4,4,3,
	3,4,5,8,8,8,8,8,7,5,3,3,4,4,4,4,
	2,2,1,2,2,3,4,4,5,7,10,12,12,12,12,12,
	11,12,19,20,20,20,20,20,22,22,22,21,20,20,20,20,
	19,18,16,15,16,15,15,16,20,19,19,17,16,16,16,16,
]


static func prepare_stage(root: Node3D, stage_id: String) -> void:
	if stage_id != "s01z_na1" or root.has_meta("mountain_backdrop"):
		return
	MeshUtils.split_mesh_surfaces(root)
	for node in MeshUtils.collect_mesh_instances(root, []):
		var mi := node as MeshInstance3D
		if mi.is_queued_for_deletion() or mi.mesh == null:
			continue
		var source := mi.mesh.surface_get_material(0) as StandardMaterial3D
		if source == null:
			continue
		if source.resource_name == "2_kemu":
			# Remove the old edge-smoke card, including its wrapped brown seam.
			mi.visible = false
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif source.resource_name in ["0_v", "0_vi2"]:
			var material := ShaderMaterial.new()
			material.shader = CANYON_SHADER
			material.set_shader_parameter("albedo_texture", source.albedo_texture)
			material.set_shader_parameter("albedo_color", source.albedo_color)
			material.set_shader_parameter("skyline", PackedFloat32Array(
				SKYLINE_VIEW3 if source.resource_name == "0_v" else SKYLINE_VIEW2))
			mi.set_surface_override_material(0, material)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.set_meta("mountain_backdrop", true)


static func apply_sky(env: Environment, base: ProceduralSkyMaterial,
		light: DirectionalLight3D, slot: Dictionary, hour: float, weather: String) -> void:
	if slot.get("sky_style", "") != "valley_mountains":
		return
	var night := 1.0 - smoothstep(5.0, 7.0, hour) + smoothstep(19.0, 21.0, hour)
	var twilight := maxf(1.0 - absf(hour - 6.0), 1.0 - absf(hour - 19.0) / 2.0)
	var rainy := weather in ["rain", "drizzle", "makara_rain"]
	CLOUD_SKY.apply(env, base, light, {"sky_style": "makara_clouds"})
	var material := env.sky.sky_material as ShaderMaterial
	material.set_shader_parameter("night_amount", clampf(night, 0.0, 1.0))
	material.set_shader_parameter("twilight_amount", clampf(twilight, 0.0, 1.0))
	material.set_shader_parameter("rain_amount", 1.0 if rainy else 0.0)
	if rainy:
		light.light_energy *= 0.35
		env.ambient_light_energy *= 0.8
