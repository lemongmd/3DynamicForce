shader_type spatial;
// Лужа «как водичка» (просьба автора оригинала): лёд и лужи карт, пятна мороженого.
// Форма — из картинки оригинала (её прозрачность не дрожит), внутри картинка чуть колышется,
// от середины расходятся кольца ряби, по поверхности вспыхивают блики. Всё ступеньками по
// пикселям картинки — вода остаётся пиксельной, как остальная игра.
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

uniform sampler2D albedo_texture : source_color, filter_nearest, repeat_disable;
// Цвет лужи (цвет экземпляра оригинала: лёд Снежной — голубой, лужи Шинозавода — оранжевые).
uniform vec4 tint : source_color = vec4(1.0);
// Прозрачность объекта (появление и таяние — ставит скрипт).
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
// Пикселей в картинке по ширине — шаг ступенек эффектов.
uniform float pixels = 64.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 cell = floor(UV * pixels) / pixels;
	vec2 wobble = vec2(sin(cell.y * 23.0 + TIME * 2.1), cos(cell.x * 19.0 + TIME * 1.7)) / pixels;
	vec4 shape = texture(albedo_texture, UV);
	vec3 water = texture(albedo_texture, UV + wobble).rgb;
	// Рябь: кольца от середины, бегут наружу.
	float ring = step(0.82, sin(length(cell - vec2(0.5)) * 46.0 - TIME * 3.5));
	// Блики: редкие пиксели вспыхивают и гаснут.
	vec2 spark_cell = floor(cell * pixels * 0.5);
	float spark = step(0.97, hash(spark_cell + floor(TIME * 2.5)));
	// Кромка лужи светлее (там, где рядом кончается картинка).
	float edge = 1.0 - texture(albedo_texture, UV + vec2(1.5 / pixels, 1.5 / pixels)).a;
	vec3 color = water * tint.rgb * COLOR.rgb + vec3(ring * 0.14 + spark * 0.55 + edge * 0.18);
	ALBEDO = color;
	ALPHA = clamp(shape.a * tint.a * COLOR.a * opacity * (0.9 + ring * 0.1), 0.0, 1.0);
}
