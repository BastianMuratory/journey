// Folds part of a rigless mesh about a crease line, in model space.
//
// The Pokémon models are single static .obj meshes with no skeleton, so wings
// cannot be keyframed. What they do have is symmetry about x = 0 and wings that
// stick out as thin sheets, which is enough to bend them in the vertex shader:
// everything past a crease rotates about it, by an angle scaled by how far past
// it sits, so the crease holds still and the far edge sweeps the arc.
//
//     |<-- held -->|<----- folded ---->|
//     0          crease              extent
//     w = 0        w = 0               w = 1
//
// Which direction that runs in is [code]fold_axis[/code]:
//
//     0 (X)  crease runs front-to-back, mirrored on both sides of the body, and
//            the wings swing up and down about Z. This is an ordinary wing beat.
//     1 (Y)  crease runs left-to-right at some height, and everything above it
//            folds forward over what is below, about X.
//     2 (Z)  crease runs left-to-right at some depth, and everything behind it
//            folds up over what is in front, about X.
//
// Only the X fold is mirrored -- it is the only one whose split coordinate is
// |x|, so it is the only one with two halves to move in opposite directions.
//
// Twist is a second, smaller rotation about the fold axis itself: for X that is
// the wing feathering about its own span, which is what makes a beat read as a
// wing rather than a hinge.
//
// UVs are untouched, so the texture rides along exactly as it should.
//
// Shared by wing_flap.gdshader and wing_flash.gdshader -- the hit flash draws
// the mesh a second time through material_overlay, and has to deform to the
// same pose or the flash peels off the wings.
//
// Every function here is pure, and the caller applies the result to VERTEX,
// NORMAL, TANGENT and BINORMAL itself. Handing built-ins to a function as out or
// inout parameters is not something Godot's shader language reliably allows, and
// the three lines it would save are not worth finding that out at import time.

// Where this vertex sits along the fold axis. Mirrored for X, because both wings
// fold together and only their direction differs.
float fold_coord(vec3 vert, int fold_axis) {
	if (fold_axis == 0) {
		return abs(vert.x);
	}
	return fold_axis == 1 ? vert.y : vert.z;
}

// How much of the fold this vertex takes: 0 anywhere before the crease, 1 at the
// far edge.
//
// curve shapes the distribution -- 1.0 swings the whole flap rigidly, which is
// what a fold wants, while higher values keep it straighter near the crease and
// put the arc out at the tip, which is what a wing beat wants.
float fold_weight(vec3 vert, int fold_axis, float crease, float extent, float curve) {
	float reach = max(extent - crease, 0.0001);
	float w = clamp((fold_coord(vert, fold_axis) - crease) / reach, 0.0, 1.0);
	return pow(w, curve);
}

// +1 or -1 for an X fold, so the two wings mirror; 1 for the others, which have
// only one flap to move.
float fold_side(vec3 vert, int fold_axis) {
	return fold_axis == 0 ? sign(vert.x) : 1.0;
}

// The point the fold turns about. Only its position across the rotation axis
// matters, so the coordinate along that axis is left at zero.
//
// [param root] is where the crease line sits in the remaining direction: the
// height of the shoulder for an X fold, and for the others the offset of the
// crease line across the body.
vec3 fold_pivot(vec3 vert, int fold_axis, float crease, float root) {
	if (fold_axis == 0) {
		return vec3(sign(vert.x) * crease, root, 0.0);
	}
	if (fold_axis == 1) {
		return vec3(0.0, crease, root);
	}
	return vec3(0.0, root, crease);
}

// The fold itself: about Z for an X fold, about X for the other two -- in each
// case the axis the crease line runs along.
mat3 fold_rotation(int fold_axis, float angle) {
	float c = cos(angle);
	float s = sin(angle);
	// Columns, not rows.
	if (fold_axis == 0) {
		return mat3(vec3(c, s, 0.0), vec3(-s, c, 0.0), vec3(0.0, 0.0, 1.0));
	}
	return mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, c, s), vec3(0.0, -s, c));
}

// Twist, about the fold axis itself. Unmirrored: both wings feather the same way
// into the stroke, the way a real pair does.
mat3 twist_rotation(int fold_axis, float angle) {
	float c = cos(angle);
	float s = sin(angle);
	if (fold_axis == 0) {
		return mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, c, s), vec3(0.0, -s, c));
	}
	if (fold_axis == 1) {
		return mat3(vec3(c, 0.0, -s), vec3(0.0, 1.0, 0.0), vec3(s, 0.0, c));
	}
	return mat3(vec3(c, s, 0.0), vec3(-s, c, 0.0), vec3(0.0, 0.0, 1.0));
}

// Everything above, assembled: the rotation to apply to a vertex and its frame.
// Twist first, then the fold swings the twisted flap.
mat3 wing_rotation(int fold_axis, float fold, float twist, float weight, float side) {
	return fold_rotation(fold_axis, fold * weight * side)
		* twist_rotation(fold_axis, twist * weight);
}
