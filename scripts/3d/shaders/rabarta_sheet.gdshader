shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform float age = 0.0;
uniform float speed = 16.0;
varying vec3 point;
void vertex() {
    point = VERTEX;
    float arrival = length(VERTEX.xz) / speed;
    VERTEX.y *= smoothstep(arrival, arrival + 0.1, age);
}
void fragment() {
    float arrival = length(point.xz) / speed;
    float local_age = age - arrival;
    float appear = smoothstep(0.0, 0.025, local_age);
    float fade = 1.0 - smoothstep(0.22, 0.65, local_age);
    float vein = pow(0.5 + 0.5 * sin(point.x * 8.0 + sin(point.z * 5.0) * 2.0), 16.0);
    float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 2.0);
    // Freshly frozen leading band is white; older ice settles into pale blue.
    float leading = 1.0 - smoothstep(0.045, 0.13, local_age);
    vec3 trail = mix(vec3(0.28,0.65,0.83), vec3(0.68,0.9,1.0), vein * 0.65 + rim * 0.3);
    ALBEDO = mix(trail, vec3(0.88,1.0,1.0), leading);
    EMISSION = ALBEDO * (0.2 + vein * 0.35 + leading * 1.4);
    ALPHA = appear * fade * mix(0.38 + vein * 0.22 + rim * 0.12, 0.95, leading);
}
