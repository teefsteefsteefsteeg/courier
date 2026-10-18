shader_type spatial;
// Village ground: grass with natural variation, blended by two splat maps into
// dirt lanes, cobblestone roads, flagstone plazas, tilled field soil, forest
// floor and clearing moss. Edges are broken up with noise so surfaces meet
// irregularly instead of along straight lines.
//   splat_a: R dirt  G cobble road  B flagstone  A tilled soil
//   splat_b: R forest floor  G clearing moss  B dry meadow  A contact shade

uniform sampler2D splat_a : hint_default_black, filter_linear, repeat_disable;
uniform sampler2D splat_b : hint_default_black, filter_linear, repeat_disable;
uniform vec2 splat_origin = vec2(-64.0, -64.0);
uniform float splat_size = 128.0;
uniform sampler2D noise_large : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_detail : hint_default_white, filter_linear_mipmap, repeat_enable;

uniform vec3 grass_deep : source_color = vec3(0.25, 0.42, 0.19);
uniform vec3 grass_lush : source_color = vec3(0.34, 0.53, 0.23);
uniform vec3 grass_sunny : source_color = vec3(0.46, 0.61, 0.27);
uniform vec3 grass_dry : source_color = vec3(0.56, 0.57, 0.31);
uniform vec3 dirt_dark : source_color = vec3(0.45, 0.33, 0.22);
uniform vec3 dirt_light : source_color = vec3(0.66, 0.52, 0.35);
uniform vec3 cobble_dark : source_color = vec3(0.46, 0.44, 0.42);
uniform vec3 cobble_light : source_color = vec3(0.68, 0.64, 0.58);
uniform vec3 flag_dark : source_color = vec3(0.50, 0.45, 0.39);
uniform vec3 flag_light : source_color = vec3(0.68, 0.62, 0.53);
uniform vec3 mortar : source_color = vec3(0.30, 0.27, 0.24);
uniform vec3 soil_dark : source_color = vec3(0.33, 0.22, 0.14);
uniform vec3 soil_light : source_color = vec3(0.52, 0.38, 0.24);
uniform vec3 forest_dark : source_color = vec3(0.13, 0.22, 0.13);
uniform vec3 forest_light : source_color = vec3(0.25, 0.32, 0.17);
uniform vec3 moss_dark : source_color = vec3(0.24, 0.44, 0.24);
uniform vec3 moss_light : source_color = vec3(0.38, 0.60, 0.32);
uniform float cobble_scale = 2.6;
uniform float flag_scale = 1.45;
uniform float furrow_spacing = 0.9;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

// x: distance to nearest cell point, y: distance to the cell border, z: cell id in [0, 1)
vec3 voronoi(vec2 x) {
	vec2 n = floor(x);
	vec2 f = fract(x);
	float f1 = 8.0;
	float f2 = 8.0;
	vec2 id = vec2(0.0);
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 r = g + hash2(n + g) - f;
			float d = dot(r, r);
			if (d < f1) {
				f2 = f1;
				f1 = d;
				id = n + g;
			} else if (d < f2) {
				f2 = d;
			}
		}
	}
	return vec3(sqrt(f1), sqrt(f2) - sqrt(f1), fract(sin(dot(id, vec2(12.9898, 78.233))) * 43758.5453));
}

// Splat weight with a noisy threshold so edges wander naturally.
float edge(float weight, float noise, float softness, float wobble) {
	return smoothstep(0.5 - softness, 0.5 + softness, weight + (noise - 0.5) * wobble);
}

vec3 stones(vec2 p, float scale, vec3 dark, vec3 light, float detail, out float gap) {
	vec3 v = voronoi(p * scale);
	gap = 1.0 - smoothstep(0.025, 0.11, v.y);
	vec3 stone = mix(dark, light, v.z) * (0.9 + detail * 0.18);
	// Domed stones: a little lighter in the middle.
	stone *= 1.06 - v.x * 0.18;
	return mix(stone, mortar, gap);
}

void fragment() {
	vec2 p = world_pos.xz;
	vec2 uv = (p - splat_origin) / splat_size;
	float n_large = texture(noise_large, p * 0.011).r;
	float n_mid = texture(noise_detail, p * 0.043).r;
	float n_fine = texture(noise_detail, p * 0.17).r;
	vec2 warp = (vec2(texture(noise_detail, p * 0.07).r, texture(noise_detail, p * 0.07 + vec2(0.37, 0.71)).r) - 0.5) * (0.7 / splat_size);
	vec4 a = texture(splat_a, uv + warp);
	vec4 b = texture(splat_b, uv + warp);

	// Grass: broad patches of deep/lush/sunny green, dry meadow streaks, fine mottling.
	vec3 col = mix(grass_deep, grass_lush, smoothstep(0.25, 0.55, n_large));
	col = mix(col, grass_sunny, smoothstep(0.6, 0.85, n_large) * 0.8);
	col = mix(col, grass_dry, clamp(smoothstep(0.55, 0.95, n_mid) * 0.3 + b.b * 0.4, 0.0, 0.6));
	col *= 0.86 + n_fine * 0.26;

	float w_forest = edge(b.r, n_mid, 0.2, 0.5);
	col = mix(col, mix(forest_dark, forest_light, n_fine) * (0.9 + n_large * 0.2), w_forest);
	float w_moss = edge(b.g, n_mid, 0.18, 0.4);
	col = mix(col, mix(moss_dark, moss_light, n_fine), w_moss);

	float w_soil = edge(a.a, n_fine, 0.1, 0.3);
	if (w_soil > 0.001) {
		float furrow = 0.5 + 0.5 * sin(p.y * 6.2832 / furrow_spacing + n_fine * 1.5);
		vec3 soil = mix(soil_dark, soil_light, smoothstep(0.15, 0.85, furrow)) * (0.9 + n_mid * 0.2);
		col = mix(col, soil, w_soil);
	}
	float w_dirt = edge(a.r, n_fine, 0.12, 0.45);
	if (w_dirt > 0.001) {
		// Pale centre line and darker ruts along lanes.
		vec3 dirt = mix(dirt_dark, dirt_light, smoothstep(0.2, 0.8, n_fine * 0.6 + a.r * 0.4)) * (0.92 + n_large * 0.14);
		col = mix(col, dirt, w_dirt);
	}
	float gap = 0.0;
	float w_cobble = edge(a.g, n_fine, 0.07, 0.3);
	if (w_cobble > 0.001) {
		col = mix(col, stones(p, cobble_scale, cobble_dark, cobble_light, n_fine, gap), w_cobble);
	}
	float flag_gap = 0.0;
	float w_flag = edge(a.b, n_fine, 0.06, 0.25);
	if (w_flag > 0.001) {
		col = mix(col, stones(p + vec2(17.3, 5.1), flag_scale, flag_dark, flag_light, n_fine, flag_gap), w_flag);
	}
	// Contact shade under trees and around building footprints.
	col *= 1.0 - b.a * 0.3;

	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.8, max(w_cobble, w_flag) * (1.0 - max(gap, flag_gap)));
	SPECULAR = 0.3;
}
