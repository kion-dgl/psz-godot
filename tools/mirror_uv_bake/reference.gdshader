shader_type spatial;
render_mode cull_disabled;

// Reference only: same half-texel fold recipe used by the game. The candidate
// has no ShaderMaterial and uses the native Godot material compiler unchanged.
uniform sampler2D albedo_texture : source_color, filter_linear, repeat_enable;
uniform vec2 uv_scale = vec2(1.0);
uniform vec2 uv_offset = vec2(0.0);
uniform bool mirror_x = true;
uniform bool mirror_y = false;

float fold_coord(float coordinate, float half_texel) {
	return clamp(1.0 - abs(mod(coordinate, 2.0) - 1.0), half_texel, 1.0 - half_texel);
}

void fragment() {
	vec2 uv = UV * uv_scale + uv_offset;
	vec2 half_texel = 0.5 / vec2(textureSize(albedo_texture, 0));
	if (mirror_x) uv.x = fold_coord(uv.x, half_texel.x);
	if (mirror_y) uv.y = fold_coord(uv.y, half_texel.y);
	ALBEDO = texture(albedo_texture, uv).rgb;
	ROUGHNESS = 0.85;
	METALLIC = 0.0;
	SPECULAR = 0.5;
}
