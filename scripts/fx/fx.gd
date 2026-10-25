class_name Fx
extends RefCounted
## Эффекты частиц ремейка. В оригинале их почти нет (след машины, вспышка парирования),
## это наше дополнение по просьбе автора ремейка: дым дрифта, пламя ускорения, пыль
## и взрывная волна при приземлении, искры об стену, «бонк» при остановке, взрыв бомбы,
## искры коробки предметов.
##
## Спрайты — пиксельные картинки assets/textures/fx/* (белые с тенями; цвет задаёт
## пресет), частицы — CPUParticles3D (работают и в рендере Compatibility).
## Пресет — словарь параметров (см. PRESETS); emitter() делает непрерывный источник,
## burst() — разовый выброс, который сам удаляется.

const TEXTURES := {
	&"puff": preload("res://assets/textures/fx/fx_puff.png"),
	&"flame": preload("res://assets/textures/fx/fx_flame.png"),
	&"spark": preload("res://assets/textures/fx/fx_spark.png"),
	&"star": preload("res://assets/textures/fx/fx_star.png"),
	&"ring": preload("res://assets/textures/fx/fx_ring.png"),
	# В 4 раза детальнее (build_fx_textures.gd) — для приземления (просьба автора оригинала:
	# «эффект приземления сильно пиксельный»).
	&"puff_hd": preload("res://assets/textures/fx/fx_puff_hd.png"),
	&"spark_hd": preload("res://assets/textures/fx/fx_spark_hd.png"),
}
const RING_TEXTURE := preload("res://assets/textures/fx/fx_ring_hd.png")
## Цвета искр дрифта по стадиям заряда (как мини-турбо: синие, оранжевые, фиолетовые).
const DRIFT_STAGE_COLORS := [
	[Color(0.75, 0.95, 1.0), Color(0.25, 0.6, 1.0), Color(0.1, 0.25, 0.9)],
	[Color(1.0, 0.95, 0.5), Color(1.0, 0.55, 0.1), Color(0.9, 0.2, 0.05)],
	[Color(1.0, 0.75, 1.0), Color(0.85, 0.3, 1.0), Color(0.5, 0.1, 0.8)],
]

## Параметры пресета (все необязательны):
##   texture — ключ TEXTURES; size — сторона спрайта, м; amount; lifetime;
##   velocity — [мин, макс] м/с; direction; spread — °; flatness (1 — только по земле);
##   gravity; damping — [мин, макс]; scale — [мин, макс]; curve — &"shrink" / &"grow" / &"pop";
##   colors — цвета по времени жизни (с прозрачностью); hue — разброс оттенка 0..1;
##   sphere — радиус области появления, м; box — полуразмеры области; spin — °/с вращения;
##   retro — ретро-вид (Nintendo 64 / SNES): цвета меняются ступеньками, края пикселей
##   жёсткие (без плавного растворения), частица исчезает разом.
const PRESETS := {
	# Дым из-под задних колёс в дрифте (непрерывный), ретро: клубы белые -> серые ступеньками.
	&"drift_smoke": {
		"texture": &"puff", "size": 1.2, "amount": 24, "lifetime": 0.6,
		"velocity": [0.6, 1.6], "direction": Vector3(0, 1, 0.6), "spread": 35.0,
		"gravity": Vector3(0, 1.2, 0), "damping": [1.0, 2.0], "scale": [0.8, 1.3], "curve": &"grow",
		"colors": [Color(1, 1, 1), Color(0.85, 0.85, 0.9), Color(0.65, 0.65, 0.72), Color(0.65, 0.65, 0.72, 0.0)],
		"box": Vector3(0.7, 0.05, 0.1), "retro": true,
	},
	# Искры «заряженного» дрифта (непрерывный), ретро; цвет — по стадии (DRIFT_STAGE_COLORS,
	# ставит CarFx): отпусти кнопку — ускорение тем сильнее, чем выше стадия.
	&"drift_sparks": {
		"texture": &"spark", "size": 0.6, "amount": 36, "lifetime": 0.3,
		"velocity": [3.0, 6.0], "direction": Vector3(0, 0.6, 1), "spread": 50.0,
		"gravity": Vector3(0, -14, 0), "scale": [0.8, 1.3], "curve": &"shrink",
		"colors": DRIFT_STAGE_COLORS[0] + [Color(0, 0, 0, 0)],
		"box": Vector3(0.7, 0.05, 0.1), "retro": true,
	},
	# Пламя из выхлопа, пока машина быстрее своего обычного предела (непрерывный).
	&"boost_flame": {
		"texture": &"flame", "size": 1.0, "amount": 40, "lifetime": 0.3,
		"velocity": [4.0, 7.0], "direction": Vector3(0, 0.15, 1), "spread": 12.0,
		"gravity": Vector3.ZERO, "scale": [0.8, 1.2], "curve": &"shrink",
		"colors": [Color(1, 1, 0.75), Color(1, 0.7, 0.15), Color(0.95, 0.25, 0.05, 0.6), Color(0.3, 0.1, 0.05, 0.0)],
		"box": Vector3(0.25, 0.05, 0.05),
	},
	# Пыль во все стороны по земле при приземлении.
	&"landing_dust": {
		"texture": &"puff_hd", "size": 1.1, "amount": 20, "lifetime": 0.6,
		"velocity": [5.0, 9.0], "direction": Vector3(1, 0, 0), "spread": 180.0, "flatness": 1.0,
		"gravity": Vector3(0, 1.5, 0), "damping": [10.0, 14.0], "scale": [0.8, 1.4], "curve": &"grow",
		"colors": [Color(1, 0.97, 0.9, 0.9), Color(0.85, 0.8, 0.7, 0.5), Color(0.7, 0.65, 0.6, 0.0)],
		"sphere": 1.0,
	},
	# Искры вверх при жёстком приземлении.
	# Брызги помидора, упавшего на дорогу.
	&"tomato_splash": {
		"texture": &"puff_hd", "size": 0.55, "amount": 16, "lifetime": 0.45,
		"velocity": [4.0, 8.0], "direction": Vector3(0, 0.6, 0), "spread": 80.0,
		"gravity": Vector3(0, -18, 0), "scale": [0.7, 1.2], "curve": &"shrink",
		"colors": [Color(1, 0.35, 0.3), Color(0.85, 0.1, 0.12), Color(0.6, 0.05, 0.08, 0.0)],
		"sphere": 0.6,
	},
	&"landing_sparks": {
		"texture": &"spark_hd", "size": 0.4, "amount": 14, "lifetime": 0.5,
		"velocity": [5.0, 9.0], "direction": Vector3(0, 1, 0), "spread": 60.0,
		"gravity": Vector3(0, -20, 0), "scale": [0.8, 1.2], "curve": &"shrink",
		"colors": [Color(1, 1, 0.7), Color(1, 0.6, 0.15), Color(1, 0.3, 0.1, 0.0)],
		"sphere": 0.8,
	},
	# Искры об стену (направление задаётся при выбросе).
	&"wall_sparks": {
		"texture": &"spark", "size": 0.35, "amount": 12, "lifetime": 0.35,
		"velocity": [4.0, 8.0], "direction": Vector3(0, 1, 0), "spread": 55.0,
		"gravity": Vector3(0, -18, 0), "scale": [0.8, 1.2], "curve": &"shrink",
		"colors": [Color(1, 1, 0.8), Color(1, 0.75, 0.25), Color(1, 0.4, 0.1, 0.0)],
		"sphere": 0.3,
	},
	# «Бонк»: звёздочки над машиной, когда её остановило (промах парирования).
	&"bonk": {
		"texture": &"star", "size": 0.9, "amount": 6, "lifetime": 0.7,
		"velocity": [3.0, 5.0], "direction": Vector3(0, 1, 0), "spread": 70.0,
		"gravity": Vector3(0, -9, 0), "scale": [0.9, 1.1], "curve": &"pop", "spin": 360.0,
		"colors": [Color(1, 0.95, 0.3), Color(1, 0.85, 0.2), Color(1, 0.6, 0.1, 0.0)],
		"sphere": 0.5,
	},
	# Радужные искры коробки предметов.
	&"item_sparkle": {
		"texture": &"spark", "size": 0.45, "amount": 18, "lifetime": 0.5,
		"velocity": [4.0, 7.0], "direction": Vector3(0, 1, 0), "spread": 180.0,
		"gravity": Vector3(0, -6, 0), "damping": [3.0, 5.0], "scale": [0.8, 1.3], "curve": &"shrink",
		"colors": [Color(1, 0.3, 0.3), Color(1, 0.3, 0.3), Color(1, 0.3, 0.3, 0.0)], "hue": 1.0,
		"sphere": 0.8,
	},
	# Взрыв бомбы: огонь и дым.
	&"explosion_fire": {
		"texture": &"flame", "size": 1.4, "amount": 22, "lifetime": 0.45,
		"velocity": [4.0, 9.0], "direction": Vector3(0, 1, 0), "spread": 90.0,
		"gravity": Vector3(0, 3, 0), "damping": [6.0, 9.0], "scale": [0.9, 1.5], "curve": &"pop",
		"colors": [Color(1, 1, 0.8), Color(1, 0.75, 0.2), Color(1, 0.3, 0.05, 0.7), Color(0.3, 0.1, 0.05, 0.0)],
		"sphere": 0.8,
	},
	&"explosion_smoke": {
		"texture": &"puff", "size": 1.6, "amount": 14, "lifetime": 1.1,
		"velocity": [2.0, 4.0], "direction": Vector3(0, 1, 0), "spread": 70.0,
		"gravity": Vector3(0, 2.5, 0), "damping": [2.0, 3.0], "scale": [0.8, 1.4], "curve": &"grow",
		"colors": [Color(0.35, 0.33, 0.33, 0.0), Color(0.3, 0.28, 0.28, 0.8), Color(0.45, 0.43, 0.43, 0.0)],
		"sphere": 1.0,
	},
}


## Непрерывный источник по пресету (emitting = false; включать по месту).
## Частицы в мировых координатах: дым остаётся позади едущей машины.
static func emitter(preset_name: StringName) -> CPUParticles3D:
	var preset: Dictionary = PRESETS[preset_name]
	var particles := CPUParticles3D.new()
	particles.name = String(preset_name).to_pascal_case()
	particles.emitting = false
	particles.local_coords = false
	particles.amount = int(preset.get("amount", 16))
	particles.lifetime = float(preset.get("lifetime", 0.5))
	particles.lifetime_randomness = 0.3
	particles.mesh = _quad(preset)
	particles.direction = preset.get("direction", Vector3.UP)
	particles.spread = float(preset.get("spread", 45.0))
	particles.flatness = float(preset.get("flatness", 0.0))
	particles.gravity = preset.get("gravity", Vector3(0, -9.8, 0))
	var velocity: Array = preset.get("velocity", [1.0, 2.0])
	particles.initial_velocity_min = velocity[0]
	particles.initial_velocity_max = velocity[1]
	var damping: Array = preset.get("damping", [0.0, 0.0])
	particles.damping_min = damping[0]
	particles.damping_max = damping[1]
	var scale_range: Array = preset.get("scale", [1.0, 1.0])
	particles.scale_amount_min = scale_range[0]
	particles.scale_amount_max = scale_range[1]
	particles.scale_amount_curve = _scale_curve(preset.get("curve", &"shrink"))
	particles.color_ramp = _gradient(preset.get("colors", [Color.WHITE, Color(1, 1, 1, 0)]), bool(preset.get("retro", false)))
	var hue := float(preset.get("hue", 0.0))
	particles.hue_variation_min = -hue
	particles.hue_variation_max = hue
	var spin := float(preset.get("spin", 0.0))
	particles.angular_velocity_min = -spin
	particles.angular_velocity_max = spin
	particles.angle_min = -180.0 if spin != 0.0 else 0.0
	particles.angle_max = 180.0 if spin != 0.0 else 0.0
	if preset.has("box"):
		particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		particles.emission_box_extents = preset["box"]
	elif preset.has("sphere"):
		particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		particles.emission_sphere_radius = float(preset["sphere"])
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return particles


## Разовый выброс пресетов names в точке at (родитель — parent, обычно рядом с машиной).
## direction — заменить направление вылета (искры от стены). Узел удаляется сам.
static func burst(names: Array, parent: Node, at: Vector3, direction: Vector3 = Vector3.ZERO) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var holder := Node3D.new()
	holder.name = "FxBurst"
	parent.add_child(holder)
	holder.global_position = at
	var longest := 0.0
	for preset_name in names:
		var particles := emitter(preset_name)
		particles.one_shot = true
		particles.explosiveness = 0.9
		if direction != Vector3.ZERO:
			particles.direction = direction
		holder.add_child(particles)
		particles.emitting = true
		longest = maxf(longest, particles.lifetime)
	holder.get_tree().create_timer(longest + 0.2, false).timeout.connect(holder.queue_free)


## Кольцо ударной волны на земле: растёт до radius за time и тает.
static func ring(parent: Node, at: Vector3, radius: float = 4.0, time: float = 0.35) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var sprite := Sprite3D.new()
	sprite.name = "FxRing"
	sprite.texture = RING_TEXTURE
	sprite.axis = Vector3.AXIS_Y
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.shaded = false
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sprite.modulate = Color(1, 0.95, 0.8)
	# pixel_size так, чтобы при масштабе 1 диаметр был 2·radius.
	sprite.pixel_size = radius * 2.0 / RING_TEXTURE.get_width()
	parent.add_child(sprite)
	sprite.global_position = at + Vector3.UP * 0.08
	sprite.scale = Vector3.ONE * 0.2
	var tween := sprite.create_tween().set_parallel()
	tween.tween_property(sprite, ^"scale", Vector3.ONE, time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(sprite, ^"transparency", 1.0, time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(sprite.queue_free)


## Тряхнуть камеры, следящие поблизости (TopDownCamera.shake_from).
static func shake(node: Node, at: Vector3, strength: float) -> void:
	if node != null and node.is_inside_tree():
		node.get_tree().call_group(TopDownCamera.GROUP, &"shake_from", at, strength)


static func _quad(preset: Dictionary) -> QuadMesh:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if bool(preset.get("retro", false)):
		# Ретро: пиксель либо есть, либо нет — без полупрозрачных краёв.
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		material.alpha_scissor_threshold = 0.5
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.albedo_texture = TEXTURES[preset.get("texture", &"puff")]
	var quad := QuadMesh.new()
	var size := float(preset.get("size", 1.0))
	quad.size = Vector2(size, size)
	quad.material = material
	return quad


## stepped — цвета меняются ступеньками (ретро), а не плавно.
static func _gradient(colors: Array, stepped: bool = false) -> Gradient:
	var gradient := Gradient.new()
	if stepped:
		gradient.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	var offsets := PackedFloat32Array()
	var packed := PackedColorArray()
	for i in colors.size():
		offsets.append(float(i) / maxf(colors.size() - 1, 1))
		packed.append(colors[i])
	gradient.offsets = offsets
	gradient.colors = packed
	return gradient


static func _scale_curve(kind: StringName) -> Curve:
	var curve := Curve.new()
	match kind:
		&"grow":
			curve.add_point(Vector2(0.0, 0.5))
			curve.add_point(Vector2(1.0, 1.0))
		&"pop":
			curve.add_point(Vector2(0.0, 0.3))
			curve.add_point(Vector2(0.2, 1.0))
			curve.add_point(Vector2(1.0, 0.6))
		_:
			curve.add_point(Vector2(0.0, 1.0))
			curve.add_point(Vector2(1.0, 0.2))
	return curve
