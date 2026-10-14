shader_type spatial;
// Mirrored-repeat variant for EFFECT SPRITES (the o0c_* burst/effect archive):
// crossed quads carrying a tiny indexed-looking texture, meant to be drawn flat
// and unlit with a hard alpha cut — matching what the glTF declares (NEAREST
// filtering, alphaMode MASK, doubleSided).
//
// Split from mirror_repeat_alpha.gdshader because those three properties are
// shader-level, not uniforms: the filter is a sampler hint, and unshaded is a
// render_mode. The UV fold itself is shared via the include.
render_mode unshaded, cull_disabled;

#include "res://scripts/3d/shaders/mirror_repeat.gdshaderinc"

uniform sampler2D albedo_texture : source_color, filter_nearest, repeat_enable;
uniform vec2 uv_scale = vec2(1.0, 1.0);
uniform vec2 uv_offset = vec2(0.0, 0.0);
uniform bool mirror_x = true;
uniform bool mirror_y = true;
uniform float alpha_scissor = 0.5;
uniform vec4 albedo_tint : source_color = vec4(1.0);
uniform float visibility_alpha = 1.0;
// Optional radial reveal for the source-sized Needler effect.
uniform float reveal_radius = -1.0;
// Needle rails share the spike material but use horizontal faces.
uniform bool preserve_horizontal_faces = false;
// Original needle strip UVs are above the rail band (which ends at 0.823).
uniform bool align_needle_slots = false;
varying float needle_face;
varying vec3 local_position;
varying vec2 local_xz;

void vertex() {
	needle_face = align_needle_slots && UV.y > 0.83 ? 1.0 : 0.0;
	// Half of the plate texture repeat: move spike rows from lattice to slots.
	if (needle_face > 0.5) VERTEX.z -= 5.5 / 7.0;
	local_xz = VERTEX.xz;
	local_position = VERTEX;
}

void fragment() {
	// The source has an extra pair of rows beyond the textured plate.
	if (needle_face > 0.5 && abs(local_xz.y) > 2.75) discard;
	if (reveal_radius >= 0.0 && length(local_xz) > reveal_radius) discard;
	vec2 uv = UV * uv_scale + uv_offset;
	vec2 half_texel = 0.5 / vec2(textureSize(albedo_texture, 0));
	uv = mirror_uv(uv, half_texel, mirror_x, mirror_y);
	vec4 tex = texture(albedo_texture, uv);
	ALBEDO = tex.rgb * albedo_tint.rgb;
	// Derive the face normal: imported sprite normals do not describe these planes.
	vec3 face_normal = normalize(cross(dFdx(local_position), dFdy(local_position)));
	float surface_visibility = preserve_horizontal_faces && abs(face_normal.y) > 0.5 ? 1.0 : visibility_alpha;
	ALPHA = tex.a * albedo_tint.a * surface_visibility;
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor;
}
