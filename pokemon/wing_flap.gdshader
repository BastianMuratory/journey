shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Stands in for the StandardMaterial3D the .obj importer builds, plus a vertex
// stage that folds the wings. [PokemonModel] copies the imported material's
// values into the uniforms below, so a species looks identical whether or not
// it has wings -- the only difference is that this one moves.
//
// [PokemonAnimator] writes fold and twist every frame. Everything else is
// per-species and set once, from the species' PokemonData.

#include "res://pokemon/wing_deform.gdshaderinc"

group_uniforms material;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, hint_default_white, filter_linear_mipmap;
uniform float roughness : hint_range(0.0, 1.0) = 1.0;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float specular : hint_range(0.0, 1.0) = 0.5;

group_uniforms wings;
/// Which way the crease runs: 0 = X (mirrored wings), 1 = Y, 2 = Z.
uniform int fold_axis : hint_range(0, 2) = 0;
/// Fold angle in radians. Driven per frame.
uniform float fold = 0.0;
/// Twist about the fold axis in radians, driven per frame alongside it.
uniform float twist = 0.0;
/// Where the crease sits along the fold axis, model space.
uniform float crease = 0.0;
/// Where the crease line sits in the remaining direction, model space.
uniform float root = 0.0;
/// The far edge of what folds, along the fold axis, model space.
uniform float extent = 1.0;
/// Bend distribution. 1.0 folds rigidly, higher keeps the arc out at the tip.
uniform float curve : hint_range(0.5, 3.0) = 1.5;

void vertex() {
	float w = fold_weight(VERTEX, fold_axis, crease, extent, curve);
	if (w > 0.0) {
		mat3 rot = wing_rotation(fold_axis, fold, twist, w, fold_side(VERTEX, fold_axis));
		vec3 pivot = fold_pivot(VERTEX, fold_axis, crease, root);
		VERTEX = rot * (VERTEX - pivot) + pivot;
		// Pure rotation, so the same matrix serves for the frame vectors.
		NORMAL = rot * NORMAL;
		TANGENT = rot * TANGENT;
		BINORMAL = rot * BINORMAL;
	}
}

void fragment() {
	// Deliberately never writes ALPHA. Godot switches a shader to the transparent
	// pass the moment it sees ALPHA assigned, which would cost these creatures
	// their depth prepass and sort them against each other for no reason -- none
	// of the winged species has an alpha map to begin with.
	ALBEDO = texture(albedo_texture, UV).rgb * albedo_color.rgb;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	SPECULAR = specular;
}
