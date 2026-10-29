shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, depth_test_disabled, cull_disabled, fog_disabled;

uniform vec3 shaft_tint : source_color = vec3(1.0, 0.78, 0.52);
uniform float shaft_intensity : hint_range(0.0, 1.0) = 0.0;

float soft_beam(float x, float centre, float width) {
	float d = abs(x - centre);
	return exp(-(d * d) / max(width * width, 0.00001));
}

void fragment() {
	vec2 uv = UV;
	float vertical_fade = smoothstep(0.015, 0.24, uv.y)
		* (1.0 - smoothstep(0.72, 0.99, uv.y));
	float beams = 0.0;
	beams += soft_beam(uv.x, 0.19 + (uv.y - 0.5) * 0.14, 0.025) * 0.75;
	beams += soft_beam(uv.x, 0.43 - (uv.y - 0.5) * 0.10, 0.018) * 0.58;
	beams += soft_beam(uv.x, 0.72 + (uv.y - 0.5) * 0.19, 0.032) * 0.68;
	float canopy_breakup = 0.82 + 0.18 * sin(uv.y * 58.0 + sin(uv.x * 41.0));
	ALBEDO = shaft_tint;
	ALPHA = clamp(beams * vertical_fade * canopy_breakup * shaft_intensity * 0.10, 0.0, 0.12);
}
