shader_type spatial;

#include "res://scripts/3d/shaders/mirror_repeat.gdshaderinc"

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec2 uv_scale = vec2(1.0, 1.0);
uniform vec2 uv_offset = vec2(0.0, 0.0);
uniform bool mirror_x = true;
uniform bool mirror_y = true;
uniform bool emission_enabled = false;
uniform vec3 emission_color : source_color = vec3(0.0);
uniform float emission_energy = 1.0;

void fragment() {
	vec2 uv = UV * uv_scale + uv_offset;
	vec2 half_texel = 0.5 / vec2(textureSize(albedo_texture, 0));
	uv = mirror_uv(uv, half_texel, mirror_x, mirror_y);
	vec4 tex = texture(albedo_texture, uv);
	ALBEDO = tex.rgb;
	if (emission_enabled) {
		EMISSION = emission_color * emission_energy;
	}
}
