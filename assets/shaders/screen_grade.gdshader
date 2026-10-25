shader_type canvas_item;
// Поверх мира (под интерфейсом): полосы скорости, когда машина быстрее своего обычного
// предела (ускорители, ускорение после дрифта, нитро, рывок).
// Экран 384×216 — полосы получаются крупными пиксельными штрихами.

// 0..1 — сила полос скорости (ставит ScreenEffects).
uniform float speed : hint_range(0.0, 1.0) = 0.0;

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

void fragment() {
	vec2 centered = UV - vec2(0.5);
	centered.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float radius = length(centered);
	// Полосы: лучи от центра, каждые 1/12 с меняются.
	float ray = floor((atan(centered.y, centered.x) + PI) * 48.0);
	float lit = step(0.82, hash(ray * 1.37 + floor(TIME * 12.0) * 7.13));
	float streak = lit * smoothstep(0.3, 0.75, radius) * speed * 0.45;
	COLOR = vec4(vec3(1.0), streak);
}
