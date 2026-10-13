shader_type spatial;
render_mode cull_disabled, specular_disabled;

uniform sampler2D albedo_texture : source_color, filter_nearest, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float skyline[128];

void fragment() {
	// The panorama repeats horizontally, but its top must never wrap to the
	// bottom row. Match the source pixel silhouette and remove the sky fringe.
	vec2 uv = vec2(fract(UV.x), clamp(UV.y, 0.0, 1.0));
	int column = clamp(int(floor(uv.x * 128.0)), 0, 127);
	if (uv.y * 128.0 < skyline[column] + 1.0) {
		discard;
	}
	vec4 tex = texture(albedo_texture, vec2(uv.x, min(uv.y, 127.5 / 128.0)));
	ALBEDO = tex.rgb * COLOR.rgb * albedo_color.rgb;
	ROUGHNESS = 1.0;
}

// The artwork already contains the cliffs' relief and directional shading.
// Environment ambient color/energy provides time and weather adaptation;
// don't relight the flat panorama cards with direct lights.
void light() {}
