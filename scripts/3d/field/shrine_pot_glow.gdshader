shader_type spatial;
render_mode cull_disabled;

uniform sampler2D albedo_texture : source_color, filter_nearest_mipmap, repeat_enable;
uniform vec2 uv_scale = vec2(2.0, 1.0);
uniform vec2 uv_offset = vec2(0.0);
uniform bool mirror_s = true;
uniform bool mirror_t = false;
uniform float band_height = 0.95;
uniform float band_width = 0.22;
uniform float glow_strength = 0.36;
// Local visibility floor for old stone; this never illuminates the room.
uniform float pillar_fill = 0.065;
// Linear RGB, matching the approved Three.js material study.
uniform vec3 glow_color = vec3(0.025, 0.42, 0.34);
varying float vessel_height;

void vertex() {
	vessel_height = VERTEX.y;
}

float wrap_coord(float value, bool mirror_axis) {
	float t = mod(value, 2.0);
	return mirror_axis ? (t <= 1.0 ? t : 2.0 - t) : fract(value);
}

void fragment() {
	vec2 uv = UV * uv_scale + uv_offset;
	uv = vec2(wrap_coord(uv.x, mirror_s), wrap_coord(uv.y, mirror_t));
	vec4 tex = texture(albedo_texture, uv);
	if (tex.a < 0.1) { discard; }
	ALBEDO = tex.rgb * COLOR.rgb;
	ROUGHNESS = 0.95;
	float band = exp(-2.0 * pow((vessel_height - band_height) / band_width, 2.0));
	float vessel = smoothstep(0.44, 0.75, vessel_height) * (1.0 - smoothstep(1.5, 2.2, vessel_height));
	float grain = 0.4 + 0.6 * clamp(dot(ALBEDO, vec3(0.333)) * 2.0, 0.0, 1.0);
	EMISSION = tex.rgb * vec3(0.55, 0.65, 0.68) * pillar_fill + glow_color * glow_strength * (band + vessel * 0.12) * grain;
}
