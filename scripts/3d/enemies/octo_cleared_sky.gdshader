shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled, blend_mix, depth_draw_never;
uniform sampler2D cloud_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform float clear_amount = 0.0;
varying float world_height;
void vertex() {
	world_height = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}
void fragment() {
	vec3 cloud = texture(cloud_texture, UV).rgb * COLOR.rgb;
	// The sky mesh also carries the water: keep its low surfaces dark.
	ALPHA = clear_amount;
	ALBEDO = mix(cloud, vec3(0.52, 0.57, 0.63), 0.65 * smoothstep(0.0, 8.0, world_height));
}
