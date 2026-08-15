// Mega evolution energy sphere.
//
// Additive, unshaded, two-sided shell. Nothing is textured -- the whole look
// comes from three layers driven by the local-space position:
//
//   rim   : fresnel edge glow, makes the shell read as a volume
//   bands : spiralling energy ribbons, warped by fbm noise
//   hue   : pink <-> cyan sweep, the Mega Evolution rainbow
//
// Driven from mega_evolution.gd through three uniforms:
//   progress  0 -> 1 while the sphere charges (density and brightness ramp)
//   flash     0 -> 1 -> 0 at the peak, blows the whole shell to white
//   fade      1 -> 0 as it dissipates
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform float fade : hint_range(0.0, 1.0) = 1.0;

uniform vec3 color_a : source_color = vec3(1.0, 0.18, 0.72);
uniform vec3 color_b : source_color = vec3(0.16, 0.82, 1.0);
uniform vec3 color_core : source_color = vec3(1.0, 0.96, 0.82);

uniform float swirl_speed = 2.2;
uniform float band_count = 7.0;
uniform float rim_power = 2.4;
uniform float intensity = 2.2;
uniform float wobble = 0.16;

varying vec3 v_local;

float hash13(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash13(i + vec3(0.0, 0.0, 0.0)), hash13(i + vec3(1.0, 0.0, 0.0)), f.x),
			mix(hash13(i + vec3(0.0, 1.0, 0.0)), hash13(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
		mix(mix(hash13(i + vec3(0.0, 0.0, 1.0)), hash13(i + vec3(1.0, 0.0, 1.0)), f.x),
			mix(hash13(i + vec3(0.0, 1.0, 1.0)), hash13(i + vec3(1.0, 1.0, 1.0)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return s;
}

void vertex() {
	v_local = VERTEX;
	float t = TIME * swirl_speed;
	// Boil the surface so the shell never looks like a hard sphere.
	float w = fbm(normalize(VERTEX) * 2.6 + vec3(0.0, t * 0.45, 0.0)) - 0.5;
	VERTEX += NORMAL * w * wobble * (0.35 + progress);
}

void fragment() {
	vec3 n = normalize(v_local);
	float t = TIME * swirl_speed;
	float ang = atan(n.z, n.x);

	// Ribbons of energy spiralling up the sphere, noise-warped.
	float warp = fbm(n * 3.0 + vec3(0.0, t * 0.55, 0.0)) * 4.0;
	float band = sin(n.y * band_count - t * 1.7 + ang * 2.0 + warp);
	band = smoothstep(0.05, 1.0, band);

	float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), rim_power);

	float hue = 0.5 + 0.5 * sin(n.y * 3.0 + ang + t);
	vec3 col = mix(color_a, color_b, hue);
	col = mix(col, color_core, clamp(band * 0.55 + rim * 0.4, 0.0, 1.0));
	col = mix(col, vec3(1.0), flash);

	float a = rim * 1.15 + band * 0.5 + 0.06;
	a *= fade * (0.3 + 0.7 * progress);
	a += flash * 1.5;

	ALBEDO = col * intensity * (0.55 + 0.85 * progress + flash * 2.0);
	ALPHA = clamp(a, 0.0, 1.0);
}
