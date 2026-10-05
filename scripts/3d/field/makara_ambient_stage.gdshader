shader_type spatial;
render_mode cull_disabled, specular_disabled;
uniform sampler2D albedo_texture : source_color, filter_nearest, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform vec3 uv_scale = vec3(1.0);
uniform vec3 uv_offset = vec3(0.0);
uniform bool use_vertex_color = true;
void fragment() {
	vec4 tex = texture(albedo_texture, UV * uv_scale.xy + uv_offset.xy);
	ALBEDO = tex.rgb * albedo_color.rgb * (use_vertex_color ? COLOR.rgb : vec3(1.0));
	ALPHA = tex.a * albedo_color.a;
	ALPHA_SCISSOR_THRESHOLD = 0.1;
	ROUGHNESS = 1.0;
}
// Keep Environment ambient illumination; reject all direct light on stage art.
void light() {}
