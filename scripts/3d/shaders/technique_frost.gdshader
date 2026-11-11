shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform float opacity = 0.55;
uniform float phase = 0.0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1,311.7))) * 43758.5453); }
float noise2(vec2 p) {
 vec2 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
 return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}
void vertex() {
 MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
 vec2 p = UV * 2.0 - 1.0;
 float n = noise2(UV*5.0 + vec2(TIME*0.7 + phase, -TIME*0.4));
 n = n*0.7 + noise2(UV*11.0 + vec2(-TIME,phase))*0.3;
 float shape = 1.0-smoothstep(0.15,1.0,length(p*vec2(1.0,1.15)) + (n-0.5)*0.25);
 ALBEDO = mix(vec3(0.66,0.85,0.91),vec3(0.87,0.97,1.0),n);
 ALPHA = opacity * shape * (0.45 + 0.55*n);
}
