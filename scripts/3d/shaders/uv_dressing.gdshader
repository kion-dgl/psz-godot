// UV-dressing shader for decorative object sets (special_c3 warp-pad pieces).
//
// The source GLBs (DS-era) declare mirrored texture wrap and unlit materials
// (KHR_materials_unlit) — Godot's importer keeps unlit but has no mirrored
// wrap on BaseMaterial3D, so these need a shader (same seam problem
// mirror_repeat.gdshader solves, plus per-axis wrap choice, UV scroll for the
// warp glow, and the MASK/BLEND alpha these materials use).
//
// Scroll uses TIME so decorative motion needs no per-frame script and keeps
// running while the tree is paused (menus), like PSZ's own warp glow.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_prepass_alpha;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
// 0 = mirror, 1 = repeat, 2 = clamp — per axis (see WRAP in teleporter_dressing.gd)
uniform int wrap_u = 0;
uniform int wrap_v = 0;
uniform vec2 uv_scale = vec2(1.0, 1.0);
uniform vec2 uv_offset = vec2(0.0, 0.0);
uniform float uv_rot = 0.0; // radians around the texture center
uniform vec2 scroll_speed = vec2(0.0, 0.0); // UV units/sec
uniform float alpha_scissor = 0.0; // >0 = discard below threshold (glTF MASK)
uniform vec4 albedo_color : source_color = vec4(1.0);
// Per-surface back-face cull. render_mode is compile-time, but these sets mix
// single- and double-sided materials on one mesh: o0s_warpcn's glow sheet is
// authored CULL_DISABLED while its base plate is CULL_BACK. Forcing everything
// double-sided draws the plate's underside through the pad as an offset,
// discoloured copy of itself. Discarding back faces here keeps one shader.
uniform bool cull_back = false;
// Debug only (PSZ_DRESSING_DEBUG_TINT=1): flat per-surface colour so a stray
// draw can be traced to the surface that produced it. Anything ghosting in an
// UNTINTED colour is not coming through this shader at all.
uniform vec4 debug_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// Debug only (PSZ_DRESSING_DEBUG_TINT=y): colour by the vertex's model-space Y
// instead of by surface, so stacked rings on ONE surface can be told apart.
// o0s_warpcn's plate is two 14-vertex rings at y=-0.55 and y=-0.20; per-surface
// tinting paints both the same colour and cannot distinguish them.
uniform bool debug_y_tint = false;
// Discard geometry below this model-space Y. These pieces are solid slabs, not
// flat plates: o0s_warpcn's base is 0.35 thick, and its top face is alpha-
// scissored, so the ring cut-outs let you see the underside 0.35 below —
// which reads as an offset, discoloured copy of the plate. The pad sits on the
// floor and nothing under it is ever meaningfully visible, so the bottom face
// is dropped. Left at -INF (draw everything) unless a piece asks for it.
uniform float min_y = -1e9;

varying float v_local_y;

void vertex() {
	v_local_y = VERTEX.y;
}

float wrap_coord(float c, int mode, float half_texel) {
	if (mode == 1) {
		return c; // hardware repeat via the sampler's repeat_enable
	}
	if (mode == 2) {
		return clamp(c, half_texel, 1.0 - half_texel);
	}
	// Mirror. Half-texel inset at the fold: without it, linear filtering
	// samples across the repeat wrap right at the seam and paints a 1px line
	// of the opposite edge (see mirror_repeat.gdshader).
	float m = mod(c, 2.0);
	float r = m < 1.0 ? m : 2.0 - m;
	return clamp(r, half_texel, 1.0 - half_texel);
}

void fragment() {
	if (cull_back && !FRONT_FACING) {
		discard;
	}
	if (v_local_y < min_y) {
		discard;
	}
	vec2 uv = UV;
	if (uv_rot != 0.0) {
		float cs = cos(uv_rot);
		float sn = sin(uv_rot);
		uv = mat2(vec2(cs, sn), vec2(-sn, cs)) * (uv - vec2(0.5)) + vec2(0.5);
	}
	uv = uv * uv_scale + uv_offset + scroll_speed * TIME;
	vec2 half_texel = 0.5 / vec2(textureSize(albedo_tex, 0));
	uv = vec2(wrap_coord(uv.x, wrap_u, half_texel.x), wrap_coord(uv.y, wrap_v, half_texel.y));
	vec4 col = texture(albedo_tex, uv) * COLOR * albedo_color * debug_tint;
	if (debug_y_tint) {
		// Bands split at the midpoints between o0s_warpcn's known ring heights
		// (-0.55, -0.20, +0.50): yellow / cyan / magenta, low to high.
		vec3 band = vec3(1.0, 1.0, 0.2);
		if (v_local_y >= -0.375 && v_local_y < 0.15) {
			band = vec3(0.2, 1.0, 1.0);
		} else if (v_local_y >= 0.15) {
			band = vec3(1.0, 0.2, 1.0);
		}
		col.rgb = band;
	}
	if (alpha_scissor > 0.0 && col.a < alpha_scissor) {
		discard;
	}
	ALBEDO = col.rgb;
	ALPHA = col.a;
}
