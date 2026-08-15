shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled;

// Adapted from Loop_Box's CC0 "3D Lightning Shader"
// (https://godotshaders.com/shader/3d-lightning-shader/). The FBM/noise core
// is the original; the changes for Zonde are:
//
//   - Y-billboard vertex(), so one flat quad reads as a bolt from any camera
//     angle instead of disappearing edge-on as the player orbits.
//   - blend_add + unshaded: an additive FX shouldn't take scene lighting, and
//     EMISSION is ignored under unshaded, so Emission_Power folds into ALBEDO.
//   - Fade uniform, so the spawner can tween the bolt out.
//   - Seed uniform: the original is driven purely by TIME, so every bolt on
//     screen is pixel-identical. Gizonde chains and Razonde spawn a fistful at
//     once, and they need to differ.
//   - Top_Taper, so the bolt fades into the sky instead of ending on the hard
//     quad edge. The strike end stays full brightness.
//   - Dropped the Power_Texture sampler — the original reads it into
//     Power_Value and never uses it.

uniform vec3 Main_Color : source_color = vec3(1.0);
uniform vec3 Effect_Color : source_color = vec3(0.3, 0.3, 1.0);

uniform int Octave_Count : hint_range(1, 20) = 6;
uniform float Amp_Start = 0.5;
uniform float Amp_Coeff = 0.5;
uniform float Freq_Coeff = 2.0;
uniform float Speed = 3.0;

uniform float Y_Size = 4.0;
uniform float X_Size = 1.0;

uniform float Emission_Power = 2.0;
uniform float Fade : hint_range(0.0, 1.0) = 1.0;
uniform float Seed = 0.0;
uniform float Top_Taper : hint_range(0.0, 1.0) = 0.25;

float Hash12(vec2 UV_)
{
	return fract(cos(mod(dot(UV_, vec2(13.9898, 8.141)), 3.14)) * 43758.5453);
}

vec2 Hash22(vec2 UV_)
{
	UV_ = vec2(dot(UV_, vec2(127.1, 311.7)),
	dot(UV_, vec2(269.5, 183.3)));
	return 2.0 * fract(sin(UV_) * 43758.5453123);
}

float Noise(vec2 UV_)
{
	vec2 IUV = floor(UV_);
	vec2 FUV = fract(UV_);
	vec2 Blur = smoothstep(0.0, 1.0, FUV);

	float A = dot(Hash22(IUV + vec2(0.0, 0.0)), FUV - vec2(0.0, 0.0));
	float B = dot(Hash22(IUV + vec2(1.0, 0.0)), FUV - vec2(1.0, 0.0));
	float C = dot(Hash22(IUV + vec2(0.0, 1.0)), FUV - vec2(0.0, 1.0));
	float D = dot(Hash22(IUV + vec2(1.0, 1.0)), FUV - vec2(1.0, 1.0));

	float Mix_X1 = mix(A, B, Blur.x);
	float Mix_X2 = mix(C, D, Blur.x);

	return mix(Mix_X1, Mix_X2, Blur.y) + 0.5;
}

float FBM(vec2 UV_)
{
	float Value = 0.0;
	float Amplitude = Amp_Start;

	for (int Index = 0; Index < Octave_Count; Index++)
	{
		Value += Amplitude * Noise(UV_);
		UV_ *= Freq_Coeff;
		Amplitude *= Amp_Coeff;
	}

	return Value;
}

void vertex()
{
	// Y-billboard that keeps the mesh's own scale: the quad yaws to face the
	// camera but stays upright, so the bolt always falls straight down.
	mat4 Facing = VIEW_MATRIX * mat4(
		vec4(normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz)), 0.0),
		vec4(0.0, 1.0, 0.0, 0.0),
		vec4(normalize(cross(INV_VIEW_MATRIX[0].xyz, vec3(0.0, 1.0, 0.0))), 0.0),
		MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = Facing * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment()
{
	vec2 Modified_UV = 2.0 * UV - 1.0;
	Modified_UV.y *= Y_Size;
	Modified_UV.x *= X_Size;

	Modified_UV.x -= Amp_Start;
	Modified_UV += FBM(Modified_UV + TIME * Speed + Seed);
	Modified_UV.x += 0.5 - Amp_Coeff;

	float Dist = abs(Modified_UV.x);

	// UV.y is 0 at the top of a QuadMesh, so this tapers the sky end only.
	float Taper = smoothstep(0.0, Top_Taper, UV.y);
	float Flicker = mix(0.0, 0.05, Hash12(vec2(TIME + Seed)));

	vec3 Final_Color = Effect_Color * Flicker / Dist * Taper * Fade;

	ALBEDO = Final_Color * Main_Color * Emission_Power;
	ALPHA = clamp(Final_Color.r, 0.0, 1.0);
}
