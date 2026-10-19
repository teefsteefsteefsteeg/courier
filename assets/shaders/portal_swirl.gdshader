// Teleport portal surface: a blue-purple swirl with a slowly turning ring of rune marks,
// soft-edged to a disc. Unshaded and additive, so it needs no light; `power` fades it
// (0 = an inactive portal shows nothing). The same shader draws the ground rune circle
// with `swirl` off.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

uniform vec4 inner_color : source_color = vec4(0.62, 0.42, 1.0, 1.0);
uniform vec4 outer_color : source_color = vec4(0.22, 0.55, 1.0, 1.0);
uniform vec4 rune_color : source_color = vec4(0.85, 0.8, 1.0, 1.0);
uniform float power : hint_range(0.0, 2.0) = 1.0;
uniform float swirl : hint_range(0.0, 1.0) = 1.0;
uniform float rune_speed = 0.35;
uniform float rune_count = 14.0;
uniform float ring_radius : hint_range(0.0, 0.5) = 0.4;

float hash(float n) { return fract(sin(n) * 43758.5453); }

void fragment() {
	vec2 p = UV - vec2(0.5);
	float r = length(p);
	float a = atan(p.y, p.x);
	float disc = 1.0 - smoothstep(0.46, 0.5, r);
	// Swirl: two counter-turning spiral arms over a radial gradient.
	float spiral = sin(a * 3.0 + r * 22.0 - TIME * 2.4) * 0.5 + 0.5;
	float spiral2 = sin(-a * 2.0 + r * 15.0 - TIME * 1.3) * 0.5 + 0.5;
	vec3 base = mix(inner_color.rgb, outer_color.rgb, smoothstep(0.0, 0.48, r));
	float glow = (0.35 + 0.45 * spiral * spiral2) * (1.0 - smoothstep(0.0, 0.5, r) * 0.5);
	vec3 col = base * glow * swirl;
	// Rune ring: short marks around ring_radius, turning slowly.
	float turned = a + TIME * rune_speed;
	float slot = floor((turned / 6.2831853 + 0.5) * rune_count);
	float local = fract((turned / 6.2831853 + 0.5) * rune_count);
	float mark = step(0.25, local) * step(local, 0.25 + 0.35 + 0.3 * hash(slot));
	float band = smoothstep(0.022, 0.0, abs(r - ring_radius));
	float edge = smoothstep(0.012, 0.0, abs(r - (ring_radius + 0.05))) * 0.6;
	col += rune_color.rgb * (band * mark + edge) * (0.75 + 0.25 * sin(TIME * 3.0 + slot));
	ALBEDO = col * power * disc;
	ALPHA = 1.0;
}
