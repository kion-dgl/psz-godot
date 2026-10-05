extends RefCounted
## Shared E sky. Small radiance map and two cloud samples keep the cost modest.
const SKY_SHADER := preload("res://scripts/3d/field/makara_sky.gdshader")
static var _clouds: NoiseTexture2D


static func apply(env: Environment, base: ProceduralSkyMaterial,
		light: DirectionalLight3D, slot: Dictionary) -> void:
	if slot.get("sky_style", "") != "makara_clouds":
		if env.sky.sky_material is ShaderMaterial \
				and env.sky.sky_material.shader == SKY_SHADER:
			env.sky.sky_material = base
		return
	if _clouds == null:
		var noise := FastNoiseLite.new()
		noise.seed = 650
		noise.frequency = 0.012
		noise.fractal_octaves = 4
		_clouds = NoiseTexture2D.new()
		_clouds.width = 512
		_clouds.height = 512
		_clouds.seamless = true
		_clouds.noise = noise
	var material := ShaderMaterial.new()
	material.shader = SKY_SHADER
	material.set_shader_parameter("cloud_noise", _clouds)
	material.set_shader_parameter("sun_direction", light.global_transform.basis.z.normalized())
	material.set_shader_parameter("night_amount", 1.0 if slot.get("sky_night", false) else 0.0)
	material.set_shader_parameter("rain_amount", 1.0 if slot.get("sky_rain", false) else 0.0)
	material.set_shader_parameter("twilight_amount", 1.0 if slot.get("sky_twilight", false) else 0.0)
	env.sky.sky_material = material
	env.sky.radiance_size = Sky.RADIANCE_SIZE_32
