shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, shadows_disabled;

// The white hit flash, for winged species.
//
// [PokemonAnimator] flashes a Pokémon by hanging an additive material off
// material_overlay, which draws the mesh a second time. That second pass runs
// its own vertex stage, so without the identical fold the flash would sit on
// the wings' rest pose while the wings themselves are mid-stroke. Same include,
// same uniforms, same result.

#include "res://pokemon/wing_deform.gdshaderinc"

group_uniforms flash;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 0.0);

group_uniforms wings;
uniform int fold_axis : hint_range(0, 2) = 0;
uniform float fold = 0.0;
uniform float twist = 0.0;
uniform float crease = 0.0;
uniform float root = 0.0;
uniform float extent = 1.0;
uniform float curve : hint_range(0.5, 3.0) = 1.5;

void vertex() {
	float w = fold_weight(VERTEX, fold_axis, crease, extent, curve);
	if (w > 0.0) {
		mat3 rot = wing_rotation(fold_axis, fold, twist, w, fold_side(VERTEX, fold_axis));
		vec3 pivot = fold_pivot(VERTEX, fold_axis, crease, root);
		VERTEX = rot * (VERTEX - pivot) + pivot;
		NORMAL = rot * NORMAL;
	}
}

void fragment() {
	ALBEDO = flash_color.rgb;
	ALPHA = flash_color.a;
}
