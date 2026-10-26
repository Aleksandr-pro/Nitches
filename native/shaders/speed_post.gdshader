shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, depth_test_disabled, depth_draw_never;
// Полноэкранный пост-эффект в стиле гоночных игр из Drive-базы «Для godot».
// Работает в рендерерах Mobile и Forward+. Вешается на QuadMesh через
// NativeSpeedPost, дочерний узел игровой Camera3D.
// Цвета обрабатываются в линейном HDR до тональной компрессии окружения.
// Настройки ниже облегчены относительно исходника: на телефоне эффект
// включается только на скорости и не платит цену лишнего sharpen-прохода.

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;

group_uniforms speed_effects;
uniform float speed : hint_range(0.0, 1.0) = 0.0;
uniform float blur_strength : hint_range(0.0, 0.2) = 0.045;
uniform float clear_radius : hint_range(0.0, 0.6) = 0.24;
uniform float aberration : hint_range(0.0, 0.03) = 0.006;
uniform float speed_lines : hint_range(0.0, 1.0) = 0.28;
uniform vec2 focus_point = vec2(0.5, 0.52);

group_uniforms look;
uniform float sharpen : hint_range(0.0, 1.0) = 0.0;
uniform float saturation : hint_range(0.0, 2.0) = 1.0;
uniform float contrast : hint_range(0.5, 1.5) = 1.06;
uniform vec3 shadow_tint : source_color = vec3(0.95, 0.97, 1.0);
uniform vec3 highlight_tint : source_color = vec3(1.02, 1.0, 0.96);
uniform float split_strength : hint_range(0.0, 1.0) = 0.28;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.22;
uniform float grain : hint_range(0.0, 0.1) = 0.005;

const int SAMPLES = 8;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void vertex() {
	// Растягиваем квад на весь экран (reversed-Z: z = 1.0 это ближняя плоскость)
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = 1.0 / VIEWPORT_SIZE;
	float aspect = VIEWPORT_SIZE.x / VIEWPORT_SIZE.y;

	vec2 toward = uv - focus_point;
	float dist = length(toward * vec2(aspect, 1.0));
	float mask = smoothstep(clear_radius, 0.85, dist);

	vec3 base = textureLod(screen_tex, uv, 0.0).rgb;

	// Лёгкая резкость (unsharp mask)
	if (sharpen > 0.001) {
		vec3 around = textureLod(screen_tex, uv + vec2(px.x, 0.0), 0.0).rgb
			+ textureLod(screen_tex, uv - vec2(px.x, 0.0), 0.0).rgb
			+ textureLod(screen_tex, uv + vec2(0.0, px.y), 0.0).rgb
			+ textureLod(screen_tex, uv - vec2(0.0, px.y), 0.0).rgb;
		base += (base - around * 0.25) * sharpen;
	}

	vec3 col = base;

	// Радиальный motion blur: центр (машина) остаётся чётким, края размываются
	float amt = blur_strength * speed * mask;
	if (amt > 0.0005) {
		vec3 acc = base;
		float wsum = 1.0;
		for (int i = 1; i < SAMPLES; i++) {
			float t = float(i) / float(SAMPLES - 1);
			float w = 1.0 - t * 0.6;
			acc += textureLod(screen_tex, uv - toward * amt * t, 0.0).rgb * w;
			wsum += w;
		}
		col = acc / wsum;

		// Хроматическая аберрация только по краям и только на скорости
		float ca = aberration * speed * mask;
		col.r = mix(col.r, textureLod(screen_tex, uv + toward * ca, 0.0).r, 0.7);
		col.b = mix(col.b, textureLod(screen_tex, uv - toward * ca, 0.0).b, 0.7);
	}

	// Цветокор: насыщенность, split toning (холодные тени, тёплый свет), контраст
	float luma = dot(col, vec3(0.2126, 0.7152, 0.0722));
	col = mix(vec3(luma), col, saturation);
	float sh = 1.0 - smoothstep(0.0, 0.35, luma);
	float hi = smoothstep(0.3, 1.2, luma);
	col *= mix(vec3(1.0), shadow_tint, sh * split_strength);
	col *= mix(vec3(1.0), highlight_tint, hi * split_strength);
	col = pow(max(col, vec3(0.0)) / 0.18, vec3(contrast)) * 0.18;

	// Линии скорости по краям на высокой скорости
	if (speed_lines > 0.001 && speed > 0.55) {
		vec2 d = toward * vec2(aspect, 1.0);
		float ang = atan(d.y, d.x) / TAU + 0.5;
		float id = floor(ang * 140.0);
		float tick = floor(TIME * 24.0);
		float line = step(0.92, hash21(vec2(id, tick)));
		line *= smoothstep(0.4, 0.9, dist) * smoothstep(0.55, 1.0, speed);
		col += vec3(line * speed_lines * 0.35);
	}

	// Subtle lens falloff stays circular on landscape phone displays.
	float vig = smoothstep(0.24, 0.78, length((uv - 0.5) * vec2(aspect, 1.0)));
	col *= 1.0 - vig * (vignette_strength + 0.18 * speed);

	// Плёночное зерно
	float n = hash21(uv * VIEWPORT_SIZE + fract(TIME) * 100.0) - 0.5;
	col += n * grain * (1.0 - clamp(luma, 0.0, 1.0) * 0.5);

	// Color grade, vignette and fine grain are intentionally always active;
	// radial blur/CA/lines remain speed-gated above.
	ALBEDO = max(col, vec3(0.0));
}
