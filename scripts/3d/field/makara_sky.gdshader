shader_type sky;

uniform sampler2D cloud_noise : repeat_enable, filter_linear;
uniform vec3 sun_direction = vec3(0.0, 0.7, 0.7);

uniform float night_amount = 0.0;
uniform float rain_amount = 0.0;
uniform float twilight_amount = 0.0;

void sky() {
	vec3 ray = normalize(EYEDIR);
	float height = clamp(ray.y, 0.0, 1.0);
	vec3 sky_color = mix(vec3(0.72, 0.55, 0.46), vec3(0.12, 0.32, 0.57), pow(height, 0.45));
	sky_color = mix(sky_color, mix(vec3(0.52, 0.19, 0.12), vec3(0.10, 0.12, 0.29), height), twilight_amount);
	sky_color = mix(sky_color, mix(vec3(0.035, 0.05, 0.09), vec3(0.006, 0.012, 0.035), height), night_amount);
	float sun_dot = max(dot(ray, normalize(sun_direction)), 0.0);
	float sun_disk = smoothstep(cos(0.022), cos(0.016), sun_dot);
	vec3 sunlight = mix(vec3(1.0, 0.79, 0.48), vec3(0.55, 0.7, 1.0), night_amount);
	sky_color += sunlight * (pow(sun_dot, 40.0) * 0.22 + sun_disk * 3.0);
	// Two samples of a precomputed seamless noise texture; no volumetric march.
	vec2 uv = ray.xz / (max(ray.y, 0.0) + 0.25) * 0.17;
	uv += vec2(TIME * 0.0015, TIME * 0.0004);
	float noise = texture(cloud_noise, uv).r * 0.75;
	noise += texture(cloud_noise, uv * 2.3 + vec2(0.21, 0.43)).r * 0.25;
	float clouds = smoothstep(0.44 - rain_amount * 0.22, 0.64 - rain_amount * 0.12, noise) * smoothstep(-0.02, 0.12, ray.y);
	vec3 cloud_color = mix(vec3(0.38, 0.42, 0.51), vec3(0.96, 0.85, 0.73), smoothstep(0.48, 0.73, noise));
	cloud_color = mix(cloud_color, vec3(0.045, 0.055, 0.085), night_amount);
	cloud_color *= 1.0 - rain_amount * 0.4;
	sky_color *= 1.0 - rain_amount * 0.35;
	cloud_color += sunlight * pow(sun_dot, 16.0) * 0.15;
	COLOR = mix(sky_color, cloud_color, clouds * 0.94);
}
