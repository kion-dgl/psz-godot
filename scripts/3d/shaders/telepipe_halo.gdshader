shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

void fragment() {
	float radius = length((UV - vec2(0.5)) * 2.65);
	float ring = exp(-pow((radius - 0.88) / 0.055, 2.0));
	float halo = exp(-pow((radius - 0.88) / 0.23, 2.0));
	float pulse = 0.93 + 0.07 * sin(TIME * 3.2);
	ALBEDO = mix(vec3(0.03, 0.6, 1.0), vec3(0.65, 1.0, 1.0), ring);
	ALPHA = (ring * 0.75 + halo * 0.20) * pulse;
}
