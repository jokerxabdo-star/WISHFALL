shader_type canvas_item;

uniform vec4 shimmer_color : source_color = vec4(1.0, 1.0, 1.0, 0.8);
uniform float speed = 1.5;
uniform float width = 0.2;

void fragment() {
    vec4 tex_color = texture(TEXTURE, UV);
    float shimmer = smoothstep(0.0, width, 0.5 - abs(mod(TIME * speed + UV.x - UV.y, 2.0) - 1.0));
    COLOR = vec4(mix(tex_color.rgb, shimmer_color.rgb, shimmer * shimmer_color.a), tex_color.a);
}