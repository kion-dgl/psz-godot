shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform vec3 uv_scale = vec3(1.0, 1.0, 1.0);
uniform vec3 uv_offset = vec3(0.0, 0.0, 0.0);
uniform vec2 uv_scroll = vec2(0.0, 0.0);

void fragment() {
	// Keep the SAMPLED uv in [0,1) (offsetY + uv_scroll*TIME accumulate large,
	// and fract preserves float precision), but derive the mip from the
	// CONTINUOUS coord. Plain texture() after fract() spikes the UV derivative
	// at every wrap — the GPU then snaps to a coarse mip right there, painting
	// a dark seam where the scroll wraps (the horizontal tile seam) and dotted
	// lines at the U edges. textureGrad feeds the real continuous derivatives,
	// so wrapping stays seamless with mipmaps.
	vec2 uv_cont = UV * uv_scale.xy + uv_offset.xy + uv_scroll * TIME;
	vec2 uv = fract(uv_cont);
	vec4 tex = textureGrad(albedo_texture, uv, dFdx(uv_cont), dFdy(uv_cont));
	ALBEDO = tex.rgb * COLOR.rgb * albedo_color.rgb;
	ALPHA = tex.a * albedo_color.a;
}
