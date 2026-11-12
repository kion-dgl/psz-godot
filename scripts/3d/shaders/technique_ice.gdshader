shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never;
uniform float dissolve = 0.0;
uniform float opacity = 1.0;
varying vec3 local_pos;
void vertex() { local_pos = VERTEX; }
void fragment() {
 vec3 cell = floor(local_pos * 28.0);
 float noise = fract(sin(dot(cell,vec3(12.9898,78.233,45.164)))*43758.5453);
 float rim = pow(1.0 - abs(dot(normalize(NORMAL),normalize(VIEW))),1.5);
 float vein = pow(0.5+0.5*sin(local_pos.y*26.0 + local_pos.x*17.0 + sin(local_pos.z*31.0)*1.4),18.0);
 ALBEDO = mix(vec3(0.26,0.62,0.78),vec3(0.82,0.96,1.0),rim*0.7+vein*0.25);
 float breakup = smoothstep(dissolve-0.15,dissolve+0.15,noise);
 ALPHA = opacity * (0.28 + rim*0.3 + vein*0.12) * breakup * (1.0-dissolve);
}
