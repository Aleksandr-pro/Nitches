shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// Native 0.2.28: variety pass (replaced/aged pavers, delivery-batch
// hue drift, per-segment mortar colour, chipped joint edges, joint
// grime) on top of the 0.2.17 stochastic concrete below.
// Native 0.2.17 stochastic concrete.  The old StandardMaterial repeated
// one 6 m slab photograph in world triplanar space, so the same joints
// and stains visibly tiled across whole districts.  This shader keeps
// the photographic aggregate, but blends two rotated scales under a
// procedural running-bond layout whose row offsets, paver lengths,
// tint, roughness, stains and gum spots vary by world-space hash.

uniform sampler2D slab_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D slab_normal_texture : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D fine_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_textures = true;
uniform vec4 tint : source_color = vec4(0.56, 0.57, 0.56, 1.0);
uniform float base_roughness : hint_range(0.55, 1.0) = 0.95;
uniform float pattern_scale : hint_range(0.45, 2.5) = 1.0;
uniform float joint_strength : hint_range(0.0, 1.0) = 0.92;
uniform float normal_strength : hint_range(0.0, 1.5) = 0.62;

varying vec3 world_position;
varying vec3 world_normal;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

vec3 sample_concrete_albedo(vec2 plane) {
	vec2 uv_a = plane * 0.083;
	vec2 uv_b = vec2(plane.y, -plane.x) * 0.066 + vec2(0.371, 0.719);
	vec3 a = texture(slab_texture, uv_a).rgb;
	vec3 b = texture(slab_texture, uv_b).rgb;
	float blend = smoothstep(0.30, 0.70, value_noise(plane * 0.073 + 13.7));
	vec3 colour = mix(a, b, blend * 0.62);
	float fine = texture(fine_texture, plane * 0.63).r;
	float fine_rot = texture(fine_texture, vec2(plane.y, -plane.x) * 1.71 + 0.43).r;
	colour *= (0.76 + 0.42 * fine) * (0.90 + 0.20 * fine_rot);
	return colour;
}

vec3 sample_concrete_normal(vec2 plane) {
	vec3 a = texture(slab_normal_texture, plane * 0.083).rgb * 2.0 - 1.0;
	vec3 b = texture(slab_normal_texture, vec2(plane.y, -plane.x) * 0.066 + vec2(0.371, 0.719)).rgb * 2.0 - 1.0;
	vec3 mixed = normalize(mix(a, b, 0.38) + vec3(0.0, 0.0, 0.001));
	return mixed * 0.5 + 0.5;
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(world_normal);
	vec3 an = abs(n);
	vec2 plane = (an.y >= an.x && an.y >= an.z)
		? world_position.xz
		: (an.x >= an.z ? world_position.zy : world_position.xy);
	plane *= pattern_scale;

	// Running bond in real metres: rows are 1.38 m deep, while each row
	// independently chooses 2.35 m, 3.15 m or 4.05 m pavers and an offset.
	float row_height = 1.38;
	float row_id = floor(plane.y / row_height);
	float row_hash = hash12(vec2(row_id * 1.371, 4.17));
	float segment_length = row_hash < 0.33 ? 2.35 : (row_hash < 0.72 ? 3.15 : 4.05);
	float row_offset = row_hash * 17.31;
	float segment_id = floor((plane.x + row_offset) / segment_length);
	float local_x = fract((plane.x + row_offset) / segment_length);
	float local_y = fract(plane.y / row_height);
	float edge_x = min(local_x, 1.0 - local_x) * segment_length;
	float edge_y = min(local_y, 1.0 - local_y) * row_height;
	float edge_distance = min(edge_x, edge_y);
	vec2 paver_id = vec2(segment_id * 1.73 + row_id * 0.31, row_id * 2.19 - segment_id * 0.17);
	float paver_hash = hash12(paver_id);
	float paver_warmth = hash12(paver_id + 19.7);
	// 0.2.28 variety pass: chipped/worn joint edges and a per-paver
	// joint width, so no two joints read as the same stamped line.
	float chip = value_noise(plane * 9.0 + 3.7);
	float edge_chipped = edge_distance + (chip - 0.5) * 0.016;
	float joint_half = 0.012 + 0.020 * hash12(paver_id + 7.3);
	float aa = max(max(fwidth(plane.x), fwidth(plane.y)), 0.004);
	float joint = (1.0 - smoothstep(joint_half, joint_half + 0.034 + aa * 1.45, edge_chipped)) * joint_strength;
	float bevel = smoothstep(0.035, 0.078, edge_distance) * (1.0 - smoothstep(0.078, 0.175, edge_distance));

	vec3 base = use_textures ? sample_concrete_albedo(plane) : vec3(0.52);
	vec3 colour = base * tint.rgb * (0.78 + 0.44 * paver_hash);
	colour *= mix(vec3(0.96, 0.99, 1.04), vec3(1.05, 1.00, 0.93), paver_warmth);
	// Occasional replaced (newer, cooler) and aged (darker) pavers.
	float replaced = step(0.935, hash12(paver_id + 31.1));
	float aged = step(hash12(paver_id + 47.9), 0.045);
	colour *= 1.0 + replaced * 0.16 - aged * 0.20;
	colour = mix(colour, colour * vec3(0.94, 0.97, 1.05), replaced * 0.7);
	// Slow warm<->cool drift between stone deliveries (~60 m wavelength).
	float batch_drift = value_noise(plane * 0.016 + 8.4);
	colour *= mix(vec3(0.93, 0.97, 1.07), vec3(1.08, 1.00, 0.90), batch_drift);

	float macro_stain = value_noise(plane * 0.043 + 4.9);
	float district_stain = value_noise(plane * 0.161 + 9.2);
	colour *= 0.88 + 0.17 * macro_stain + 0.08 * district_stain;
	float tyre_and_foot_wear = smoothstep(0.76, 0.97, value_noise(plane * vec2(0.085, 0.31) + 27.0));
	colour *= 1.0 - tyre_and_foot_wear * 0.10;
	float gum_spots = smoothstep(0.968, 0.996, value_noise(plane * 7.3 + 41.0));
	colour *= 1.0 - gum_spots * 0.18;
	// Grime collects unevenly along joints.
	float joint_grime = (1.0 - smoothstep(0.0, 0.09, edge_distance)) * (0.35 + 0.65 * district_stain);
	colour *= 1.0 - joint_grime * 0.10;

	// Mortar varies per segment: mostly dark, sometimes sand-filled.
	vec3 joint_colour = mix(vec3(0.10, 0.095, 0.09), vec3(0.42, 0.38, 0.31), step(0.78, hash12(vec2(row_id * 3.7, segment_id * 1.3))));
	colour = mix(colour, joint_colour, joint * 0.80);
	colour *= 1.0 + bevel * 0.035;

	ALBEDO = colour;
	if (use_textures) {
		NORMAL_MAP = sample_concrete_normal(plane);
		NORMAL_MAP_DEPTH = normal_strength;
	}
	ROUGHNESS = clamp(base_roughness + (paver_hash - 0.5) * 0.13 + joint * 0.025 - tyre_and_foot_wear * 0.035 - replaced * 0.08 + aged * 0.05, 0.58, 1.0);
	METALLIC = 0.0;
	SPECULAR = 0.28;
	AO = 1.0 - joint * 0.24;
}
