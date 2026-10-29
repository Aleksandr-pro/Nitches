shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// Drive-база пользователя: wet_asphalt.gdshader, переработанная в 0.2.6 в
// многослойный дорожный материал. Мировые XZ-координаты дают одинаковый
// физический масштаб зерна и макроизноса, а UV дорожного меша дают
// направленные вдоль каждой улицы колеи, швы, заплатки и масляные пятна.
// В ясную погоду это сухой асфальт с локальной влажностью у водостоков, а
// не зеркальная мокрая поверхность.
//
// cull_disabled здесь не декоративная опция: дорожное полотно — критичная
// поверхность, и оно не должно исчезать из-за winding процедурного меша.
// Сама геометрия дополнительно строится с правильным для Godot порядком
// вершин (см. NativeWorldBuilder._build_road_mesh).

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wear_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_textures = true;
uniform bool use_wear_texture = false;
uniform vec4 asphalt_color : source_color = vec4(0.030, 0.032, 0.036, 1.0);
uniform float texture_brightness : hint_range(0.05, 2.0) = 1.08;
uniform float tex_scale : hint_range(0.01, 2.0) = 0.115;

uniform float wetness : hint_range(0.0, 1.0) = 0.12;
uniform float puddle_amount : hint_range(0.0, 1.0) = 0.22;
uniform float dry_roughness : hint_range(0.0, 1.0) = 0.94;
uniform float wet_roughness : hint_range(0.0, 1.0) = 0.48;
uniform float puddle_roughness : hint_range(0.0, 1.0) = 0.16;
uniform float bump_strength : hint_range(0.0, 2.0) = 0.62;

varying vec3 world_pos;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm2(vec2 p) {
	return vnoise(p) * 0.68 + vnoise(p * 2.13 + 17.0) * 0.32;
}

float band_mask(float value, float center, float width) {
	return 1.0 - smoothstep(width * 0.45, width, abs(value - center));
}

float rect_mask(vec2 uv, vec2 lo, vec2 hi, vec2 aa) {
	vec2 lower = smoothstep(lo - aa, lo + aa, uv);
	vec2 upper = vec2(1.0) - smoothstep(hi - aa, hi + aa, uv);
	return lower.x * lower.y * upper.x * upper.y;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float lateral = clamp(UV.x, 0.0, 1.0) * 2.0 - 1.0;
	float abs_lateral = abs(lateral);
	// _build_road_mesh() stores travelled metres / 18 in UV.y.
	float road_s = max(UV.y, 0.0) * 18.0;
	float camera_distance = distance(CAMERA_POSITION_WORLD, world_pos);
	float detail_fade = 1.0 - smoothstep(70.0, 190.0, camera_distance);

	float edge_grime = smoothstep(0.76, 1.0, abs_lateral);
	float gutter = smoothstep(0.84, 0.995, abs_lateral);

	float puddle_noise = fbm2(p * 0.10) + gutter * 0.065;
	float puddle_threshold = mix(1.05, 0.58, puddle_amount * wetness);
	float puddle = smoothstep(puddle_threshold, puddle_threshold + 0.08, puddle_noise);
	float damp = clamp(
		wetness * (0.35 + 0.65 * vnoise(p * 0.065 + 31.0))
		+ gutter * 0.10 * max(wetness, 0.25),
		0.0,
		1.0
	);
	float grain = mix(0.86, 1.14, vnoise(p * 4.2));
	// Narrow road-aligned wet streaks modulate the PBR highlight instead
	// of rendering a costly screen-space or planar reflection.
	float streak_noise = fbm2(vec2(road_s * 0.10 + TIME * 0.018, lateral * 5.2));
	float wet_streak = smoothstep(0.57, 0.79, streak_noise)
		* (1.0 - smoothstep(0.88, 1.0, abs_lateral))
		* clamp(damp * 0.82 + puddle * 0.55, 0.0, 1.0)
		* mix(0.40, 1.0, detail_fade);

	// Polished wheel paths follow the road itself. Four broad bands cover
	// both two-lane streets and the four-lane Boulevard/Corniche without
	// depending on a north/south texture direction baked into one image.
	float wheel_variation = 0.72 + 0.28 * vnoise(vec2(road_s * 0.035, lateral * 1.7) + 8.1);
	float wheel_track = max(
		max(band_mask(abs_lateral, 0.20, 0.105), band_mask(abs_lateral, 0.37, 0.105)),
		max(band_mask(abs_lateral, 0.63, 0.105), band_mask(abs_lateral, 0.80, 0.105))
	) * wheel_variation * mix(0.38, 1.0, detail_fade);

	float oil_noise = vnoise(vec2(UV.x * 6.5, road_s * 0.020) + 4.7);
	float oil = smoothstep(0.67, 0.89, oil_noise)
		* (1.0 - smoothstep(0.25, 0.90, abs_lateral));

	// Transverse construction joints every 12 m and weaker longitudinal
	// paving seams. Screen-space derivatives keep them from turning into
	// one-pixel sparkle at the reduced Android 3D resolution.
	float joint_fraction = fract(road_s / 12.0);
	float joint_distance = min(joint_fraction, 1.0 - joint_fraction) * 12.0;
	float joint_aa = max(fwidth(road_s) * 1.4, 0.012);
	float joint = (1.0 - smoothstep(0.018, 0.018 + joint_aa, joint_distance))
		* (0.55 + 0.45 * vnoise(vec2(lateral * 7.0, road_s * 0.13)))
		* detail_fade;

	float seam_distance = min(
		min(abs(UV.x - 0.25), abs(UV.x - 0.50)),
		abs(UV.x - 0.75)
	);
	float seam_aa = max(fwidth(UV.x) * 1.4, 0.0012);
	float seam = (1.0 - smoothstep(0.0022, 0.0022 + seam_aa, seam_distance))
		* (0.45 + 0.55 * vnoise(vec2(road_s * 0.11, UV.x * 19.0)))
		* detail_fade;

	// Rectangular resurfacing patches are generated in lane-sized cells.
	// Their dark perimeter reads as tar sealing; only about one cell in
	// five is repaired, so the street looks maintained rather than ruined.
	vec2 patch_grid = vec2(UV.x * 4.0, road_s / 17.0);
	vec2 patch_cell = floor(patch_grid);
	float patch_seed = hash21(patch_cell + vec2(19.7, 7.3));
	float repair_patch = 0.0;
	float tar_border = 0.0;
	if (patch_seed < 0.20) {
		float patch_x = hash21(patch_cell + vec2(3.1, 9.7));
		float patch_y = hash21(patch_cell + vec2(11.3, 5.9));
		vec2 patch_lo = vec2(0.12 + 0.28 * patch_x, 0.14 + 0.26 * patch_y);
		vec2 patch_hi = vec2(
			patch_lo.x + 0.38 + 0.24 * hash21(patch_cell + vec2(23.7, 1.9)),
			patch_lo.y + 0.34 + 0.30 * hash21(patch_cell + vec2(7.7, 29.1))
		);
		vec2 patch_uv = fract(patch_grid);
		vec2 patch_aa = max(fwidth(patch_grid) * 1.2, vec2(0.006));
		float patch_outer = rect_mask(
			patch_uv,
			patch_lo - vec2(0.026, 0.018),
			patch_hi + vec2(0.026, 0.018),
			patch_aa
		);
		float patch_inner = rect_mask(patch_uv, patch_lo, patch_hi, patch_aa);
		repair_patch = patch_inner;
		tar_border = clamp(patch_outer - patch_inner, 0.0, 1.0);
	}

	float wear_luma = 0.065;
	float crack = 0.0;
	if (use_textures) {
		vec2 coords = p * tex_scale;
		vec2 rotated = mat2(vec2(0.9239, 0.3827), vec2(-0.3827, 0.9239)) * p;
		vec3 micro = texture(albedo_tex, coords).rgb;
		vec3 macro = texture(albedo_tex, rotated * 0.027 + vec2(0.37, 0.11)).rgb;
		vec3 asphalt = mix(micro, macro, 0.30);

		if (use_wear_texture) {
			vec3 wear = texture(wear_tex, rotated * 0.030 + vec2(0.13, 0.71)).rgb;
			wear_luma = dot(wear, vec3(0.299, 0.587, 0.114));
			// These thresholds are in linear sampler space, not the
			// 0..255 values seen in an image viewer: asphalt_city has a
			// measured median luminance of about 0.065 after sRGB decode.
			float wear_contrast = clamp(wear_luma / 0.065, 0.48, 1.45);
			asphalt *= mix(1.0, wear_contrast, 0.38);
			crack = (1.0 - smoothstep(0.032, 0.052, wear_luma)) * detail_fade;
			asphalt = mix(asphalt, asphalt * vec3(0.72, 0.73, 0.76), crack * 0.55);
		}

		ALBEDO = asphalt * texture_brightness * grain;
		vec3 normal_main = texture(normal_tex, coords).rgb * 2.0 - 1.0;
		vec3 normal_detail = texture(
			normal_tex,
			rotated * 0.34 + vec2(0.61, 0.23)
		).rgb * 2.0 - 1.0;
		vec2 combined_xy = normal_main.xy * 0.78
			+ normal_detail.xy * 0.48 * detail_fade;
		vec3 combined_normal = normalize(vec3(combined_xy, 1.0));
		// Godot expects NORMAL_MAP in texture RGB form. Feeding it the
		// already-unpacked -1..1 vector caused overly hard, incorrectly
		// centred relief in the copied Drive shader.
		NORMAL_MAP = combined_normal * 0.5 + 0.5;
		NORMAL_MAP_DEPTH = bump_strength * (1.0 - puddle * 0.9);
	} else {
		ALBEDO = asphalt_color.rgb * grain;
		float e = 0.08;
		float height_c = vnoise(p * 5.0);
		float height_x = vnoise((p + vec2(e, 0.0)) * 5.0);
		float height_y = vnoise((p + vec2(0.0, e)) * 5.0);
		vec3 fallback_normal = normalize(vec3(
			(height_c - height_x) * 2.0,
			(height_c - height_y) * 2.0,
			1.0
		));
		NORMAL_MAP = fallback_normal * 0.5 + 0.5;
		NORMAL_MAP_DEPTH = bump_strength * (1.0 - puddle * 0.9);
	}

	// Road-aligned ageing sits above both texture octaves, so it remains
	// coherent when the same world-space grain crosses an intersection.
	ALBEDO *= 1.0 - 0.115 * wheel_track;
	ALBEDO *= 1.0 - 0.20 * oil;
	ALBEDO *= 1.0 - 0.17 * joint;
	ALBEDO *= 1.0 - 0.11 * seam;
	ALBEDO *= 1.0 - 0.16 * repair_patch;
	ALBEDO *= 1.0 - 0.30 * tar_border;
	ALBEDO = mix(ALBEDO, ALBEDO * vec3(0.74, 0.67, 0.55), edge_grime * 0.34);
	float lane_dust = band_mask(abs_lateral, 0.50, 0.24)
		* vnoise(vec2(road_s * 0.018, 5.2)) * 0.05;
	ALBEDO *= 1.0 + lane_dust;

	// Влажный асфальт темнеет; лужи не должны становиться светлее дороги.
	ALBEDO *= mix(1.0, 0.72, damp);
	ALBEDO = mix(ALBEDO, ALBEDO * vec3(0.58, 0.62, 0.68), puddle);

	// 0.2.19 reference corridor: RichTown Boulevard itself is a freshly
	// resurfaced charcoal carriageway, while side streets retain the
	// older grey aggregate.  The world-space mask is confined to the
	// exported X=760, Z=-430..430 avenue and its intersection pads.
	float boulevard_mask = (1.0 - smoothstep(11.2, 13.2, abs(world_pos.x - 760.0)))
		* smoothstep(-438.0, -428.0, world_pos.z)
		* (1.0 - smoothstep(428.0, 438.0, world_pos.z));
	ALBEDO = mix(ALBEDO, ALBEDO * vec3(0.43, 0.45, 0.49), boulevard_mask * 0.86);
	ALBEDO = mix(ALBEDO, ALBEDO * vec3(0.86, 0.90, 0.96), wet_streak * 0.16);

	float surface_roughness = dry_roughness;
	surface_roughness += (wear_luma - 0.065) * 0.65;
	surface_roughness -= wheel_track * 0.10 + oil * 0.18;
	surface_roughness += crack * 0.045 + joint * 0.05 + repair_patch * 0.015;
	surface_roughness = clamp(surface_roughness, 0.70, 0.985);
	surface_roughness = mix(surface_roughness, 0.82, boulevard_mask * 0.72);

	ROUGHNESS = mix(surface_roughness, wet_roughness, damp);
	ROUGHNESS = mix(ROUGHNESS, puddle_roughness, puddle);
	ROUGHNESS = mix(ROUGHNESS, max(wet_roughness - 0.08, 0.36), wet_streak * 0.24);
	METALLIC = 0.0;
	SPECULAR = clamp(mix(0.30, 0.56, max(damp, puddle)) + wet_streak * 0.08, 0.0, 1.0);
	AO = clamp(1.0 - crack * 0.18 - joint * 0.12 - tar_border * 0.15, 0.62, 1.0);
}
