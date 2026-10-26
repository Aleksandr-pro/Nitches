shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_disabled;

// Drive-база пользователя: foliage_wind.gdshader, адаптированная к
// MultiMesh-растительности RichTown. Исходник использовал LIGHT прямо в
// fragment(), где этой встроенной переменной в Godot 4 нет; здесь вместо
// ручного освещения используется штатный BACKLIGHT, а PBR-освещение
// остаётся стандартным. Маска качания строится по реальной высоте меша
// (base_y/plant_height выставляет NativeWorldBuilder из AABB), для пальм —
// по UV.y листа: основание неподвижно, кончик движется сильнее.

uniform sampler2D leaf_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_texture = true;
uniform vec4 leaf_color : source_color = vec4(0.16, 0.38, 0.10, 1.0);
uniform vec4 leaf_tint : source_color = vec4(0.72, 0.96, 0.62, 1.0);
uniform float alpha_scissor : hint_range(0.0, 1.0) = 0.0;

uniform vec2 wind_dir = vec2(1.0, 0.35);
uniform float wind_speed : hint_range(0.0, 4.0) = 1.15;
uniform float bend_strength : hint_range(0.0, 0.4) = 0.035;
uniform float flutter_strength : hint_range(0.0, 0.2) = 0.012;
uniform float gust_strength : hint_range(0.0, 1.0) = 0.42;
uniform float base_y = 0.0;
uniform float plant_height = 2.0;
uniform bool use_uv_mask = false;
uniform float backlight_strength : hint_range(0.0, 1.5) = 0.38;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	vec2 instance_offset = MODEL_MATRIX[3].xz;
	float phase = hash12(instance_offset * 0.37) * 6.28318;
	float height_mask = clamp((VERTEX.y - base_y) / max(plant_height, 0.001), 0.0, 1.0);
	float mask = use_uv_mask ? clamp(UV.y, 0.0, 1.0) : height_mask;
	mask = mask * mask;

	vec2 travel = instance_offset * 0.055 - normalize(wind_dir) * TIME * wind_speed * 0.75;
	float gust = 0.5 + 0.5 * sin(travel.x + travel.y + phase * 0.23);
	gust = mix(1.0 - gust_strength, 1.0 + gust_strength, gust * gust);
	float sway = sin(TIME * wind_speed * 1.7 + phase) * bend_strength * gust;
	float flutter = sin(TIME * (7.0 + wind_speed * 2.0) + phase * 3.0 + VERTEX.x * 4.0 + VERTEX.z * 3.0) * flutter_strength;

	vec2 direction = normalize(wind_dir);
	VERTEX.xz += direction * sway * mask;
	VERTEX.x += flutter * direction.y * mask;
	VERTEX.z -= flutter * direction.x * mask;
	VERTEX.y -= abs(sway) * 0.18 * mask;
}

void fragment() {
	vec4 base = leaf_color;
	if (use_texture) {
		base = texture(leaf_texture, UV);
		ALBEDO = base.rgb * leaf_tint.rgb;
	} else {
		ALBEDO = leaf_color.rgb;
	}
	ALPHA = base.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor;
	ROUGHNESS = 0.95;
	METALLIC = 0.0;
	BACKLIGHT = ALBEDO * backlight_strength;
}
