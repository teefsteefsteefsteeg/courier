// REEBOO Labs Water Kit - shared helpers for the 3D water shaders.
// Works in Forward+, Mobile and Compatibility (the depth math switches on CURRENT_RENDERER).

// Linear view-space depth (positive, in meters) of the opaque scene at a screen UV.
float wk_scene_depth(sampler2D dtex, vec2 suv, mat4 inv_proj) {
	float d = textureLod(dtex, suv, 0.0).x;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(suv, d) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(suv * 2.0 - 1.0, d);
#endif
	vec4 v = inv_proj * vec4(ndc, 1.0);
	return -v.z / v.w;
}

// View-space position of the opaque scene at a screen UV.
vec3 wk_scene_view_pos(sampler2D dtex, vec2 suv, mat4 inv_proj) {
	float d = textureLod(dtex, suv, 0.0).x;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(suv, d) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(suv * 2.0 - 1.0, d);
#endif
	vec4 v = inv_proj * vec4(ndc, 1.0);
	return v.xyz / v.w;
}

// Two layers of a caustics texture at a world X/Z position (classic min() blend).
float wk_caustics(sampler2D ctex, vec2 p, float t) {
	float a = texture(ctex, p + vec2(0.013, 0.021) * t).r;
	float b = texture(ctex, p * 1.31 + vec2(0.41, 0.17) - vec2(0.017, -0.011) * t).r;
	return min(a, b);
}

// The screen texture as linear color, so it can be written to EMISSION in every renderer.
vec3 wk_screen_linear(vec3 c) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
#else
	return c;
#endif
}

// Whiteout blend of two tangent-space normals (unpacked, -1..1).
vec3 wk_blend_normals(vec3 a, vec3 b) {
	return normalize(vec3(a.xy + b.xy, a.z * b.z));
}

// One Gerstner wave. w = (direction x, direction z, steepness 0..1, wavelength in meters).
// Returns the displacement and adds the derivatives to tangent / binormal.
vec3 wk_gerstner(vec4 w, vec2 p, float t, inout vec3 tangent, inout vec3 binormal) {
	float steep = w.z;
	float k = 6.2831853 / max(w.w, 0.01);
	float c = sqrt(9.8 / k);
	vec2 d = normalize(w.xy + vec2(0.00001));
	float f = k * (dot(d, p) - c * t);
	float a = steep / k;
	float s = sin(f);
	float co = cos(f);
	tangent += vec3(-d.x * d.x * steep * s, d.x * steep * co, -d.x * d.y * steep * s);
	binormal += vec3(-d.x * d.y * steep * s, d.y * steep * co, -d.y * d.y * steep * s);
	return vec3(d.x * a * co, a * s, d.y * a * co);
}

float wk_hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Expanding rain-drop rings. Returns a tangent-space normal offset (xy).
vec2 wk_rain_ripples(vec2 p, float t, float rate) {
	vec2 acc = vec2(0.0);
	for (int layer = 0; layer < 2; layer++) {
		vec2 q = p + float(layer) * vec2(0.37, 0.71);
		vec2 cell = floor(q);
		vec2 f = fract(q);
		float h = wk_hash12(cell + float(layer) * 17.0);
		vec2 c = vec2(0.25) + 0.5 * vec2(h, wk_hash12(cell.yx + 3.1));
		float life = fract(t * rate + h);
		vec2 dv = f - c;
		float d = length(dv);
		float r = life * 0.45;
		float ring = sin(clamp((d - r) * 40.0, -3.1416, 3.1416)) * (1.0 - smoothstep(0.0, 0.07, abs(d - r)));
		acc += (dv / max(d, 0.0001)) * ring * (1.0 - life) * (1.0 - life);
	}
	return acc;
}

// Toon posterize helper: steps <= 0 returns x unchanged.
float wk_steps(float x, float steps) {
	return steps > 0.5 ? floor(x * steps + 0.5) / steps : x;
}
