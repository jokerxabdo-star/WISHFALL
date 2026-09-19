shader_type canvas_item;

uniform bool flash_white = false;

void fragment() {
    vec4 texture_color = texture(TEXTURE, UV);
    if (flash_white) {
        COLOR = vec4(1.0, 1.0, 1.0, texture_color.a);
    } else {
        COLOR = texture_color;
    }
}