shader_type spatial;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec2 uv_scale = vec2(1.0, 1.0);
uniform vec2 uv_offset = vec2(0.0, 0.0);
uniform bool mirror_x = true;
uniform bool mirror_y = true;

float mirror_coord(float c) {
	float m = mod(c, 2.0);
	return m < 1.0 ? m : 2.0 - m;
}

void fragment() {
	vec2 uv = UV * uv_scale + uv_offset;
	if (mirror_x) uv.x = mirror_coord(uv.x);
	if (mirror_y) uv.y = mirror_coord(uv.y);
	vec4 tex = texture(albedo_texture, uv);
	ALBEDO = tex.rgb;
	ALPHA = tex.a;
}
