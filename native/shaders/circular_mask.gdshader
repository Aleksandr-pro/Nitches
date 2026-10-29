shader_type canvas_item;

// Circular alpha mask used by the 0.2.33 HUD minimap.  Custom
// CanvasItem draw primitives do not all carry a control-space UV,
// so the mask is based on the interpolated local VERTEX position.
uniform vec2 rect_size = vec2(172.0, 172.0);
varying vec2 local_position;

void vertex() {
    local_position = VERTEX;
}

void fragment() {
    vec2 safe_size = max(rect_size, vec2(1.0, 1.0));
    vec2 centered = local_position / safe_size - vec2(0.5);
    float distance_from_center = length(centered) * 2.0;
    float alpha = 1.0 - smoothstep(0.985, 1.0, distance_from_center);
    COLOR.a *= alpha;
}
