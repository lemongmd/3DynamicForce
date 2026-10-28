class_name HalloweenBackground
extends Control
## Хэллоуинский фон меню (сезон — Season.is_halloween(), вместо MenuBackground):
##   * тёмно-фиолетовое небо полосами, звёзды мерцают, облака плывут через низкую луну;
##   * справа на скале голое дерево чернеет на фоне луны; ореол луны чуть дышит;
##   * голые корявые деревья, кладбище: надгробия, тыквы-фонари мерцают, гроб стоймя — крышка
##     иногда приоткрывается, внутри горят глаза; ещё пара глаз моргает за надгробиями;
##   * гниль: лужи зелёной слизи с пузырями;
##   * летучие мыши пролетают стайками, падают листья, по земле ползёт туман.
## Картинки — scripts/tools/build_halloween_menu.gd (assets/textures/menu_halloween/).

const DIR := "res://assets/textures/menu_halloween/"
const LEAF := preload("res://assets/textures/halloween/leaf.png")
## Пятно света ступенями (карта «Хэллоуин»): ореол тыкв.
const GLOW_POOL := preload("res://assets/textures/halloween/glow_pool.png")
## Небо полосами сверху вниз.
const SKY := [Color8(11, 2, 20), Color8(19, 4, 32), Color8(28, 7, 44), Color8(38, 10, 56),
		Color8(50, 14, 68), Color8(64, 20, 80), Color8(80, 28, 92), Color8(96, 36, 100)]
## Высота ближней земли от низа экрана, px (hills.png: земля с y = 46 из 64).
const GROUND := 18.0
const COFFIN_EVERY := 9.0
const COFFIN_OPEN_TIME := 2.2
const BAT_FRAME := 0.12

var _time := 0.0
var _stars: _Stars
var _moon: TextureRect
var _moon_glow: TextureRect
var _clouds: Array[TextureRect] = []
var _hills: TextureRect
var _trees: Array[TextureRect] = []
var _cliff: TextureRect
var _cliff_tree: TextureRect
var _coffin_box: TextureRect
var _coffin_lid: TextureRect
var _coffin_eyes: Control
var _tombs: Array[TextureRect] = []
var _pumpkins: Array[TextureRect] = []
var _pumpkin_glows: Array[TextureRect] = []
var _slimes: Array[TextureRect] = []
var _bubbles: Array[CPUParticles2D] = []
var _fogs: Array[TextureRect] = []
var _leaves: CPUParticles2D
var _eyes: Array[Control] = []
var _bat_frames: Array[Texture2D] = []
var _bats: Array[Dictionary] = []
var _next_flock := 2.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sky := TextureRect.new()
	sky.texture = _sky_texture()
	sky.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sky.stretch_mode = TextureRect.STRETCH_SCALE
	sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_add(sky)
	_stars = _Stars.new()
	_stars.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_add(_stars)
	_moon_glow = _sprite("moon_glow")
	_moon_glow.material = _additive()
	_moon_glow.modulate = Color(0.75, 0.55, 0.9, 0.55)
	_moon = _sprite("moon")
	for i in 3:
		var cloud := _sprite("cloud")
		cloud.modulate.a = 0.9
		cloud.set_meta(&"speed", 4.0 + 3.0 * i)
		_clouds.append(cloud)
	_hills = _sprite("hills")
	_hills.stretch_mode = TextureRect.STRETCH_TILE
	_hills.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	for file in ["tree_2", "tree_0"]:
		_trees.append(_sprite(file))
	_coffin_box = _sprite("coffin_box")
	_coffin_eyes = _eye_pair()
	_coffin_eyes.visible = false
	_coffin_lid = _sprite("coffin_lid")
	_coffin_lid.pivot_offset = Vector2(1, 30)
	for kind in [0, 2, 1, 0, 1, 2]:
		_tombs.append(_sprite("tomb_%d" % kind))
	for i in 3:
		var glow := TextureRect.new()
		glow.texture = GLOW_POOL
		glow.material = _additive()
		_add(glow)
		glow.modulate = Color(1.0, 0.55, 0.1, 0.6)
		_pumpkin_glows.append(glow)
		_pumpkins.append(_sprite("pumpkin"))
	for i in 2:
		_slimes.append(_sprite("slime"))
		var bubbles := _particles(4, 1.4, Color8(124, 255, 74))
		bubbles.direction = Vector2.UP
		bubbles.spread = 20.0
		bubbles.initial_velocity_min = 4.0
		bubbles.initial_velocity_max = 9.0
		bubbles.emission_rect_extents = Vector2(9, 1)
		_bubbles.append(bubbles)
	_eyes.append(_eye_pair())
	_cliff = _sprite("cliff")
	_cliff_tree = _sprite("tree_1")
	for i in 2:
		var fog := _sprite("fog")
		fog.stretch_mode = TextureRect.STRETCH_TILE
		fog.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		fog.modulate.a = 0.55 if i == 0 else 0.4
		fog.set_meta(&"speed", 6.0 if i == 0 else -4.0)
		_fogs.append(fog)
	for i in 2:
		_bat_frames.append(load("%sbat_%d.png" % [DIR, i]) as Texture2D)
	_leaves = _particles(14, 9.0, Color.WHITE)
	_leaves.texture = LEAF
	_leaves.direction = Vector2(0.4, 1.0)
	_leaves.spread = 25.0
	_leaves.gravity = Vector2(6, 10)
	_leaves.initial_velocity_min = 8.0
	_leaves.initial_velocity_max = 18.0
	_leaves.angular_velocity_min = -90.0
	_leaves.angular_velocity_max = 90.0
	_leaves.scale_amount_min = 0.5
	_leaves.scale_amount_max = 1.0
	_leaves.preprocess = 9.0
	var leaf_colors := Gradient.new()
	leaf_colors.colors = PackedColorArray([Color8(240, 128, 30), Color8(200, 56, 40), Color8(236, 190, 60)])
	leaf_colors.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	_leaves.color_initial_ramp = leaf_colors
	resized.connect(_layout)
	_layout()


func _layout() -> void:
	var w := size.x
	var h := size.y
	var ground := h - GROUND
	_hills.position = Vector2(0, h - 64)
	_hills.size = Vector2(w, 64)
	# Скала справа внизу, на ней дерево (корни — на площадке x 36..56, y 20), луна низко за ним.
	_cliff.position = Vector2(w - 96, h - 80)
	_cliff_tree.position = _cliff.position + Vector2(46 - 38, 22 - 84)
	var moon_center := _cliff.position + Vector2(52, -26)
	_moon.position = moon_center - Vector2(32, 32)
	_moon_glow.position = moon_center - Vector2(64, 64)
	# Деревья: большое у левого края и поменьше левее середины.
	_trees[0].position = Vector2(-34, ground - 126)
	_trees[1].position = Vector2(w * 0.22, ground - 110)
	# Гроб стоймя у большого дерева.
	_coffin_box.position = Vector2(64, ground - 31)
	_coffin_lid.position = _coffin_box.position
	_coffin_eyes.position = _coffin_box.position + Vector2(6, 9)
	var tomb_x := [18.0, 108.0, 132.0, w * 0.5 - 70.0, w * 0.5 + 58.0, w - 142.0]
	for i in _tombs.size():
		_tombs[i].position = Vector2(tomb_x[i], ground - 17 + (i % 2))
	var pumpkin_x := [46.0, w * 0.5 - 40.0, w - 120.0]
	for i in _pumpkins.size():
		_pumpkins[i].position = Vector2(pumpkin_x[i], ground - 11)
		_pumpkin_glows[i].position = _pumpkins[i].position + Vector2(7, 7) - _pumpkin_glows[i].size * 0.5
	var slime_x := [150.0, w * 0.5 + 16.0]
	for i in _slimes.size():
		_slimes[i].position = Vector2(slime_x[i], ground - 4)
		_bubbles[i].position = _slimes[i].position + Vector2(14, 1)
	_eyes[0].position = Vector2(w * 0.5 + 64, ground - 22)
	for fog in _fogs:
		fog.size = Vector2(w + 128, 24)
		fog.position.y = h - 30 if fog == _fogs[0] else h - 40
	_leaves.position = Vector2(w * 0.5, -8)
	_leaves.emission_rect_extents = Vector2(w * 0.5, 2)
	for cloud in _clouds:
		if cloud.position == Vector2.ZERO:
			cloud.position = Vector2(randf_range(0, w), randf_range(20, h * 0.5))
	_stars.scatter(Vector2(w, h * 0.7))


func _process(delta: float) -> void:
	_time += delta
	var w := size.x
	_moon_glow.modulate.a = 0.55 + 0.06 * sin(_time * 1.3)
	# Гроб: крышка приоткрывается, внутри горят глаза.
	var coffin_t := fmod(_time + 4.0, COFFIN_EVERY)
	var open := 0.0
	if coffin_t < COFFIN_OPEN_TIME:
		open = sin(PI * coffin_t / COFFIN_OPEN_TIME)
	_coffin_lid.rotation = -0.5 * clampf(open * 1.4, 0.0, 1.0)
	_coffin_eyes.visible = open > 0.3
	# Глаза в темноте моргают по очереди.
	for i in _eyes.size():
		_eyes[i].visible = fmod(_time + i * 2.3, 5.0) < 4.0 and fmod(_time * 3.0 + i, 7.0) > 0.25
	# Тыквы мерцают.
	for i in _pumpkin_glows.size():
		_pumpkin_glows[i].modulate.a = 0.45 + 0.15 * sin(_time * 9.0 + i * 2.0) + 0.1 * sin(_time * 23.0 + i)
	for cloud in _clouds:
		cloud.position.x -= float(cloud.get_meta(&"speed")) * delta
		if cloud.position.x < -cloud.size.x:
			cloud.position = Vector2(w + randf_range(0, 60), randf_range(20, size.y * 0.5))
	for fog in _fogs:
		fog.position.x = -fposmod(_time * float(fog.get_meta(&"speed")), 128.0)
	_stars.twinkle(_time)
	_update_bats(delta)


func _update_bats(delta: float) -> void:
	_next_flock -= delta
	if _next_flock <= 0.0:
		_next_flock = randf_range(6.0, 12.0)
		var from_left := randf() < 0.5
		var y := randf_range(30.0, size.y * 0.45)
		for i in randi_range(2, 4):
			var bat := TextureRect.new()
			bat.mouse_filter = Control.MOUSE_FILTER_IGNORE
			bat.texture = _bat_frames[0]
			add_child(bat)
			move_child(bat, _leaves.get_index())
			_bats.append({"node": bat, "x": -20.0 - i * 14.0 if from_left else size.x + 10.0 + i * 14.0,
					"y": y + randf_range(-10, 10), "dir": 1.0 if from_left else -1.0,
					"speed": randf_range(50.0, 70.0), "phase": randf() * TAU})
	for bat in _bats.duplicate():
		var node: TextureRect = bat["node"]
		bat["x"] = float(bat["x"]) + float(bat["dir"]) * float(bat["speed"]) * delta
		node.position = Vector2(bat["x"], float(bat["y"]) + 5.0 * sin(_time * 4.0 + float(bat["phase"])))
		node.texture = _bat_frames[int((_time + float(bat["phase"])) / BAT_FRAME) % 2]
		if node.position.x < -80.0 or node.position.x > size.x + 80.0:
			node.queue_free()
			_bats.erase(bat)


# --------------------------------------------------------------------------

func _add(node: Control) -> void:
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(node)


func _sprite(file: String) -> TextureRect:
	var sprite := TextureRect.new()
	sprite.texture = load("%s%s.png" % [DIR, file]) as Texture2D
	_add(sprite)
	return sprite


## Пара светящихся глаз (2 пикселя через один).
func _eye_pair() -> Control:
	var pair := Control.new()
	for x in [0, 3]:
		var eye := ColorRect.new()
		eye.color = Color8(255, 216, 74)
		eye.size = Vector2.ONE
		eye.position = Vector2(x, 0)
		pair.add_child(eye)
	_add(pair)
	return pair


func _particles(amount: int, lifetime: float, color: Color) -> CPUParticles2D:
	var particles := CPUParticles2D.new()
	particles.amount = amount
	particles.lifetime = lifetime
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	particles.gravity = Vector2.ZERO
	particles.color = color
	add_child(particles)
	return particles


static func _additive() -> CanvasItemMaterial:
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return additive


## Небо: полосы SKY сверху вниз (без плавного перехода — по-пиксельному).
static func _sky_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	var offsets := PackedFloat32Array()
	for i in SKY.size():
		offsets.append(float(i) / SKY.size())
	gradient.offsets = offsets
	gradient.colors = PackedColorArray(SKY)
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0, 0)
	texture.fill_to = Vector2(0, 1)
	texture.width = 4
	texture.height = 64
	return texture


## Звёзды: точки в 1 px (редкие — крестиком), мерцают каждая со своей фазой.
class _Stars:
	extends Control

	var _points: Array[Vector3] = []
	var _time := 0.0

	func scatter(area: Vector2) -> void:
		_points.clear()
		var rng := RandomNumberGenerator.new()
		rng.seed = 666
		for i in int(area.x * area.y / 900.0):
			_points.append(Vector3(rng.randf_range(0, area.x), rng.randf_range(0, area.y), rng.randf() * TAU))
		queue_redraw()

	func twinkle(time: float) -> void:
		_time = time
		queue_redraw()

	func _draw() -> void:
		for i in _points.size():
			var p := _points[i]
			var a := 0.45 + 0.55 * sin(_time * (0.8 + fmod(p.z, 1.3)) + p.z)
			var color := Color(1.0, 0.94, 0.8, clampf(a, 0.1, 1.0))
			var at := Vector2(floorf(p.x), floorf(p.y))
			draw_rect(Rect2(at, Vector2.ONE), color)
			if i % 9 == 0 and a > 0.8:
				for d in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
					draw_rect(Rect2(at + d, Vector2.ONE), Color(color, 0.5))
