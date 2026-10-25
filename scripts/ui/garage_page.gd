class_name GaragePage
extends VBoxContainer
## Гараж — страница меню «на чём поедем?» (MenuSkin оригинала): машина крутится посередине,
## слева — уровни R, G, B (4 на канал, кадры menuskinchange-r/g/b), справа — кузов, стёкла,
## рисунок, колёса (кадры menuskinchange-skinparts): нажатие — следующий вариант; под ними —
## поле ника (как MenuNick оригинала). Секрет оригинала: зажать кнопку кузова — танк.
## Скин меняется сразу (signal changed).

signal changed(code: String)

const BUTTONS := "res://assets/original/textures/menu/menuskinchange-"
## Сколько держать кнопку кузова, чтобы получить танк, с.
const TANK_HOLD := 1.0
## Скорость вращения машины, рад/с.
const TURN_SPEED := 0.8
const BUTTON_SIZE := Vector2(16, 16)

var skin: CarSkin = CarSkin.from_code(CarSkin.DEFAULT_CODE)
## Поле ника — ставит меню (ник меню общий для всех страниц).
var nick_field: Control

var _pivot: Node3D
var _channel_buttons: Array[TextureButton] = []
var _info: Label
var _hold := -1.0


func _ready() -> void:
	add_theme_constant_override(&"separation", 2)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", 8)
	add_child(row)
	for channel in ["r", "g", "b"]:
		var button := _texture_button("%s%s-%03d.png" % [BUTTONS, channel, _level(channel)])
		button.tooltip_text = {"r": "красный", "g": "зелёный", "b": "синий"}[channel]
		button.pressed.connect(_on_channel.bind(channel, button))
		row.add_child(button)
		_channel_buttons.append(button)
	row.add_child(_preview())
	var titles := ["кузов", "стёкла", "рисунок", "колёса"]
	for i in 4:
		var button := _texture_button("%sskinparts-%03d.png" % [BUTTONS, i])
		button.tooltip_text = titles[i]
		if i == 0:
			button.button_down.connect(func() -> void: _hold = 0.0)
			button.button_up.connect(_on_base_released)
		else:
			button.pressed.connect(_on_part.bind(i))
		row.add_child(button)
	_info = Label.new()
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info.add_theme_font_size_override(&"font_size", 6)
	add_child(_info)
	if nick_field != null:
		var nick_row := HBoxContainer.new()
		nick_row.alignment = BoxContainer.ALIGNMENT_CENTER
		add_child(nick_row)
		nick_row.add_child(nick_field)
	_rebuild_car()


func _process(delta: float) -> void:
	if _pivot != null and is_visible_in_tree():
		_pivot.rotate_y(TURN_SPEED * delta)
	if _hold >= 0.0:
		_hold += delta
		if _hold >= TANK_HOLD and skin.base != CarSkin.TANK:
			skin.base = CarSkin.TANK
			MenuFx.click()
			_apply()


## Скин сменили снаружи (меню загрузило настройки): кнопки R/G/B и машина — по нему.
func refresh() -> void:
	if not is_node_ready():
		return
	for i in _channel_buttons.size():
		var channel: String = ["r", "g", "b"][i]
		_channel_buttons[i].texture_normal = load("%s%s-%03d.png" % [BUTTONS, channel, _level(channel)]) as Texture2D
	_rebuild_car()


## Первая кнопка (красный) — для фокуса с клавиатуры.
func first_button() -> Control:
	return _channel_buttons[0]


## Машина на подставке: свой 3D-мир в SubViewport (вид сверху-сбоку, как камера гонки).
func _preview() -> Control:
	var container := SubViewportContainer.new()
	container.stretch = true
	container.custom_minimum_size = Vector2(96, 64)
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	container.add_child(viewport)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.55
	var world := WorldEnvironment.new()
	world.environment = environment
	viewport.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.95, 0.6, 0.0)
	sun.light_energy = 0.9
	viewport.add_child(sun)
	var camera := Camera3D.new()
	camera.fov = 32.0
	viewport.add_child(camera)
	camera.look_at_from_position(Vector3(0.0, 4.2, 5.4), Vector3(0.0, 0.4, 0.0))
	_pivot = Node3D.new()
	_pivot.rotation.y = 2.4
	viewport.add_child(_pivot)
	return container


func _texture_button(path: String) -> TextureButton:
	var button := TextureButton.new()
	button.texture_normal = load(path) as Texture2D
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	button.custom_minimum_size = BUTTON_SIZE
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	MenuFx.juicy(button)
	return button


func _level(channel: String) -> int:
	return {"r": skin.r, "g": skin.g, "b": skin.b}[channel]


func _on_channel(channel: String, button: TextureButton) -> void:
	var level := (_level(channel) + 1) % CarSkin.LEVELS
	match channel:
		"r":
			skin.r = level
		"g":
			skin.g = level
		"b":
			skin.b = level
	button.texture_normal = load("%s%s-%03d.png" % [BUTTONS, channel, level]) as Texture2D
	_apply()


## Кузов: короткое нажатие — следующая форма (с танка — снова по кругу), долгое — танк (_process).
func _on_base_released() -> void:
	var held := _hold
	_hold = -1.0
	if held >= TANK_HOLD:
		return
	skin.base = (skin.base + 1) % CarSkin.BASES
	_apply()


func _on_part(index: int) -> void:
	match index:
		1:
			skin.glass = (skin.glass + 1) % CarSkin.GLASSES
		2:
			skin.decal = (skin.decal + 1) % CarSkin.PRINTS
		3:
			skin.wheels = (skin.wheels + 1) % CarSkin.WHEELS
	_apply()


func _apply() -> void:
	_rebuild_car()
	changed.emit(skin.to_code())


func _rebuild_car() -> void:
	for child in _pivot.get_children():
		child.queue_free()
	var model := skin.model_scene().instantiate() as Node3D
	_pivot.add_child(model)
	skin.paint(model)
	var base_name := "танк" if skin.base == CarSkin.TANK else "%d/%d" % [skin.base + 1, CarSkin.BASES]
	_info.text = "кузов %s, стёкла %d/%d, рисунок %d/%d, колёса %d/%d" % [base_name,
			skin.glass + 1, CarSkin.GLASSES, skin.decal + 1, CarSkin.PRINTS, skin.wheels + 1, CarSkin.WHEELS]
