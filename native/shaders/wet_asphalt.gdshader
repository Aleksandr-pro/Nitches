shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// Drive-база пользователя: wet_asphalt.gdshader, адаптированная под RichTown
// и мобильный рендер. В ясную погоду это прежде всего ТЁМНЫЙ сухой асфальт:
// небольшая влажность только добавляет пятна и редкие лужи, но не превращает
// дорогу в зеркало неба. Текстуры берутся в мировых XZ-координатах, поэтому
// зерно имеет одинаковый физический масштаб на прямых и поворотах.
//
// cull_disabled здесь не декоративная опция: дорожное полотно — критичная
// поверхность, и оно не должно исчезать из-за winding процедурного меша.
// Сама геометрия дополнительно строится с правильным для Godot порядком
// вершин (см. NativeWorldBuilder._build_road_mesh).

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_textures = true;
uniform vec4 asphalt_color : source_color = vec4(0.030, 0.032, 0.036, 1.0);
uniform float texture_brightness : hint_range(0.05, 1.5) = 0.58;
uniform float tex_scale : hint_range(0.01, 2.0) = 0.14;

uniform float wetness : hint_range(0.0, 1.0) = 0.12;
uniform float puddle_amount : hint_range(0.0, 1.0) = 0.22;
uniform float dry_roughness : hint_range(0.0, 1.0) = 0.94;
uniform float wet_roughness : hint_range(0.0, 1.0) = 0.48;
uniform float puddle_roughness : hint_range(0.0, 1.0) = 0.16;
uniform float bump_strength : hint_range(0.0, 2.0) = 0.55;

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

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;

	float puddle_noise = fbm2(p * 0.10);
	float puddle_threshold = mix(1.05, 0.58, puddle_amount * wetness);
	float puddle = smoothstep(puddle_threshold, puddle_threshold + 0.08, puddle_noise);
	float damp = clamp(wetness * (0.35 + 0.65 * vnoise(p * 0.065 + 31.0)), 0.0, 1.0);
	float grain = mix(0.86, 1.14, vnoise(p * 4.2));

	if (use_textures) {
		vec2 coords = p * tex_scale;
		ALBEDO = texture(albedo_tex, coords).rgb * texture_brightness * grain;
		vec3 n = texture(normal_tex, coords).rgb * 2.0 - 1.0;
		NORMAL_MAP = n;
		NORMAL_MAP_DEPTH = bump_strength * (1.0 - puddle * 0.9);
	} else {
		ALBEDO = asphalt_color.rgb * grain;
		float e = 0.08;
		float height_c = vnoise(p * 5.0);
		float height_x = vnoise((p + vec2(e, 0.0)) * 5.0);
		float height_y = vnoise((p + vec2(0.0, e)) * 5.0);
		NORMAL_MAP = normalize(vec3((height_c - height_x) * 2.0, (height_c - height_y) * 2.0, 1.0));
		NORMAL_MAP_DEPTH = bump_strength * (1.0 - puddle * 0.9);
	}

	// Влажный асфальт темнеет; лужи не должны становиться светлее дороги.
	ALBEDO *= mix(1.0, 0.72, damp);
	ALBEDO = mix(ALBEDO, ALBEDO * vec3(0.58, 0.62, 0.68), puddle);

	ROUGHNESS = mix(dry_roughness, wet_roughness, damp);
	ROUGHNESS = mix(ROUGHNESS, puddle_roughness, puddle);
	METALLIC = 0.0;
	SPECULAR = mix(0.34, 0.56, max(damp, puddle));
}
