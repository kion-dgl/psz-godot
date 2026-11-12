shader_type spatial;
// The pool is translucent water (the GLB authors ~0.484 opacity), not an
// additive waterfall glow. Alpha blending bounds its brightness instead of
// accumulating light from the pool bed and other transparent draws.
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform vec3 uv_scale = vec3(1.0);
uniform vec3 uv_offset = vec3(0.0);
uniform vec2 uv_scroll = vec2(0.0);

void fragment() {
	vec2 uv_cont = UV * uv_scale.xy + uv_offset.xy + uv_scroll * TIME;
	vec4 tex = textureGrad(albedo_texture, fract(uv_cont), dFdx(uv_cont), dFdy(uv_cont));
	ALBEDO = tex.rgb * COLOR.rgb * albedo_color.rgb;
	ALPHA = tex.a * albedo_color.a;
}
