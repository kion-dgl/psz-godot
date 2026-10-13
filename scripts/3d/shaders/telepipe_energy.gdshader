shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// CylinderMesh packs its side into the upper half of the UV atlas.
// All angular frequencies are
// integers so the animated pattern joins cleanly at the cylinder's UV seam.
void fragment() {
	float h = 1.0 - UV.y * 2.0;
	float angle = UV.x * 6.2831853;
	float t = TIME;
	float pulse = 0.94 + 0.06 * sin(t * 3.2);
	float waviness = sin(angle * 7.0 + t * 2.0) * 0.035
		+ sin(angle * 13.0 - t * 2.8) * 0.025;
	float skirt = 1.0 - smoothstep(0.16 + waviness, 0.40 + waviness, h);
	float rim = 1.0 - smoothstep(0.045, 0.17, h);

	// Uneven narrow tongues, with taller blue tips above the cyan skirt.
	float lanes = pow(max(0.0, sin(angle * 19.0 + sin(angle * 5.0) * 1.7)), 12.0);
	float tip = 0.43 + 0.37 * (0.5 + 0.5 * sin(angle * 11.0 + t * 2.2));
	float tongues = lanes * (1.0 - smoothstep(tip - 0.20, tip, h));
	float fine_lanes = pow(max(0.0, sin(angle * 31.0 - t * 0.35)), 30.0);
	float travel = fract(h * 1.4 - t * 0.8 + sin(angle * 9.0));
	float sparks = fine_lanes * smoothstep(0.65, 0.85, travel)
		* (1.0 - smoothstep(0.90, 1.0, travel))
		* (1.0 - smoothstep(0.65, 0.98, h));
	float strength = max(skirt * 0.70, tongues * 0.8) + rim * 0.55 + sparks * 0.7;
	vec3 color = mix(vec3(0.08, 0.34, 1.0), vec3(0.15, 0.9, 1.0), skirt);
	color = mix(color, vec3(0.8, 1.0, 1.0), rim);
	ALBEDO = color;
	ALPHA = clamp(strength * pulse, 0.0, 1.0);
}
