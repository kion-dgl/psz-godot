shader_type spatial;
render_mode unshaded, cull_back;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform vec3 uv_scale = vec3(1.0, 1.0, 1.0);
uniform vec3 uv_offset = vec3(0.0, 0.0, 0.0);
// Wrap mode per axis: 0 = repeat, 1 = mirror, 2 = clamp
uniform int wrap_s = 0;
uniform int wrap_t = 0;

float apply_wrap(float coord, int mode) {
	if (mode == 2) {
		// Clamp
		return clamp(coord, 0.0, 1.0);
	} else if (mode == 1) {
		// Mirror: 0→1 normal, 1→2 flipped, 2→3 normal, etc.
		float t = mod(coord, 2.0);
		return t <= 1.0 ? t : 2.0 - t;
	}
	// Repeat (default)
	return fract(coord);
}

void fragment() {
	vec2 uv = UV * uv_scale.xy + uv_offset.xy;
	uv.x = apply_wrap(uv.x, wrap_s);
	uv.y = apply_wrap(uv.y, wrap_t);
	vec4 tex = texture(albedo_texture, uv);
	ALBEDO = tex.rgb * COLOR.rgb * albedo_color.rgb;
	ALPHA = tex.a * COLOR.a * albedo_color.a;
}
