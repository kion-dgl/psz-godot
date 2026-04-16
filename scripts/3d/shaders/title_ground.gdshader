shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;

// Ported from web/src/title-screen/TitleScreen.tsx ground shader.
// Rock texture tiled + Lambert key light + beam point-light pool + fog.

uniform sampler2D rock_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float tiles = 24.0;

uniform float ambient_amount = 0.45;
uniform vec3 key_color : source_color = vec3(0.749, 0.815, 1.0);
uniform float key_intensity = 1.2;
uniform vec3 key_dir = vec3(0.25, 0.9, 0.35);

uniform vec3 beam_pos = vec3(0.0, -100.0, 0.0);
uniform vec3 beam_color : source_color = vec3(0.729, 0.863, 1.0);
uniform float beam_intensity = 3.2;
uniform float beam_radius = 110.0;

uniform float fog_near = 280.0;
uniform float fog_far = 820.0;
uniform vec3 fog_color : source_color = vec3(0.165, 0.094, 0.314);

varying vec3 v_world_pos;
varying vec3 v_world_normal;
varying float v_view_dist;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec4 mv = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	v_view_dist = -mv.z;
}

void fragment() {
	vec3 tex = texture(rock_tex, UV * tiles).rgb;
	vec3 N = normalize(v_world_normal);
	float key_ndl = max(dot(N, normalize(key_dir)), 0.0);

	vec3 to_beam = beam_pos - v_world_pos;
	float beam_dist = length(to_beam);
	vec3 beam_dir = to_beam / max(beam_dist, 0.0001);
	float beam_ndl = max(dot(N, beam_dir), 0.0);
	float fall = 1.0 - smoothstep(0.0, beam_radius, beam_dist);
	fall *= fall;

	vec3 light = vec3(ambient_amount)
		+ key_color * key_intensity * key_ndl
		+ beam_color * beam_intensity * fall * beam_ndl;
	vec3 lit = tex * light;
	float fog = smoothstep(fog_near, fog_far, v_view_dist);
	ALBEDO = mix(lit, fog_color, fog);
	// Steep alpha fade — ground fully dissolves well before fog_far so
	// the horizon plane, stars and moon behind it stay visible. Paired
	// with depth_draw_never so ground never occludes them via depth.
	ALPHA = 1.0 - smoothstep(fog_near, fog_far * 0.6, v_view_dist);
}
