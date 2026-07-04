shader_type spatial;
// Double-sided: the animated warp surface must be visible from both sides.
render_mode cull_disabled;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec2 uv_scale = vec2(1.0, 1.0);
uniform vec2 uv_offset = vec2(0.0, 0.0);
uniform bool mirror_x = true;
uniform bool mirror_y = true;

float mirror_coord(float c, float half_texel) {
	float m = mod(c, 2.0);
	float r = m < 1.0 ? m : 2.0 - m;
	// Half-texel inset at the mirror fold: without it, linear filtering samples
	// across the repeat wrap right at the seam and paints a 1px line of the
	// opposite edge (the "off by a pixel" seam). Clamping to texel-center range
	// makes the fold double the edge texel, like hardware MIRRORED_REPEAT.
	return clamp(r, half_texel, 1.0 - half_texel);
}

void fragment() {
	vec2 uv = UV * uv_scale + uv_offset;
	vec2 half_texel = 0.5 / vec2(textureSize(albedo_texture, 0));
	if (mirror_x) uv.x = mirror_coord(uv.x, half_texel.x);
	if (mirror_y) uv.y = mirror_coord(uv.y, half_texel.y);
	vec4 tex = texture(albedo_texture, uv);
	ALBEDO = tex.rgb;
	ALPHA = tex.a;
}
