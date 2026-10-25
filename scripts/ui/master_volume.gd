extends Node
## Автозагрузка «Volume»: общая громкость на клавиши − и +, как в оригинале (GlobalS: пока
## клавиша зажата — ±15 дБ/с, от −50 до 0 дБ, шина Master). Пока громкость меняется и ещё
## секунду после — полоска сверху экрана; значение сохраняется (GameSettings master_volume_db).

const STEP_DB_PER_SECOND := 15.0
const MIN_DB := -50.0
const MAX_DB := 0.0
const SHOW_TIME := 1.2
const BAR_WIDTH := 64.0

var _layer: CanvasLayer
var _panel: PanelContainer
var _bar: ColorRect
var _label: Label
var _show_left := 0.0
var _changed := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_apply(float(GameSettings.get_value("master_volume_db", MAX_DB)))


func _process(delta: float) -> void:
	var direction := 0.0
	if InputMap.has_action(GameActions.VOLUME_UP) and Input.is_action_pressed(GameActions.VOLUME_UP):
		direction += 1.0
	if InputMap.has_action(GameActions.VOLUME_DOWN) and Input.is_action_pressed(GameActions.VOLUME_DOWN):
		direction -= 1.0
	# Пока печатают в поле ввода (ник, ID игры), − и + — это буквы, а не громкость.
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		direction = 0.0
	if direction != 0.0:
		_apply(volume_db() + direction * STEP_DB_PER_SECOND * delta)
		_changed = true
		_show_left = SHOW_TIME
	elif _changed:
		_changed = false
		GameSettings.set_value("master_volume_db", volume_db())
	_show_left -= delta
	_layer.visible = _show_left > 0.0


static func volume_db() -> float:
	return AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Master"))


func _apply(db: float) -> void:
	db = clampf(db, MIN_DB, MAX_DB)
	var bus := AudioServer.get_bus_index(&"Master")
	AudioServer.set_bus_volume_db(bus, db)
	AudioServer.set_bus_mute(bus, db <= MIN_DB)
	var share := inverse_lerp(MIN_DB, MAX_DB, db)
	_bar.size = Vector2(roundf(BAR_WIDTH * share), 3.0)
	_label.text = "громкость %d%%" % roundi(share * 100.0)


func _build() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 120
	_layer.visible = false
	add_child(_layer)
	var holder := CenterContainer.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	holder.offset_top = 6.0
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(holder)
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 2)
	_panel.add_child(box)
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override(&"font_size", 6)
	box.add_child(_label)
	var track := ColorRect.new()
	track.color = Color(0.0, 0.0, 0.0, 0.6)
	track.custom_minimum_size = Vector2(BAR_WIDTH, 3)
	box.add_child(track)
	_bar = ColorRect.new()
	_bar.color = Color(1.0, 0.82, 0.1)
	_bar.size = Vector2(BAR_WIDTH, 3)
	track.add_child(_bar)
