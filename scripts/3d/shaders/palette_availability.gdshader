shader_type canvas_item;
uniform bool unavailable = false;
void fragment() {
    vec4 color = texture(TEXTURE, UV) * COLOR;
    if (unavailable) {
        float grey = dot(color.rgb, vec3(0.299, 0.587, 0.114));
        color.rgb = vec3(grey * 0.55);
        color.a *= 0.65;
    }
    COLOR = color;
}
