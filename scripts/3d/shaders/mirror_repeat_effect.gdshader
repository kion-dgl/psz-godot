shader_type spatial;
// Mirrored-repeat variant for EFFECT SPRITES (the o0c_* burst/effect archive):
// crossed quads carrying a tiny indexed-looking texture, meant to be drawn flat
// and unlit with a hard alpha cut — matching what the glTF declares (NEAREST
// filtering, alphaMode MASK, doubleSided).
//
// Split from mirror_repeat_alpha.gdshader because those three properties are
// shader-level, not uniforms: the filter is a sampler hint, and unshaded is a
// render_mode. The UV fold itself is shared via the include.
render_mode unshaded, cull_disabled;

#include "res://scripts/3d/shaders/mirror_repeat.gdshaderinc"

uniform sampler2D albedo_texture : source_color, filter_nearest, repeat_enable;
uniform vec2 uv_scale = vec2(1.0, 1.0);
uniform vec2 uv_offset = vec2(0.0, 0.0);
uniform bool mirror_x = true;
uniform bool mirror_y = true;
uniform float alpha_scissor = 0.5;

void fragment() {
	vec2 uv = UV * uv_scale + uv_offset;
	vec2 half_texel = 0.5 / vec2(textureSize(albedo_texture, 0));
	uv = mirror_uv(uv, half_texel, mirror_x, mirror_y);
	vec4 tex = texture(albedo_texture, uv);
	ALBEDO = tex.rgb;
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor;
}
