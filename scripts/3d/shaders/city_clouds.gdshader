shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

uniform sampler2D cloud_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 cloud_color : source_color = vec4(1.0);
// Match the Three.js scrollX tuning: one texture repeat per 10 seconds.
// Sky and shadow cards share UV motion; vertex colors make them light or dark.
uniform vec2 uv_scroll = vec2(-0.1, 0.0);

void fragment() {
	vec2 uv = UV + TIME * uv_scroll;
	vec4 cloud = texture(cloud_texture, uv);
	ALBEDO = cloud.rgb * COLOR.rgb * cloud_color.rgb;
	ALPHA = cloud.a * COLOR.a * cloud_color.a;
}
