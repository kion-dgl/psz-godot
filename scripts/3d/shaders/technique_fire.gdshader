shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;
uniform float fade = 1.0;
uniform float phase = 0.0;
uniform float heat = 1.0;
varying vec3 local_pos;
float hash(vec3 p) { return fract(sin(dot(p, vec3(127.1,311.7,74.7))) * 43758.5453); }
float noise3(vec3 p) {
 vec3 i = floor(p); vec3 f = fract(p); f = f*f*(3.0-2.0*f);
 return mix(mix(mix(hash(i),hash(i+vec3(1,0,0)),f.x),mix(hash(i+vec3(0,1,0)),hash(i+vec3(1,1,0)),f.x),f.y),mix(mix(hash(i+vec3(0,0,1)),hash(i+vec3(1,0,1)),f.x),mix(hash(i+vec3(0,1,1)),hash(i+vec3(1,1,1)),f.x),f.y),f.z);
}
void vertex() {
 local_pos = VERTEX;
 float n = noise3(VERTEX * 14.0 + vec3(phase, -TIME*5.0, TIME*3.0));
 VERTEX += NORMAL * (n-0.45) * 0.075;
}
void fragment() {
 vec3 p = local_pos*15.0 + vec3(phase, -TIME*6.0, TIME*4.0);
 float n = noise3(p)*0.65 + noise3(p*2.1)*0.35;
 float facing = pow(max(dot(normalize(NORMAL),normalize(VIEW)),0.0),0.7);
 float hot = clamp((n*0.8 + facing*0.55)*heat,0.0,1.0);
 ALBEDO = mix(vec3(1.0,0.035,0.002),vec3(1.0,0.42,0.015),smoothstep(0.2,0.65,hot));
 ALBEDO = mix(ALBEDO,vec3(1.0,0.9,0.42),smoothstep(0.65,1.0,hot));
 ALPHA = fade * facing * smoothstep(0.12,0.55,n) * 0.9;
}
