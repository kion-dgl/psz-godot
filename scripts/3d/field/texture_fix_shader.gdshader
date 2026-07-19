shader_type spatial;
// cull_disabled: the stage materials this shader replaces are authored
// double-sided (glTF doubleSided → CULL_DISABLED), so culling back faces here
// dropped the far side of double-sided geometry — e.g. the back of the Dairon
// quest counter read as "missing triangles" (#537). Matches every sibling fix
// shader (waterfall, uv_dressing, mirror_repeat_alpha), which are all cull_disabled.
render_mode cull_disabled, vertex_lighting;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform vec3 uv_scale = vec3(1.0, 1.0, 1.0);
uniform vec3 uv_offset = vec3(0.0, 0.0, 0.0);
// Wrap mode per axis: 0 = repeat, 1 = mirror, 2 = clamp
uniform int wrap_s = 0;
uniform int wrap_t = 0;
uniform vec2 uv_scroll = vec2(0.0, 0.0);
// 0 = alpha scissor (opaque), 1 = alpha blend (transparent)
uniform int alpha_mode = 0;

float apply_wrap(float coord, int mode, float half_texel) {
	if (mode == 2) {
		// Clamp
		return clamp(coord, 0.0, 1.0);
	} else if (mode == 1) {
		// Mirror: 0→1 normal, 1→2 flipped, 2→3 normal, etc.
		float t = mod(coord, 2.0);
		float r = t <= 1.0 ? t : 2.0 - t;
		// Half-texel inset at the fold so linear filtering doesn't bleed across
		// the repeat wrap and paint a 1px seam (matches hardware MIRRORED_REPEAT,
		// which doubles the edge texel at the fold).
		return clamp(r, half_texel, 1.0 - half_texel);
	}
	// Repeat (default)
	return fract(coord);
}

void fragment() {
	vec2 uv = UV * uv_scale.xy + uv_offset.xy + uv_scroll * TIME;
	vec2 half_texel = 0.5 / vec2(textureSize(albedo_texture, 0));
	uv.x = apply_wrap(uv.x, wrap_s, half_texel.x);
	uv.y = apply_wrap(uv.y, wrap_t, half_texel.y);
	vec4 tex = texture(albedo_texture, uv);
	// Use vertex color for RGB tint only — Three.js ignores vertex alpha for
	// transparency, and GLB meshes often have COLOR.a=0 which would hide geometry.
	ALBEDO = tex.rgb * COLOR.rgb * albedo_color.rgb;
	ALPHA = tex.a * albedo_color.a;
	if (alpha_mode == 0) {
		ALPHA_SCISSOR_THRESHOLD = 0.1;
	}
}
