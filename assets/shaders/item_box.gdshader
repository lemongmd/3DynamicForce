shader_type spatial;
// Коробка предметов: полупрозрачная, как в оригинале (непрозрачность 0.5), плюс наш «стеклянный»
// вид (просьба автора оригинала): края светятся (френель), по высоте бежит радужный перелив
// и снизу вверх проходит полоса блика. Видна и задняя стенка — куб кажется объёмным.
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

// Грани коробки оригинала (атлас модели item_box.glb).
uniform sampler2D albedo_texture : source_color, filter_nearest;
uniform float opacity : hint_range(0.0, 1.0) = 0.5;
// Сила радужного перелива.
uniform float rainbow : hint_range(0.0, 1.0) = 0.45;

vec3 hue_to_rgb(float hue) {
	return clamp(abs(fract(hue + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
}

void fragment() {
	vec4 tex = texture(albedo_texture, UV);
	vec3 world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float fresnel = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.0);
	vec3 shimmer = hue_to_rgb(fract(world.y * 0.3 + world.x * 0.1 + TIME * 0.35));
	// Полоса блика снизу вверх (ступеньками по 1/8 м — пиксельно, как всё в игре).
	float stepped_y = floor(world.y * 8.0) / 8.0;
	float band = step(abs(fract(stepped_y * 0.5 - TIME * 0.6) - 0.5), 0.06);
	vec3 color = mix(tex.rgb, shimmer, rainbow * 0.45) + shimmer * fresnel * 0.6 + vec3(band * 0.35);
	float alpha = tex.a * opacity + fresnel * 0.3 + band * 0.2;
	if (!FRONT_FACING) {
		alpha *= 0.45;
	}
	ALBEDO = color;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
