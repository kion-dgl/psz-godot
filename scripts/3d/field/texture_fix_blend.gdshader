shader_type spatial;
// Baked, double-sided translucent surfaces: retain faint alpha without a cutoff.
render_mode unshaded, blend_mix, cull_disabled;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform vec3 uv_scale = vec3(1.0);
uniform vec3 uv_offset = vec3(0.0);
uniform vec2 uv_scroll = vec2(0.0);
uniform int wrap_s = 0;
uniform int wrap_t = 0;
uniform bool use_vertex_color = true;

float wrap_coord(float coord, int mode, float half_texel) {
	if (mode == 2) { return clamp(coord, 0.0, 1.0); }
	if (mode == 1) {
		float t = mod(coord, 2.0);
		return clamp(t <= 1.0 ? t : 2.0 - t, half_texel, 1.0 - half_texel);
	}
	return fract(coord);
}

void fragment() {
	vec2 continuous_uv = UV * uv_scale.xy + uv_offset.xy + uv_scroll * TIME;
	vec2 half_texel = 0.5 / vec2(textureSize(albedo_texture, 0));
	vec2 uv = vec2(wrap_coord(continuous_uv.x, wrap_s, half_texel.x),
		wrap_coord(continuous_uv.y, wrap_t, half_texel.y));
	vec4 tex = textureGrad(albedo_texture, uv, dFdx(continuous_uv), dFdy(continuous_uv));
	ALBEDO = tex.rgb * albedo_color.rgb * (use_vertex_color ? COLOR.rgb : vec3(1.0));
	// Vertex alpha is not part of the original baked transparency.
	ALPHA = tex.a * albedo_color.a;
}
