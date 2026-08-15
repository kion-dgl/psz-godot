// CRT tube emulation — full-screen post-process. Spec: /states/crt-filter.
//
// Owned by the CrtFilter autoload, which drives every uniform from a preset
// table (Off / Scanlines / Full). There is ONE shader and the presets differ
// only in uniform values, so a new look is a preset entry, not a new shader.
//
// This reads the back buffer, so the material MUST be the top-most canvas item
// in the viewport — everything drawn under it (3D world, HUD canvases, the
// SceneManager fade) is what gets sampled. CrtFilter parks it at layer 260 for
// exactly that reason.
//
// Godot copies the back buffer automatically for any canvas item whose shader
// declares hint_screen_texture, so no BackBufferCopy node is needed — but that
// copy is a real per-frame cost, which is why CrtFilter hides the rect entirely
// (rather than zeroing the uniforms) when the filter is Off.

shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;

// Virtual scanline count — the "resolution" of the simulated tube. Deliberately
// independent of window size, so the look is identical at 720p and at 4K
// instead of the lines vanishing into the pixel grid on a big display.
uniform float scanline_count : hint_range(120.0, 720.0) = 240.0;
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.0;
// Aperture-grille strength. The grille itself is measured in PHYSICAL pixels
// (3px RGB triads) so it stays a fine texture rather than growing with the
// window the way the scanlines do.
uniform float mask_strength : hint_range(0.0, 1.0) = 0.0;
uniform float curvature : hint_range(0.0, 0.5) = 0.0;
uniform float aberration : hint_range(0.0, 4.0) = 0.0;  // physical px of R/B split
uniform float glow : hint_range(0.0, 1.0) = 0.0;
uniform float vignette : hint_range(0.0, 1.0) = 0.0;
uniform float brightness : hint_range(0.5, 2.0) = 1.0;


// Barrel-warp SCREEN_UV, then scale back by exactly the corner warp factor.
// The rescale is what keeps the filter non-destructive: at full strength the
// corners land back on 1.0 instead of past it, so no HUD pixel is ever cropped.
// The cost is a thin black band at the edge midpoints — which reads as the
// tube's bezel, and is the reason Full keeps `curvature` small.
vec2 curve_uv(vec2 uv, float amt) {
	vec2 c = uv * 2.0 - 1.0;
	c *= 1.0 + amt * dot(c, c) * 0.5;  // corner (dot == 2.0) → 1.0 + amt
	c /= 1.0 + amt;
	return c * 0.5 + 0.5;
}


// RGB triad mask. One channel per physical pixel column stays at full
// brightness; the other two are pulled down by `strength`.
vec3 grille(float x, float strength) {
	float phase = mod(floor(x), 3.0);
	vec3 m = vec3(1.0 - strength);
	if (phase < 1.0) {
		m.r = 1.0;
	} else if (phase < 2.0) {
		m.g = 1.0;
	} else {
		m.b = 1.0;
	}
	return m;
}


void fragment() {
	vec2 uv = curve_uv(SCREEN_UV, curvature);

	// Outside the warped tube face — bezel. Softened over one pixel so the
	// rounded corners don't alias into a staircase.
	vec2 edge = smoothstep(vec2(0.0), SCREEN_PIXEL_SIZE * 2.0, uv)
		* smoothstep(vec2(0.0), SCREEN_PIXEL_SIZE * 2.0, vec2(1.0) - uv);
	float inside = edge.x * edge.y;

	vec2 ab = vec2(aberration, 0.0) * SCREEN_PIXEL_SIZE;
	vec3 col = vec3(
		texture(screen_tex, clamp(uv - ab, vec2(0.0), vec2(1.0))).r,
		texture(screen_tex, uv).g,
		texture(screen_tex, clamp(uv + ab, vec2(0.0), vec2(1.0))).b
	);

	// Cheap 4-tap halation — a bright phosphor bleeds into its darker
	// neighbours. Deliberately one-directional (max(avg - col, 0)): adding the
	// blur outright would raise every flat region too, which reads as a washed
	// -out image rather than as glow.
	if (glow > 0.0) {
		vec2 g = SCREEN_PIXEL_SIZE * 2.0;
		vec3 avg = 0.25 * (texture(screen_tex, uv + vec2(g.x, 0.0)).rgb
			+ texture(screen_tex, uv - vec2(g.x, 0.0)).rgb
			+ texture(screen_tex, uv + vec2(0.0, g.y)).rgb
			+ texture(screen_tex, uv - vec2(0.0, g.y)).rgb);
		col += max(avg - col, vec3(0.0)) * glow;
	}

	col *= 1.0 - scanline_strength * (0.5 + 0.5 * cos(uv.y * scanline_count * TAU));
	col *= grille(FRAGCOORD.x, mask_strength);

	float vig = uv.x * uv.y * (1.0 - uv.x) * (1.0 - uv.y);
	vig = clamp(pow(vig * 16.0, 0.3), 0.0, 1.0);
	col *= mix(1.0, vig, vignette);

	// Scanlines and the grille both remove energy; brightness pays it back so
	// enabling the filter doesn't just make the game darker.
	col *= brightness;

	COLOR = vec4(col * inside, 1.0);
}
