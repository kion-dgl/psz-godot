shader_type spatial;
// Double-sided: the animated warp surface must be visible from both sides.
render_mode cull_disabled;

#include "res://scripts/3d/shaders/mirror_repeat.gdshaderinc"

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec2 uv_scale = vec2(1.0, 1.0);
uniform vec2 uv_offset = vec2(0.0, 0.0);
uniform bool mirror_x = true;
uniform bool mirror_y = true;

void fragment() {
	vec2 uv = UV * uv_scale + uv_offset;
	vec2 half_texel = 0.5 / vec2(textureSize(albedo_texture, 0));
	uv = mirror_uv(uv, half_texel, mirror_x, mirror_y);
	vec4 tex = texture(albedo_texture, uv);
	ALBEDO = tex.rgb;
	ALPHA = tex.a;
}
