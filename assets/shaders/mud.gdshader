shader_type spatial;
// Грязь «Хэллоуина» (MapZone.MUD): картинка плиткой по 8 px на метр и рваный край — пятно,
// а не прямоугольник. Форма — суперэллипс (roundness 2 — овал, больше — ближе к прямоугольнику),
// край — шум по клеткам 1/8 м (как пиксели картинки), у кромки темнее.

uniform sampler2D mud_texture : source_color, filter_nearest_mipmap, repeat_enable;
// Размер зоны, м (x — по оси X узла, y — по оси Z).
uniform vec2 size = vec2(6.0, 6.0);
uniform float roundness = 2.5;
// Насколько глубоко край может «вгрызаться» внутрь, м.
uniform float edge = 1.4;
// Метров на одну плитку картинки (32 px при 8 px на метр).
uniform float tile = 4.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 m = floor(UV * size * 8.0) / 8.0;
	vec2 half_size = size * 0.5;
	vec2 q = abs(m - half_size) / half_size;
	float r = pow(pow(q.x, roundness) + pow(q.y, roundness), 1.0 / roundness);
	// Край в метрах -> в долях «радиуса» (по короткой стороне).
	float unit = 1.0 / min(half_size.x, half_size.y);
	float limit = 1.0 - edge * unit * (noise(m * 1.3) * 0.65 + noise(m * 3.1) * 0.35);
	if (r > limit) {
		discard;
	}
	vec3 color = texture(mud_texture, m / tile).rgb * 1.15;
	if (r > limit - 0.3 * unit) {
		color *= 0.6;
	}
	ALBEDO = color;
	ROUGHNESS = 0.9;
}
