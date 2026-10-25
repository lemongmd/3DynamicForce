shader_type spatial;
// Тени на жидкость не ложатся: тень эстакады на воде с отражением выглядела странно
// (просьба автора ремейка) — эстакаду и так видно в отражении.
render_mode shadows_disabled;
// Жидкий фон (вода, кислота, масло): картинка оригинала двумя слоями, текущими в разные
// стороны, с волнами (смещение по синусам) и бликами там, где светлые места обоих слоёв
// совпадают. Плитка — в мировых координатах (как раньше triplanar), фильтр Nearest:
// пиксели остаются крупными, а вода «живёт».
// Отражения (WaterReflection, если включены у трассы): картинка зеркальной камеры по
// положению пикселя на экране, дрожит по волнам; чем более косо смотрим — тем сильнее
// (френель). Без отражений — матовая жидкость без широкого блика (он делал воду «пластиковой»).

uniform sampler2D albedo_texture : source_color, filter_nearest_mipmap, repeat_enable;
// Сколько метров занимает одна картинка.
uniform float tile_size = 8.0;
// Течение, м/с (в оригинале 8 и −16 px/с = 1 и −2 м/с).
uniform vec2 flow = vec2(1.0, -2.0);
// Размах волн, м.
uniform float wobble = 0.35;
// Сила бликов.
uniform float sparkle : hint_range(0.0, 1.0) = 0.5;
// Отражение: картинка зеркальной камеры (отражённая по горизонтали) и её сила (0 — нет).
uniform sampler2D reflection_texture : source_color, filter_nearest, repeat_disable;
uniform float reflection_strength : hint_range(0.0, 1.0) = 0.0;
// Доля отражения, когда смотрим сверху / вскользь.
uniform float reflection_min = 0.38;
uniform float reflection_max = 0.75;
// Рябь отражения, доля экрана.
uniform float reflection_ripple = 0.012;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_position.xz;
	vec2 wave = vec2(sin(p.y * 0.35 + TIME * 1.3), cos(p.x * 0.3 + TIME * 1.1)) * wobble;
	vec2 uv_a = (p + wave + flow * TIME) / tile_size;
	vec2 uv_b = (p * 0.87 - wave + vec2(-flow.y, flow.x) * 0.6 * TIME) / tile_size + vec2(0.37, 0.61);
	vec3 a = texture(albedo_texture, uv_a).rgb;
	vec3 b = texture(albedo_texture, uv_b).rgb;
	float light = min(dot(a, vec3(0.333)), dot(b, vec3(0.333)));
	vec3 base = mix(a, b, 0.4);
	float glint = smoothstep(0.7, 0.92, light) * sparkle;
	if (reflection_strength > 0.0) {
		// Рябь — по тем же волнам и по картинке (светлые места слоёв сдвигают сильнее).
		vec2 ripple = (wave / max(wobble, 0.001) + (a.rg - b.rg)) * reflection_ripple;
		vec2 ruv = vec2(1.0 - SCREEN_UV.x, SCREEN_UV.y) + ripple;
		vec3 reflected = texture(reflection_texture, clamp(ruv, vec2(0.001), vec2(0.999))).rgb;
		float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
		float k = mix(reflection_min, reflection_max, fresnel) * reflection_strength;
		// Отражение — свечением (не зависит от освещения), вода под ним — темнее.
		ALBEDO = base * (1.0 - k) * 0.9;
		EMISSION = reflected * k + vec3(glint);
	} else {
		ALBEDO = base + vec3(glint);
	}
	// Матовая: широкий блик солнца на плоскости воды смотрелся как пластик.
	ROUGHNESS = 0.9;
	SPECULAR = 0.15;
}
