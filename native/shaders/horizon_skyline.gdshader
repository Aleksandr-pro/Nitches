shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_front;

uniform sampler2D skyline_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 skyline_tint : source_color = vec4(1.0);
uniform vec4 window_tint : source_color = vec4(1.0, 0.66, 0.30, 1.0);
uniform float night_factor : hint_range(0.0, 1.0) = 0.0;
uniform float layer_opacity : hint_range(0.0, 1.0) = 0.72;
uniform float layer_seed = 1.0;
uniform float skyline_density : hint_range(24.0, 240.0) = 144.0;

varying vec2 skyline_uv;

float hash1(float value) {
	return fract(sin(value * 127.1 + 311.7) * 43758.5453);
}

void vertex() {
	skyline_uv = UV;
}

void fragment() {
	// The 4096x512 RGBA panorama supplies the actual skyline silhouette and
	// facade variation. Texture V is flipped because the UV mesh runs bottom-up.
	vec2 sample_uv = vec2(skyline_uv.x, 1.0 - skyline_uv.y);
	vec4 plate = texture(skyline_tex, sample_uv);
	float cell = floor(skyline_uv.x * skyline_density);
	float local_x = fract(skyline_uv.x * skyline_density);
	float window_col = floor(local_x * 11.0);
	float window_row = floor(skyline_uv.y * 42.0);
	float window_seed = hash1(cell * 17.0 + window_col * 3.7 + window_row * 29.3 + layer_seed * 11.0);
	float window_grid = step(0.16, fract(local_x * 11.0))
		* (1.0 - step(0.82, fract(local_x * 11.0)))
		* step(0.20, fract(skyline_uv.y * 42.0))
		* (1.0 - step(0.72, fract(skyline_uv.y * 42.0)));
	float windows = plate.a * window_grid * step(0.81, window_seed) * night_factor;

	vec3 color = plate.rgb * skyline_tint.rgb;
	color = mix(color, window_tint.rgb * 1.45, windows);
	ALBEDO = color;
	EMISSION = window_tint.rgb * windows * 1.6;
	ALPHA = plate.a * layer_opacity;
}
