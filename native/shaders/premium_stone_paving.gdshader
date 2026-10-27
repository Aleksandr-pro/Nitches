shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// Native 0.2.18 premium stone promenade.  The source photograph already
// contains a large, irregular premium-slab pattern.  Two world-space
// orientations are blended with low-frequency noise so the 8 m photograph
// does not repeat as an obvious bathroom-tile grid across the boulevard,
// while a separate plaster micro-normal keeps close-range grain without
// inventing a second set of deep procedural joints.

uniform sampler2D stone_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D fine_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D fine_normal_texture : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_textures = true;
uniform vec4 tint : source_color = vec4(0.90, 0.86, 0.76, 1.0);
uniform float base_roughness : hint_range(0.45, 1.0) = 0.76;
uniform float texture_scale : hint_range(0.03, 0.35) = 0.115;
uniform float normal_strength : hint_range(0.0, 1.5) = 0.42;

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

vec2 dominant_plane(vec3 position_value, vec3 normal_value) {
	vec3 an = abs(normal_value);
	if (an.y >= an.x && an.y >= an.z) {
		return position_value.xz;
	}
	if (an.x >= an.z) {
		return position_value.zy;
	}
	return position_value.xy;
}

vec3 sample_stone_albedo(vec2 plane) {
	vec2 uv_a = plane * texture_scale;
	vec2 uv_b = vec2(plane.y, -plane.x) * texture_scale * 0.781 + vec2(0.317, 0.673);
	vec3 a = texture(stone_texture, uv_a).rgb;
	vec3 b = texture(stone_texture, uv_b).rgb;
	float blend = smoothstep(0.28, 0.72, value_noise(plane * 0.061 + 17.3));
	vec3 colour = mix(a, b, blend * 0.46);
	float fine = texture(fine_texture, plane * 1.37).r;
	colour *= 0.88 + 0.20 * fine;
	return colour;
}

vec3 sample_stone_normal(vec2 plane) {
	vec3 a = texture(fine_normal_texture, plane * 0.83).rgb * 2.0 - 1.0;
	vec3 b = texture(fine_normal_texture, vec2(plane.y, -plane.x) * 0.67 + vec2(0.211, 0.797)).rgb * 2.0 - 1.0;
	vec3 mixed = normalize(mix(a, b, 0.34) + vec3(0.0, 0.0, 0.001));
	return mixed * 0.5 + 0.5;
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 plane = dominant_plane(world_position, normalize(world_normal));
	vec3 colour = use_textures ? sample_stone_albedo(plane) : vec3(0.72, 0.68, 0.59);
	colour *= tint.rgb;

	float district_variation = value_noise(plane * 0.038 + 5.1);
	float footpath_variation = value_noise(plane * 0.147 + 11.7);
	colour *= 0.91 + 0.13 * district_variation + 0.06 * footpath_variation;
	float polished_wear = smoothstep(0.72, 0.96, value_noise(plane * vec2(0.077, 0.29) + 29.0));
	colour *= 1.0 - polished_wear * 0.055;

	ALBEDO = colour;
	if (use_textures) {
		NORMAL_MAP = sample_stone_normal(plane);
		NORMAL_MAP_DEPTH = normal_strength;
	}
	ROUGHNESS = clamp(base_roughness - polished_wear * 0.09 + (footpath_variation - 0.5) * 0.045, 0.52, 0.96);
	METALLIC = 0.0;
	SPECULAR = 0.38;
	AO = 1.0;
}
