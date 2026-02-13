shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform vec3 uv_scale = vec3(1.0, 1.0, 1.0);
uniform vec3 uv_offset = vec3(0.0, 0.0, 0.0);
uniform vec2 uv_scroll = vec2(0.0, 0.0);

void fragment() {
	vec2 uv = UV * uv_scale.xy + uv_offset.xy + uv_scroll * TIME;
	uv = fract(uv);
	vec4 tex = texture(albedo_texture, uv);
	ALBEDO = tex.rgb * COLOR.rgb * albedo_color.rgb;
	ALPHA = tex.a * albedo_color.a;
}
