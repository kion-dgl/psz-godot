shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D atlas : source_color, filter_nearest, repeat_enable;
void fragment() {
	// Eight authored 32-pixel rows; keep each person's column and phase.
	vec2 uv = UV + vec2(0.0, mod(floor(TIME * 6.0), 8.0) / 8.0);
	vec4 tex = texture(atlas, uv);
	ALBEDO = tex.rgb * COLOR.rgb;
	ALPHA = tex.a * COLOR.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
