shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

// Mobile-friendly stylized PBR water: animated multi-scale wave normals,
// small geometric swell, environment/reflection-probe specular and depth foam.
uniform float wave_time = 0.0;
uniform float wave_height = 0.62;
uniform vec2 wind_direction = vec2(0.82, 0.57);
uniform vec4 deep_color : source_color = vec4(0.012, 0.19, 0.29, 0.97);
uniform vec4 shallow_color : source_color = vec4(0.035, 0.48, 0.58, 0.94);
uniform vec4 foam_color : source_color = vec4(0.76, 0.92, 0.88, 1.0);
uniform float foam_strength = 0.66;
uniform float normal_strength = 0.78;
uniform float reflection_strength = 0.82;
uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;

varying vec3 water_world_position;

// Returns height and its analytic X/Z derivatives for a directional wave.
vec3 wave_sample(vec2 p, vec2 direction, float wavelength, float amplitude, float speed, float t) {
	vec2 d = normalize(direction);
	float k = 6.28318530718 / wavelength;
	float phase = dot(p, d) * k - t * speed;
	float c = cos(phase);
	return vec3(amplitude * sin(phase), amplitude * k * c * d.x, amplitude * k * c * d.y);
}

vec3 combined_waves(vec2 p, float t) {
	vec2 wind = normalize(wind_direction);
	vec3 a = wave_sample(p, wind, 66.0, 0.23, 0.78, t);
	vec3 b = wave_sample(p, vec2(wind.y, -wind.x), 37.0, 0.14, 0.62, t);
	vec3 c = wave_sample(p, normalize(wind + vec2(0.38, 0.22)), 19.0, 0.075, 0.92, t);
	return a + b + c;
}

float water_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float water_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 local = fract(p);
	local = local * local * (3.0 - 2.0 * local);
	float a = water_hash(cell);
	float b = water_hash(cell + vec2(1.0, 0.0));
	float c = water_hash(cell + vec2(0.0, 1.0));
	float d = water_hash(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, local.x), mix(c, d, local.x), local.y);
}

void vertex() {
	vec3 world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 waves = combined_waves(world_position.xz, wave_time);
	VERTEX.y += waves.x * wave_height;
	water_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = water_world_position.xz;
	vec3 waves = combined_waves(p, wave_time);
	// Add two short, low-amplitude ripples in the pixel shader. Their analytic
	// slopes keep highlights alive even when the sea mesh is viewed at distance.
	vec3 ripple_a = wave_sample(p, vec2(0.71, 0.70), 8.5, 0.024, 1.48, wave_time);
	vec3 ripple_b = wave_sample(p, vec2(-0.42, 0.91), 5.2, 0.012, 1.86, wave_time);
	vec2 slope = (waves.yz * wave_height + ripple_a.yz + ripple_b.yz) * normal_strength;
	vec3 world_normal = normalize(vec3(-slope.x, 1.0, -slope.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(world_normal, 0.0)).xyz);

	float scene_raw_depth = texture(scene_depth, SCREEN_UV).r;
	vec4 scene_view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, scene_raw_depth, 1.0);
	float scene_distance = -scene_view.z / max(scene_view.w, 0.0001);
	float surface_distance = -VERTEX.z;
	float water_depth = scene_raw_depth >= 0.99999 ? 30.0 : max(scene_distance - surface_distance, 0.0);
	float shallow = smoothstep(0.25, 7.5, water_depth);
	float shoreline = 1.0 - smoothstep(0.18, 1.45, water_depth);
	float foam = 0.0;
	if (shoreline > 0.001) {
		float foam_pattern = water_noise(p * 0.34 + vec2(wave_time * 0.025, -wave_time * 0.018));
		foam = shoreline * smoothstep(0.52, 0.79, foam_pattern) * foam_strength;
	}

	float facing = max(dot(normalize(NORMAL), normalize(VIEW)), 0.0);
	float fresnel = pow(1.0 - facing, 5.0);
	vec3 water_color = mix(deep_color.rgb, shallow_color.rgb, 1.0 - shallow);
	water_color = mix(water_color, vec3(0.30, 0.63, 0.69), fresnel * 0.24);
	ALBEDO = mix(water_color, foam_color.rgb, foam);
	ROUGHNESS = mix(0.105, 0.23, shallow * 0.48 + foam * 0.5);
	METALLIC = 0.12;
	SPECULAR = mix(0.58, 0.92, fresnel) * reflection_strength;
	ALPHA = mix(deep_color.a, shallow_color.a, 1.0 - shallow);
	ALPHA = max(ALPHA, foam * 0.94);
}
