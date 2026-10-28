shader_type canvas_item;

// Frosted backdrop for the 0.2.34 menu panels.  The mipmapped
// screen texture gives a one-tap blur; the Panel's own StyleBox
// colour supplies the dark tint and its alpha controls how much
// of the blurred 3D scene remains visible.
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float blur_lod : hint_range(0.0, 5.0) = 2.6;

void fragment() {
    vec3 background = textureLod(screen_texture, SCREEN_UV, blur_lod).rgb;
    vec4 source = COLOR;
    COLOR.rgb = mix(background, source.rgb, source.a);
    COLOR.a = 1.0;
}
