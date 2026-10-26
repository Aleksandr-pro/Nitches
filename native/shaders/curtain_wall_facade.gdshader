shader_type spatial;
render_mode cull_back;

// Native 0.2.15 calibrated opaque curtain-wall facade for background towers.
// This is the transparent calibrated glass algorithm without an ALPHA output. The 0.2.14 phone
// screenshots proved that the first smoked calibration was much too dark:
// neighbouring tenant zones became brown/black camouflage at Q50. This
// calibration keeps the same real-bay logic, occupied-core depth and panel
// tilt, but lifts the source into neutral blue-grey glass, compresses the
// tonal steps and averages micro detail much earlier with distance. It also
// removes the expensive clearcoat layer and one value-noise octave; polished
// glass reflects through the ordinary specular/environment response.
uniform vec4 deep_glass_color : source_color = vec4(0.045, 0.072, 0.090, 1.0);
uniform vec4 smoke_glass_color : source_color = vec4(0.082, 0.118, 0.138, 1.0);
uniform vec4 blind_color : source_color = vec4(0.310, 0.300, 0.265, 1.0);
uniform vec4 cool_interior_color : source_color = vec4(0.055, 0.080, 0.095, 1.0);
uniform vec4 warm_interior_color : source_color = vec4(0.120, 0.083, 0.052, 1.0);
uniform float floor_height_m : hint_range(2.4, 5.0) = 3.42;
uniform float bay_width_m : hint_range(0.9, 3.0) = 1.60;
uniform float base_alpha : hint_range(0.45, 0.95) = 0.76;
uniform float material_seed = 0.0;
uniform float interior_light_strength : hint_range(0.0, 1.0) = 0.0;
uniform float weathering_strength : hint_range(0.0, 1.0) = 0.32;
uniform float detail_fade_start_m : hint_range(40.0, 240.0) = 90.0;
uniform float detail_fade_end_m : hint_range(160.0, 700.0) = 300.0;

varying vec3 world_position;
varying float instance_seed;

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

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
#ifdef USE_INSTANCING
	instance_seed = float(INSTANCE_ID) * 17.0;
#else
	instance_seed = 0.0;
#endif
}

void fragment() {
	vec3 world_normal = normalize(NORMAL);
	float horizontal = abs(world_normal.x) >= abs(world_normal.z)
		? (world_normal.x >= 0.0 ? -world_position.z : world_position.z)
		: (world_normal.z >= 0.0 ? world_position.x : -world_position.x);
	float face_seed = abs(world_normal.x) >= abs(world_normal.z)
		? (world_normal.x >= 0.0 ? 113.0 : 211.0)
		: (world_normal.z >= 0.0 ? 307.0 : 401.0);

	vec2 cell = vec2(horizontal / max(bay_width_m, 0.1), world_position.y / max(floor_height_m, 0.1));
	vec2 cell_id = floor(cell) + vec2(material_seed * 41.0 + face_seed, instance_seed);
	vec2 cell_frac = fract(cell);

	// Four-bay tenant groups share a broad state, but the tonal excursion is
	// deliberately narrow: at normal driving distance the surface should read
	// as one continuous sheet of glass with depth, not a checkerboard.
	vec2 tenant_id = vec2(floor(cell.x / 4.0) + material_seed * 41.0 + face_seed, cell_id.y);
	float tenant_hash = hash12(tenant_id * 1.73 + 9.1);
	float tenant_tone = smoothstep(0.08, 0.92, tenant_hash);
	float pane_hash = hash12(cell_id * 2.19 + 4.7);
	float pane_b = hash12(cell_id * 3.11 + 12.3);
	float pane_c = hash12(cell_id * 5.07 + 21.9);

	vec3 surface_color = mix(deep_glass_color.rgb, smoke_glass_color.rgb, 0.30 + 0.40 * tenant_tone);
	float surface_roughness = mix(0.080, 0.145, tenant_tone) + (pane_b - 0.5) * 0.022;
	float surface_alpha = mix(base_alpha + 0.015, base_alpha - 0.010, tenant_tone);

	// Quiet occupier states. Blinds are now a minority detail; warm rooms are
	// only a faint colour temperature change in daylight, becoming actual
	// emission only through interior_light_strength at sunset/night.
	float blind_zone = step(0.84, tenant_hash);
	float blind_start = mix(0.58, 0.82, pane_b);
	float slat = 0.88 + 0.12 * smoothstep(0.30, 0.70, fract(cell_frac.y * 18.0));
	float blind_mask = blind_zone * step(blind_start, cell_frac.y);
	surface_color = mix(surface_color, blind_color.rgb * slat, blind_mask * 0.58);
	surface_roughness = mix(surface_roughness, 0.30, blind_mask * 0.45);
	surface_alpha = mix(surface_alpha, 0.88, blind_mask * 0.42);

	float warm_zone = step(0.90, hash12(tenant_id * 2.47 + 31.7));
	surface_color = mix(surface_color, warm_interior_color.rgb, warm_zone * (1.0 - blind_mask) * 0.46);
	surface_alpha = mix(surface_alpha, base_alpha - 0.07, warm_zone * (1.0 - blind_mask) * 0.45);

	float cool_open_zone = step(0.955, hash12(tenant_id * 3.73 + 47.9));
	surface_color = mix(surface_color, cool_interior_color.rgb, cool_open_zone * (1.0 - blind_mask) * 0.40);
	surface_alpha = mix(surface_alpha, base_alpha - 0.10, cool_open_zone * 0.42);

	// A +/-3.5% pane tint is enough to break a CG sheet without producing
	// the rectangular patchwork visible in the 0.2.14 phone captures.
	surface_color *= 0.965 + 0.070 * pane_c;

	// One broad weather octave plus one elongated runoff octave. Both are
	// kept below the glass/sky contrast and disappear into the far average.
	float broad_weather = value_noise(vec2(horizontal * 0.055, world_position.y * 0.045) + material_seed * 7.0);
	surface_color *= 0.975 + 0.045 * broad_weather * weathering_strength;
	surface_roughness += (broad_weather - 0.5) * 0.020 * weathering_strength;
	float runoff = value_noise(vec2(horizontal * 2.10, world_position.y * 0.028) + material_seed * 3.0);
	float streak = smoothstep(0.82, 0.98, runoff) * weathering_strength;
	surface_color = mix(surface_color, vec3(0.115, 0.120, 0.118), streak * 0.16);
	surface_roughness += streak * 0.020;

	float distance_to_camera = length(world_position - CAMERA_POSITION_WORLD);
	float panel_pixel_footprint = max(fwidth(cell.x), fwidth(cell.y));
	float near_detail = (1.0 - smoothstep(detail_fade_start_m, detail_fade_end_m, distance_to_camera))
		* (1.0 - smoothstep(0.18, 0.72, panel_pixel_footprint));

	// Narrow, shallow gasketing. The Blender mullions/spandrels carry the
	// real panel rhythm; the shader no longer paints a second black frame.
	float edge_distance = min(min(cell_frac.x, 1.0 - cell_frac.x), min(cell_frac.y, 1.0 - cell_frac.y));
	float gasket = (1.0 - smoothstep(0.004, 0.018, edge_distance)) * near_detail;
	surface_color = mix(surface_color, surface_color * 0.72 + vec3(0.010, 0.012, 0.014), gasket * 0.16);
	surface_roughness += gasket * 0.070;
	surface_alpha = mix(surface_alpha, 0.90, gasket * 0.40);
	float lower_sill = step(cell_frac.y, 0.020) * near_detail;
	surface_color = mix(surface_color, surface_color * 0.90, lower_sill * 0.05);
	surface_alpha = mix(surface_alpha, 0.90, lower_sill * 0.08);

	// Distance average: beyond roughly 300 m (and earlier when a complete
	// bay is sub-pixel) the facade is a continuous neutral reflective skin.
	float far_average = smoothstep(detail_fade_start_m, detail_fade_end_m, distance_to_camera);
	far_average = max(far_average, smoothstep(0.30, 0.95, panel_pixel_footprint));
	vec3 far_color = mix(deep_glass_color.rgb, smoke_glass_color.rgb, 0.52);
	surface_color = mix(surface_color, far_color, far_average * 0.76);
	surface_roughness = mix(surface_roughness, 0.115, far_average * 0.62);
	surface_alpha = mix(surface_alpha, base_alpha + 0.005, far_average * 0.72);

	// Grazing views become more mirror-like and opaque; head-on views keep
	// the occupied core/curtain depth behind the Blender glass shells.
	vec3 view_dir = normalize(world_position - CAMERA_POSITION_WORLD);
	float fresnel = pow(1.0 - clamp(abs(dot(-view_dir, world_normal)), 0.0, 1.0), 3.0);
	surface_alpha = mix(surface_alpha, 0.88, fresnel * 0.28);

	// Small independent pane tilts make neighbouring sky reflections step
	// like installed low-iron units, without the funhouse warp in 0.2.14.
	vec2 pane_tilt = (vec2(pane_hash, pane_b) - 0.5) * 0.045 * near_detail;
	vec2 micro_wave = (vec2(
		value_noise(cell * vec2(2.7, 1.4) + material_seed),
		value_noise(cell * vec2(1.5, 3.1) + material_seed + 9.0)
	) - 0.5) * 0.006 * near_detail;
	vec2 normal_xy = clamp(pane_tilt + micro_wave, vec2(-0.055), vec2(0.055));
	NORMAL_MAP = vec3(normal_xy * 0.5 + 0.5, 1.0);
	NORMAL_MAP_DEPTH = 0.35;

	ALBEDO = surface_color;
	ROUGHNESS = clamp(surface_roughness, 0.045, 0.38);
	METALLIC = 0.0;
	SPECULAR = 0.62;

	float lit_window = warm_zone * step(0.38, hash12(tenant_id * 4.91 + 63.1)) * (1.0 - blind_mask * 0.72);
	EMISSION = vec3(1.0, 0.62, 0.32) * lit_window * interior_light_strength * 0.72;
}
