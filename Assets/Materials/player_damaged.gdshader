shader_type canvas_item;

uniform bool flash_red = false;

void fragment() {
    vec4 texture_color = texture(TEXTURE, UV);
    if (flash_red) {
        COLOR = vec4(1.0, 0.15, 0.15, texture_color.a);
    } else {
        COLOR = texture_color;
    }
}