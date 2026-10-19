// REEBOO Labs Water Kit - 3D calm water: pond, lake, pool
// Gentle wind ripples in world space, optional rain rings, depth color, refraction,
// floor caustics, shore foam and a strong mirror-like Fresnel reflection.
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;

#include "water_common.gdshaderinc"

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

group_uniforms color;
uniform vec4 shallow_color : source_color = vec4(0.25, 0.60, 0.55, 1.0);
uniform vec4 deep_color : source_color = vec4(0.03, 0.14, 0.18, 1.0);
uniform float depth_distance = 4.0;
uniform float clarity = 2.5;
uniform vec4 refraction_tint : source_color = vec4(1.0);
// How strongly shallow_color tints the floor seen through the water (0 = clear glass).
uniform float absorption_tint : hint_range(0.0, 4.0) = 1.5;
uniform sampler2D caustics_texture : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform float caustics_strength : hint_range(0.0, 4.0) = 0.8;
uniform float caustics_scale = 3.0;

group_uniforms surface;
uniform sampler2D normal_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_b : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float normal_scale = 8.0;
uniform float normal_strength : hint_range(0.0, 2.0) = 0.35;
uniform vec2 wind_direction = vec2(1.0, 0.4);
uniform float wind_speed : hint_range(0.0, 4.0) = 0.6;
uniform float roughness : hint_range(0.0, 1.0) = 0.03;
uniform float specular : hint_range(0.0, 1.0) = 0.6;
uniform float refraction_strength : hint_range(0.0, 0.3) = 0.04;

group_uniforms rain;
// 0 = no rain. Rings per square meter per second, roughly.
uniform float rain_amount : hint_range(0.0, 3.0) = 0.0;
uniform float rain_ring_size = 1.2;
uniform float rain_strength : hint_range(0.0, 2.0) = 0.8;

group_uniforms reflection;
uniform vec4 reflection_color : source_color = vec4(0.60, 0.75, 0.90, 1.0);
uniform float reflection_strength : hint_range(0.0, 1.0) = 0.6;
uniform float fresnel_power : hint_range(0.5, 10.0) = 4.0;

group_uniforms foam;
uniform sampler2D foam_texture : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 foam_color : source_color = vec4(0.92, 0.95, 0.96, 1.0);
uniform float foam_scale = 4.0;
uniform float shore_foam : hint_range(0.0, 2.0) = 0.5;
uniform float shore_foam_distance = 0.6;

group_uniforms style;
uniform float toon_steps : hint_range(0.0, 8.0, 1.0) = 0.0;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = TIME;
	vec2 wd = normalize(wind_direction + vec2(0.0001)) * wind_speed;
	vec2 wuv = v_world.xz / normal_scale;
	vec3 na = texture(normal_a, wuv + wd * t * 0.02).rgb * 2.0 - 1.0;
	vec3 nb = texture(normal_b, wuv * 1.9 + vec2(-wd.y, wd.x) * t * 0.017 + vec2(0.5, 0.2)).rgb * 2.0 - 1.0;
	vec3 nt = wk_blend_normals(na, nb);
	nt.xy *= normal_strength;
	if (rain_amount > 0.0) {
		nt.xy += wk_rain_ripples(v_world.xz / rain_ring_size, t, rain_amount) * rain_strength;
	}
	vec3 N = normalize(NORMAL * nt.z + TANGENT * nt.x + BINORMAL * nt.y);
	vec3 up_view = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);

	float frag_d = -VERTEX.z;
	float thick0 = max(wk_scene_depth(depth_texture, SCREEN_UV, INV_PROJECTION_MATRIX) - frag_d, 0.0);
	vec2 ruv = SCREEN_UV + (N - up_view).xy * refraction_strength * clamp(thick0, 0.0, 1.0);
	float scene_r = wk_scene_depth(depth_texture, ruv, INV_PROJECTION_MATRIX);
	if (scene_r < frag_d) {
		ruv = SCREEN_UV;
		scene_r = frag_d + thick0;
	}
	float thick = max(scene_r - frag_d, 0.0);

	float deep_t = wk_steps(1.0 - exp(-thick / max(depth_distance, 0.01)), toon_steps);
	// Light through the water is absorbed per channel: shallow_color tints what you see below.
	vec3 absorb = ((vec3(1.0) - shallow_color.rgb) * absorption_tint + vec3(1.0)) / max(clarity, 0.01);
	vec3 tr = exp(-thick * absorb);
	float trans = wk_steps((tr.r + tr.g + tr.b) / 3.0, toon_steps);
	if (toon_steps > 0.5) {
		tr = vec3(trans);
	}
	vec3 water = mix(shallow_color.rgb, deep_color.rgb, deep_t);
	vec3 refr = wk_screen_linear(textureLod(screen_texture, ruv, 0.0).rgb) * refraction_tint.rgb;
	if (caustics_strength > 0.0) {
		vec3 floor_w = (INV_VIEW_MATRIX * vec4(wk_scene_view_pos(depth_texture, ruv, INV_PROJECTION_MATRIX), 1.0)).xyz;
		float c = wk_caustics(caustics_texture, floor_w.xz / caustics_scale, t);
		refr += refr * c * caustics_strength * exp(-thick / max(clarity * 2.0, 0.01));
	}
	float fres = wk_steps(pow(1.0 - clamp(dot(N, VIEW), 0.0, 1.0), fresnel_power), toon_steps);

	float fn = texture(foam_texture, v_world.xz / foam_scale + wd * t * 0.01).r;
	float shore_m = (1.0 - smoothstep(0.0, shore_foam_distance, thick0)) * shore_foam;
	shore_m *= 0.8 + 0.2 * sin(thick0 / max(shore_foam_distance, 0.01) * 7.0 - t * 1.5);
	float foam = toon_steps > 0.5 ? step(1.0 - shore_m, fn) * step(0.01, shore_m)
			: smoothstep(1.0 - shore_m, 1.0 - shore_m + 0.15, fn);

	vec3 albedo = water * (1.0 - trans);
	vec3 emis = refr * tr;
	albedo = mix(albedo, reflection_color.rgb, fres * reflection_strength);
	emis *= 1.0 - fres * reflection_strength;
	ALBEDO = mix(albedo, foam_color.rgb, foam);
	EMISSION = emis * (1.0 - foam);
	ROUGHNESS = mix(roughness, 0.9, foam);
	SPECULAR = specular * (1.0 - foam);
	NORMAL = N;
	ALPHA = 1.0;
}
