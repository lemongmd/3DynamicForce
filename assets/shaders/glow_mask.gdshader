shader_type spatial;
// Картинка + свечение по маске (тыквы «Хэллоуина»: светится только вырезанная рожица;
// призрак: маска — сама картинка, рожица не светится). StandardMaterial3D в Compatibility
// маску свечения (emission_texture) не применяет — светилась вся тыква.
// Двусторонний: у призрака снизу открытый подол, изнутри он темнее (inside_shade).
render_mode cull_disabled;

uniform sampler2D albedo_texture : source_color, filter_nearest_mipmap;
uniform sampler2D glow_texture : source_color, filter_nearest_mipmap;
uniform vec4 glow_color : source_color = vec4(1.0, 0.62, 0.2, 1.0);
uniform float glow_energy = 2.6;
uniform float roughness_value = 0.75;
uniform float inside_shade = 1.0;

void fragment() {
	float shade = FRONT_FACING ? 1.0 : inside_shade;
	ALBEDO = texture(albedo_texture, UV).rgb * shade;
	EMISSION = texture(glow_texture, UV).rgb * glow_color.rgb * glow_energy * shade;
	ROUGHNESS = roughness_value;
}
