shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

varying vec4 star_color;
varying float sparkle;
varying float phase;

void vertex() {
	star_color = COLOR;
	sparkle = INSTANCE_CUSTOM.x;
	phase = INSTANCE_CUSTOM.y * 6.283185;
	float pulse = 0.5 + 0.5 * sin(TIME * 2.5 + phase);
	float size = mix(1.0, 0.375 + 0.625 * pulse, sparkle);
	// Billboard without losing each MultiMesh instance's size.
	mat4 facing = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	facing[0].xyz *= length(MODEL_MATRIX[0].xyz);
	facing[1].xyz *= length(MODEL_MATRIX[1].xyz);
	facing[2].xyz *= length(MODEL_MATRIX[2].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * facing;
	VERTEX.xy *= size;
}

void fragment() {
	float radius = length(UV - vec2(0.5));
	float soft_disc = 1.0 - smoothstep(0.0, 0.5, radius);
	float pulse = 0.5 + 0.5 * sin(TIME * 2.5 + phase);
	ALBEDO = star_color.rgb;
	ALPHA = soft_disc * star_color.a * mix(1.0, 0.2 + 0.8 * pulse, sparkle);
}
