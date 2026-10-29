shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_front;

uniform vec4 skyline_tint : source_color = vec4(0.10, 0.17, 0.25, 0.82);
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
	float cell = floor(skyline_uv.x * skyline_density);
	float local_x = fract(skyline_uv.x * skyline_density);
	float seed = hash1(cell + layer_seed * 53.0);
	float height = mix(0.17, 0.72, pow(seed, 1.35));
	float tower = step(0.055, local_x) * (1.0 - step(0.94, local_x));
	float wall = (1.0 - smoothstep(height - 0.003, height + 0.003, skyline_uv.y)) * tower;
	float horizon_fade = smoothstep(0.005, 0.11, skyline_uv.y);
	float silhouette = wall * horizon_fade;

	float window_col = floor(local_x * 11.0);
	float window_row = floor(skyline_uv.y * 42.0);
	float window_seed = hash1(cell * 17.0 + window_col * 3.7 + window_row * 29.3 + layer_seed * 11.0);
	float window_grid = step(0.16, fract(local_x * 11.0))
		* (1.0 - step(0.82, fract(local_x * 11.0)))
		* step(0.20, fract(skyline_uv.y * 42.0))
		* (1.0 - step(0.72, fract(skyline_uv.y * 42.0)));
	float windows = silhouette * window_grid * step(0.81, window_seed) * night_factor;

	vec3 color = skyline_tint.rgb;
	color = mix(color, window_tint.rgb * 1.45, windows);
	ALBEDO = color;
	EMISSION = window_tint.rgb * windows * 1.6;
	ALPHA = silhouette * layer_opacity;
}
