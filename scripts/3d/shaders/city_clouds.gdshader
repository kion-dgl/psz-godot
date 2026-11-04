shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
varying vec3 world_position;
float noise_hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float soft_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(noise_hash(i), noise_hash(i + vec2(1, 0)), f.x),
		mix(noise_hash(i + vec2(0, 1)), noise_hash(i + vec2(1, 1)), f.x), f.y);
}
void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX += NORMAL * 0.008;
}
void fragment() {
	vec2 p = world_position.xz * 0.055 + TIME * vec2(0.012, -0.007);
	float cloud = soft_noise(p) * 0.7 + soft_noise(p * 2.0) * 0.3;
	ALBEDO = vec3(0.16, 0.20, 0.28);
	ALPHA = smoothstep(0.32, 0.72, cloud) * 0.22;
}
