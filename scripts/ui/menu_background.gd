class_name MenuBackground
extends Control
## Фон меню как в оригинале (слой Bg макета Menu, группа MenuBg):
##   * полосы menubg (16×224, градиент) по всей ширине колышутся волной: каждая уходит вверх
##     на 4 px и обратно за 2/3 с, с задержкой X/16/9 с — волна бежит вправо;
##   * цвет переливается от красного к оранжевому (tween offsetColor оригинала, туда-обратно
##     за 4/3 с); на красном экране оригинала и на оранжевом — один и тот же фон в разные моменты;
##   * контуры треугольников, кругов и квадратов (menubgshapes) летят справа налево и крутятся;
##   * снизу поднимаются квадратики (MenuBgParticles).
## Скорость фигур — спокойнее, чем в оригинале (там 160–320 px/с — фон мельтешит под панелью).

const STRIP := preload("res://assets/original/textures/menu/menubg-000.png")
const SHAPES := [preload("res://assets/original/textures/menu/menubgshapes-000.png"),
		preload("res://assets/original/textures/menu/menubgshapes-001.png"),
		preload("res://assets/original/textures/menu/menubgshapes-002.png")]
const PARTICLE := preload("res://assets/original/textures/menu/menubgparticles.png")
## Цвет слоя Bg оригинала (под полосами).
const BASE_COLOR := Color8(99, 0, 0)
## Краска полос: красная <-> оранжевая.
const TINT_RED := Color(0.75, 0.0, 0.0)
const TINT_ORANGE := Color(0.95, 0.55, 0.15)
## Фигуры и квадратики: оранжевые <-> жёлтые.
const SHAPE_RED := Color(1.0, 0.55, 0.1)
const SHAPE_ORANGE := Color(1.0, 0.95, 0.25)
const COLOR_PERIOD := 4.0 / 3.0
const WAVE_PERIOD := 2.0 / 3.0
const WAVE_HEIGHT := 4.0
const SHAPE_COUNT := 15
const SHAPE_SPEED := Vector2(60.0, 140.0)
const SHAPE_SPIN := Vector2(90.0, 200.0)

var _strips: Array[TextureRect] = []
var _shapes: Array[Dictionary] = []
var _strip_holder: Control
var _particles: CPUParticles2D
var _time := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var base := ColorRect.new()
	base.color = BASE_COLOR
	base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(base)
	_strip_holder = Control.new()
	_strip_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_strip_holder)
	_particles = CPUParticles2D.new()
	_particles.texture = PARTICLE
	_particles.amount = 36
	_particles.lifetime = 7.0
	_particles.preprocess = 2.0
	_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_particles.direction = Vector2.UP
	_particles.spread = 8.0
	_particles.gravity = Vector2.ZERO
	_particles.initial_velocity_min = 14.0
	_particles.initial_velocity_max = 40.0
	_particles.scale_amount_min = 1.0
	_particles.scale_amount_max = 2.5
	add_child(_particles)
	for i in SHAPE_COUNT:
		var shape := TextureRect.new()
		shape.mouse_filter = Control.MOUSE_FILTER_IGNORE
		shape.pivot_offset = Vector2(8, 8)
		add_child(shape)
		var entry := {"node": shape}
		_reset_shape(entry, randf_range(-16.0, 400.0))
		_shapes.append(entry)
	resized.connect(_layout)
	_layout()


func _layout() -> void:
	var count := ceili(size.x / 16.0) + 1
	while _strips.size() < count:
		var strip := TextureRect.new()
		strip.texture = STRIP
		strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_strip_holder.add_child(strip)
		_strips.append(strip)
	for i in _strips.size():
		_strips[i].position.x = i * 16.0
		_strips[i].scale = Vector2(1.0, maxf(size.y + 8.0, 224.0) / 224.0)
	_particles.position = Vector2(size.x * 0.5, size.y + 4.0)
	_particles.emission_rect_extents = Vector2(size.x * 0.5, 2.0)


func _process(delta: float) -> void:
	_time += delta
	# Краска: туда-обратно с плавным ходом (easeInOutSine).
	var k := 0.5 - 0.5 * cos(PI * _time / COLOR_PERIOD)
	_strip_holder.modulate = TINT_RED.lerp(TINT_ORANGE, k)
	var shape_color := SHAPE_RED.lerp(SHAPE_ORANGE, k)
	_particles.color = shape_color
	for i in _strips.size():
		var phase := (_time - i / 9.0) / WAVE_PERIOD
		_strips[i].position.y = -WAVE_HEIGHT * (0.5 - 0.5 * cos(PI * phase))
	for entry in _shapes:
		var shape: TextureRect = entry["node"]
		shape.position.x -= float(entry["speed"]) * delta
		shape.rotation_degrees += float(entry["spin"]) * delta
		shape.modulate = shape_color
		if shape.position.x < -24.0:
			_reset_shape(entry, size.x + randf_range(16.0, 64.0))


## Фигура заходит справа на случайной высоте, со своей скоростью, вращением и видом.
func _reset_shape(entry: Dictionary, x: float) -> void:
	var shape: TextureRect = entry["node"]
	shape.texture = SHAPES.pick_random()
	shape.position = Vector2(x, randf_range(24.0, maxf(size.y, 216.0) - 24.0))
	entry["speed"] = randf_range(SHAPE_SPEED.x, SHAPE_SPEED.y)
	entry["spin"] = randf_range(SHAPE_SPIN.x, SHAPE_SPIN.y) * (1.0 if randf() < 0.5 else -1.0)
