shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// 0.2.14 opaque curtain-wall facade for background glass towers.
//
// Building Models No.4/No.5 already have real mullions, fins, floor
// slabs and occupied cores, but 0.2.13 shaded every glass surface with
// one bright blue StandardMaterial. On the phone that erased the
// geometry and made both towers read as a flat blue texture.
//
// This shader works in real metres in the merged model's own space.
// Each architectural bay/floor receives a deterministic tenant state:
// dark reflective glass, smoked glass, a lowered blind, or a warm/cool
// occupied interior. Roughness, alpha, normal tilt and night emission
// vary with that state, while subtle vertical weathering prevents the
// large capsule shells from looking like printed plastic. MODEL_MATRIX
// supplies a per-instance seed, so repeated No.4 towers do not share
// the same lit/off pattern.

uniform vec4 deep_glass_color : source_color = vec4(0.018, 0.037, 0.046, 1.0);
uniform vec4 smoke_glass_color : source_color = vec4(0.045, 0.070, 0.078, 1.0);
uniform vec4 blind_color : source_color = vec4(0.290, 0.270, 0.220, 1.0);
uniform vec4 warm_interior_color : source_color = vec4(0.100, 0.065, 0.038, 1.0);
uniform vec4 cool_interior_color : source_color = vec4(0.035, 0.055, 0.064, 1.0);
uniform float floor_height_m : hint_range(1.0, 6.0) = 3.42;
uniform float bay_width_m : hint_range(0.5, 4.0) = 1.65;
uniform float base_alpha : hint_range(0.05, 1.0) = 0.80;
uniform float material_seed = 0.0;
uniform float interior_light_strength : hint_range(0.0, 2.0) = 0.0;
uniform float weathering_strength : hint_range(0.0, 1.0) = 0.55;

varying vec3 local_metres;
varying vec3 local_normal;
varying vec3 world_pos;
varying float instance_seed;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm2(vec2 p) {
	return vnoise(p) * 0.68 + vnoise(p * 2.17 + 19.0) * 0.32;
}

void vertex() {
	vec3 basis_scale = vec3(
		length(MODEL_MATRIX[0].xyz),
		length(MODEL_MATRIX[1].xyz),
		length(MODEL_MATRIX[2].xyz)
	);
	local_metres = VERTEX * basis_scale;
	local_normal = NORMAL;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	instance_seed = hash13(vec3(
		floor(MODEL_MATRIX[3].x * 0.37),
		floor(MODEL_MATRIX[3].z * 0.41),
		material_seed * 17.0 + 3.0
	)) * 91.0;
}

void fragment() {
	vec3 n_local = normalize(local_normal);
	float horizontal_m = local_metres.x;
	float face_id = 23.0;
	if (abs(n_local.x) >= abs(n_local.z)) {
		horizontal_m = local_metres.z;
		face_id = n_local.x > 0.0 ? 11.0 : 17.0;
	} else {
		face_id = n_local.z > 0.0 ? 23.0 : 29.0;
	}
	if (abs(n_local.y) > 0.72) {
		horizontal_m = local_metres.x + local_metres.z;
		face_id = 37.0;
	}

	vec2 facade_m = vec2(horizontal_m, local_metres.y);
	vec2 facade_grid = vec2(
		facade_m.x / max(bay_width_m, 0.05),
		facade_m.y / max(floor_height_m, 0.05)
	);
	vec2 cell = floor(facade_grid);
	vec2 cell_frac = fract(facade_grid);
	float seed = material_seed * 131.0 + instance_seed + face_id;

	// Tenant zones span about three bays. The individual pane hash then
	// breaks the zone just enough to avoid a repeating printed facade.
	vec2 tenant_cell = vec2(floor(cell.x / 3.0), cell.y);
	float tenant = hash13(vec3(tenant_cell, seed));
	float tenant_b = hash13(vec3(tenant_cell + vec2(19.0, 7.0), seed + 5.0));
	float pane = hash13(vec3(cell, seed + 11.0));
	float pane_b = hash13(vec3(cell + vec2(31.0, 3.0), seed + 17.0));
	float pane_c = hash13(vec3(cell + vec2(7.0, 43.0), seed + 23.0));

	vec3 surface_color = mix(
		deep_glass_color.rgb,
		smoke_glass_color.rgb,
		smoothstep(0.08, 0.92, tenant)
	);
	float surface_roughness = mix(0.052, 0.155, tenant)
		+ (pane - 0.5) * 0.045;
	float surface_alpha = mix(base_alpha + 0.045, base_alpha - 0.035, tenant);

	float blind_zone = step(0.56, tenant) * (1.0 - step(0.83, tenant));
	float blind_drop = mix(0.28, 0.74, tenant_b);
	float blind_mask = blind_zone
		* step(1.0 - blind_drop, cell_frac.y)
		* step(0.16, pane);
	vec3 blind_tint = blind_color.rgb * (0.80 + 0.34 * pane_b);
	surface_color = mix(surface_color, blind_tint, blind_mask * 0.88);
	surface_roughness = mix(surface_roughness, 0.34, blind_mask * 0.72);
	surface_alpha = mix(surface_alpha, 0.91, blind_mask);

	float warm_zone = step(0.86, tenant);
	surface_color = mix(surface_color, warm_interior_color.rgb, warm_zone * 0.68);
	surface_alpha = mix(surface_alpha, base_alpha - 0.13, warm_zone * 0.72);

	float cool_open_pane = step(0.93, pane_b) * (1.0 - blind_mask);
	surface_color = mix(
		surface_color,
		mix(cool_interior_color.rgb, warm_interior_color.rgb, step(0.62, pane_c)),
		cool_open_pane * 0.62
	);
	surface_alpha = mix(surface_alpha, base_alpha - 0.18, cool_open_pane * 0.70);
	surface_color *= 0.92 + 0.16 * pane_c;

	float camera_distance = distance(CAMERA_POSITION_WORLD, world_pos);
	float detail_fade = 1.0 - smoothstep(85.0, 230.0, camera_distance);
	float far_average = smoothstep(180.0, 460.0, camera_distance);

	// Broad tonal drift and rain/dust streaks. They follow the facade's
	// vertical direction rather than a 2D image's fixed screen axes.
	float broad_weather = fbm2(vec2(facade_m.x * 0.035, facade_m.y * 0.018) + seed * 0.01);
	float vertical_streak = smoothstep(
		0.76,
		0.97,
		vnoise(vec2(facade_m.x * 3.1, facade_m.y * 0.025) + seed * 0.03)
	) * weathering_strength * mix(0.35, 1.0, detail_fade);
	surface_color *= 0.94 + 0.10 * broad_weather;
	surface_color = mix(
		surface_color,
		surface_color * vec3(1.05, 0.99, 0.89),
		vertical_streak * 0.28
	);
	surface_roughness += (broad_weather - 0.5) * 0.045
		+ vertical_streak * 0.085;

	// A very thin dark gasket/sill shadow at the actual floor and bay
	// pitch reinforces the Blender mullions at street distance. It is
	// derivative-faded so it cannot become one-pixel sparkle far away.
	float edge_m = min(
		min(cell_frac.x, 1.0 - cell_frac.x) * bay_width_m,
		min(cell_frac.y, 1.0 - cell_frac.y) * floor_height_m
	);
	float edge_aa = max(fwidth(edge_m) * 1.35, 0.004);
	float gasket = (1.0 - smoothstep(0.022, 0.022 + edge_aa, edge_m))
		* detail_fade;
	float sill_shadow = (1.0 - smoothstep(0.015, 0.16, cell_frac.y))
		* detail_fade;
	surface_color *= 1.0 - gasket * 0.42 - sill_shadow * 0.16;
	surface_roughness += gasket * 0.20;
	surface_alpha = mix(surface_alpha, 0.94, gasket * 0.72);

	// Far LOD: retain the dark smoked read, but average the finest pane
	// contrast before the phone's reduced 3D buffer turns it to noise.
	vec3 far_color = mix(deep_glass_color.rgb, smoke_glass_color.rgb, 0.46);
	surface_color = mix(surface_color, far_color, far_average * 0.62);
	surface_roughness = mix(surface_roughness, 0.135, far_average * 0.55);
	surface_alpha = mix(surface_alpha, base_alpha + 0.02, far_average * 0.50);

	float view_fresnel = pow(
		1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0),
		3.0
	);
	surface_alpha = mix(surface_alpha, 0.94, view_fresnel * 0.48);

	float wave = sin((cell_frac.x + pane * 0.37) * 6.28318)
		* 0.012 * detail_fade;
	vec2 panel_tilt = vec2(pane_b - 0.5, pane_c - 0.5)
		* 0.105 * mix(0.35, 1.0, detail_fade);
	vec3 panel_normal = normalize(vec3(panel_tilt.x + wave, panel_tilt.y, 1.0));
	NORMAL_MAP = panel_normal * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.62;

	float lit_hash = hash13(vec3(cell + vec2(53.0, 29.0), seed + 41.0));
	float lit_pane = step(0.70, lit_hash) * interior_light_strength;
	vec3 lit_color = mix(
		vec3(1.0, 0.62, 0.30),
		vec3(0.72, 0.84, 1.0),
		step(0.78, pane_c)
	);
	EMISSION = lit_color * lit_pane
		* (0.42 + 0.72 * pane_b)
		* (1.0 - gasket * 0.86)
		* (1.0 - blind_mask * 0.42);

	// Generic background towers are solid boxes with no occupied core
	// behind the skin. Composite against a near-black interior here so
	// the opaque pass keeps correct depth between MultiMesh instances.
	ALBEDO = mix(vec3(0.003, 0.005, 0.006), surface_color, clamp(surface_alpha, 0.05, 0.97));
	METALLIC = 0.0;
	ROUGHNESS = clamp(surface_roughness, 0.035, 0.48);
	SPECULAR = 0.94;
	CLEARCOAT = 0.72;
	CLEARCOAT_ROUGHNESS = 0.075;
	AO = clamp(1.0 - gasket * 0.22 - sill_shadow * 0.16, 0.62, 1.0);
}
