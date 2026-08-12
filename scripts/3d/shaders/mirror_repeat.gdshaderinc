// Mirrored-repeat UV folding, shared by every mirror_repeat* shader.
//
// PSZ's source assets lean on hardware MIRRORED_REPEAT (glTF wrap 33648) and
// author UVs that run outside 0..1 expecting the fold — stage geometry, gates
// and switches, and the effect sprites all do it. Godot's StandardMaterial3D
// carries only a `texture_repeat` bool, so the importer drops the mode (it
// lands on CLAMP) and the outside-0..1 span smears the edge texel instead of
// mirroring. These shaders put it back.
//
// Keep this the ONLY implementation: it existed three times before, and the
// half-texel inset below is easy to omit when copying by hand.

float mirror_coord(float c, float half_texel) {
	float m = mod(c, 2.0);
	float r = m < 1.0 ? m : 2.0 - m;
	// Half-texel inset at the mirror fold: without it, linear filtering samples
	// across the repeat wrap right at the seam and paints a 1px line of the
	// opposite edge (the "off by a pixel" seam). Clamping to texel-center range
	// makes the fold double the edge texel, like hardware MIRRORED_REPEAT.
	return clamp(r, half_texel, 1.0 - half_texel);
}

vec2 mirror_uv(vec2 uv, vec2 half_texel, bool mirror_x, bool mirror_y) {
	if (mirror_x) uv.x = mirror_coord(uv.x, half_texel.x);
	if (mirror_y) uv.y = mirror_coord(uv.y, half_texel.y);
	return uv;
}
