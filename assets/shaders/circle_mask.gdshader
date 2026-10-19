// Clips a CanvasItem's texture to a soft-edged circle (HUD portrait).
shader_type canvas_item;

uniform float feather : hint_range(0.0, 0.2) = 0.02;

void fragment() {
	float d = distance(UV, vec2(0.5));
	COLOR.a *= 1.0 - smoothstep(0.5 - feather, 0.5, d);
}
