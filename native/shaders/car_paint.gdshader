shader_type spatial;
// Автомобильная краска из Drive-базы «Для godot», адаптированная для
// Mustang и Mobile renderer: металлик, мелкие блёстки, лаковый слой
// (clearcoat) и цветной отлив на краях. Назначается только на поверхности
// Paint/PaintSecondary, чтобы не затирать стёкла, шины и оптику модели.

uniform vec4 base_color : source_color = vec4(0.55, 0.02, 0.03, 1.0);
uniform vec4 flake_color : source_color = vec4(1.0, 0.82, 0.7, 1.0);
uniform vec4 fresnel_color : source_color = vec4(0.95, 0.25, 0.1, 1.0);
uniform float metallic_amount : hint_range(0.0, 1.0) = 0.68;
uniform float roughness_amount : hint_range(0.0, 1.0) = 0.19;
uniform float clearcoat_amount : hint_range(0.0, 1.0) = 1.0;
uniform float clearcoat_rough : hint_range(0.0, 1.0) = 0.075;
uniform float flake_density = 180.0;
uniform float flake_strength : hint_range(0.0, 2.0) = 0.5;
uniform float fresnel_strength : hint_range(0.0, 1.0) = 0.25;

varying vec3 obj_pos;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

void vertex() {
	obj_pos = VERTEX;
}

void fragment() {
	vec3 cell = floor(obj_pos * flake_density);
	float h = hash13(cell);
	float is_flake = step(0.82, h);

	// У каждой блёстки своя ориентация, поэтому она вспыхивает под своим углом обзора
	vec3 jitter = vec3(hash13(cell + 1.0), hash13(cell + 2.0), hash13(cell + 3.0)) - 0.5;
	vec3 flake_n = normalize(NORMAL + jitter * 0.8);
	float sparkle = pow(max(dot(flake_n, VIEW), 0.0), 24.0) * is_flake;

	float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);

	vec3 paint = mix(base_color.rgb, flake_color.rgb, is_flake * 0.35);
	ALBEDO = mix(paint, fresnel_color.rgb, f * fresnel_strength);
	// Drive-версия светилась слишком заметно ночью: блёстки должны ловить
	// свет/отражения, а не быть самостоятельным источником света.
	EMISSION = flake_color.rgb * sparkle * flake_strength * 0.32;

	METALLIC = metallic_amount;
	ROUGHNESS = clamp(roughness_amount - is_flake * 0.07, 0.03, 1.0);
	// PBR specular irradiance is supplied by the current sky and the nearest
	// local ReflectionProbe (Godot Mobile has no SSR pass).
	SPECULAR = 0.88;
	CLEARCOAT = clearcoat_amount;
	CLEARCOAT_ROUGHNESS = clearcoat_rough;
}
