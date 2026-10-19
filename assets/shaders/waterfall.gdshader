shader_type spatial;
// Wyrmfall waterfall sheet (Phase 8). UV.x runs across the fall, UV.y from the lip (0) to
// the pool (1). Two layers of foam streaks scroll downwards at different speeds over a
// translucent body that whitens towards the plunge; the sides fade out, and the lip and
// the base foam up.
render_mode blend_mix, cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

uniform vec4 top_color : source_color = vec4(0.36, 0.66, 0.78, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.62, 0.84, 0.9, 1.0);
uniform vec4 foam_color : source_color = vec4(0.95, 0.98, 1.0, 1.0);
uniform sampler2D streak_texture : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float speed = 1.4;
uniform float streak_strength : hint_range(0.0, 2.0) = 0.9;
uniform float opacity : hint_range(0.0, 1.0) = 0.82;

void fragment() {
	vec2 uv = UV;
	float a = texture(streak_texture, vec2(uv.x * 1.6, uv.y * 1.2 - TIME * speed)).r;
	float b = texture(streak_texture, vec2(uv.x * 3.1 + 0.37, uv.y * 2.4 - TIME * speed * 1.7)).r;
	float streak = smoothstep(0.42, 0.85, a * 0.55 + b * 0.55);
	float plunge = smoothstep(0.78, 1.0, uv.y);
	float lip = 1.0 - smoothstep(0.0, 0.08, uv.y);
	vec3 water = mix(top_color.rgb, bottom_color.rgb, uv.y);
	vec3 color = mix(water, foam_color.rgb, clamp(streak * streak_strength + plunge * 0.7 + lip * 0.5, 0.0, 1.0));
	float sides = smoothstep(0.0, 0.14, uv.x) * smoothstep(1.0, 0.86, uv.x);
	ALBEDO = color;
	EMISSION = color * 0.18;
	ROUGHNESS = 0.18;
	SPECULAR = 0.6;
	ALPHA = clamp(opacity + streak * 0.25, 0.0, 1.0) * sides;
}
