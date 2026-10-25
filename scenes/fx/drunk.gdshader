// «Пьяный» экран водки — эффект Warp (layout) оригинала: картинка волнами смещается
// по x в зависимости от y и по y в зависимости от x. Параметры оригинала:
// период 64 px, амплитуда 8 px, скорость 1.5 (в пикселях экрана 384×216).
shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform vec2 period = vec2(64.0, 64.0);
uniform vec2 amplitude = vec2(8.0, 8.0);
uniform vec2 speed = vec2(1.5, 1.5);

void fragment() {
	vec2 pixel = SCREEN_UV / SCREEN_PIXEL_SIZE;
	vec2 offset = vec2(
		sin((pixel.y / period.y + TIME * speed.x) * 6.2831853) * amplitude.x,
		sin((pixel.x / period.x + TIME * speed.y) * 6.2831853) * amplitude.y);
	COLOR = texture(screen_texture, SCREEN_UV + offset * SCREEN_PIXEL_SIZE);
}
