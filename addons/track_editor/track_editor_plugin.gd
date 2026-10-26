@tool
extends EditorPlugin
## Редактор карт 3Dynamic Force — панель «Трасса» в редакторе Godot.
##
## Работает, когда открыта сцена трассы (корень — Track, scenes/tracks/*.tscn):
##   * «Поставить»: выбрать объект и кликать по дороге в 3D-виде — объект встаёт ровно
##     (на полосу, по направлению трассы); R — повернуть на 90°, Esc или ПКМ — закончить;
##   * «Выровнять выделенные / все» — поставить объекты на полосы и по трассе;
##   * «Проверить карту» — TrackCheck: пустые участки, объекты на стене и друг на друге;
##     TrackFlow: проходимость и логика (резкие манёвры, слепые места, прыжки, ускорители,
##     старт) — замечания списком и метками над трассой;
##   * «Гонка на этой карте» — сохранить и запустить игру на этой карте;
##   * «Новая карта» — заготовка трассы в scenes/tracks/<имя>.tscn.
## Всё, что меняет сцену, отменяется Ctrl+Z. Подробно — docs/map_editor.md.

const TRACKS_DIR := "res://scenes/tracks/"
const RACE_SCENE := "res://scenes/race/race.tscn"
const SELF_TEST := preload("res://addons/track_editor/self_test.gd")
const ZONE_GIZMO := preload("res://addons/track_editor/map_zone_gizmo.gd")
const ROAD_SIGN_SCENE := "res://scenes/props/road_sign.tscn"
## Что можно поставить: название, сцена, свойства, особые режимы.
## item_row — ряд из N мест коробок предметов; wall — декор на стену.
const PALETTE := [
	{"title": "Бочка", "scene": "res://scenes/props/barrel.tscn", "base": "Barrel"},
	{"title": "Ускоритель +", "scene": "res://scenes/objects/boost_pad.tscn", "base": "BoostPad", "set": {"kind": 0}},
	{"title": "Ускоритель ++", "scene": "res://scenes/objects/boost_pad.tscn", "base": "BoostPad", "set": {"kind": 1}},
	{"title": "Ускоритель MAX", "scene": "res://scenes/objects/boost_pad.tscn", "base": "BoostPad", "set": {"kind": 2}},
	{"title": "Трамплин", "scene": "res://scenes/props/ramp.tscn", "base": "Ramp"},
	{"title": "Ограждение (парир.)", "scene": "res://scenes/hazards/barrier_parry.tscn", "base": "BarrierParry"},
	{"title": "Ограждение (твёрдое)", "scene": "res://scenes/props/barrier_block.tscn", "base": "BarrierBlock"},
	# Объекты карт оригинала (этап 7).
	{"title": "Шина", "scene": "res://scenes/props/tire.tscn", "base": "Tire"},
	{"title": "Ящик стройки", "scene": "res://scenes/props/site_crate.tscn", "base": "SiteCrate"},
	{"title": "Щебень", "scene": "res://scenes/props/gravel.tscn", "base": "Gravel"},
	{"title": "Краб", "scene": "res://scenes/props/crab.tscn", "base": "Crab"},
	{"title": "Краб (парир.)", "scene": "res://scenes/hazards/crab_parry.tscn", "base": "CrabParry"},
	{"title": "Спасательный круг", "scene": "res://scenes/props/life_ring.tscn", "base": "LifeRing"},
	{"title": "Мокрый пол", "scene": "res://scenes/props/wet_floor.tscn", "base": "WetFloor"},
	{"title": "Мокрый пол (парир.)", "scene": "res://scenes/hazards/wet_floor_parry.tscn", "base": "WetFloorParry"},
	{"title": "Опасно", "scene": "res://scenes/props/danger_sign.tscn", "base": "DangerSign"},
	{"title": "Опасно (парир.)", "scene": "res://scenes/hazards/danger_sign_parry.tscn", "base": "DangerSignParry"},
	# «Хэллоуин»: тыквы (твёрдая, парируемая) и призрак (плавает поперёк дороги, парировать).
	{"title": "Тыква", "scene": "res://scenes/props/pumpkin.tscn", "base": "Pumpkin"},
	{"title": "Тыква (парир.)", "scene": "res://scenes/hazards/pumpkin_parry.tscn", "base": "PumpkinParry"},
	{"title": "Призрак", "scene": "res://scenes/hazards/ghost.tscn", "base": "Ghost"},
	{"title": "Надгробие", "scene": "res://scenes/props/tombstone.tscn", "base": "Tombstone"},
	{"title": "Цирковые шары", "scene": "res://scenes/hazards/circus_balls.tscn", "base": "CircusBalls"},
	{"title": "Лёд 8×10", "scene": "res://scenes/objects/map_zone.tscn", "base": "Ice",
			"set": {"kind": 2, "size": Vector2(8.0, 10.0)}},
	{"title": "Лента 3×12", "scene": "res://scenes/objects/map_zone.tscn", "base": "Conveyor",
			"set": {"kind": 0, "size": Vector2(12.0, 3.0)}},
	{"title": "Грязь 12×20", "scene": "res://scenes/objects/map_zone.tscn", "base": "Mud",
			"set": {"kind": 3, "size": Vector2(12.0, 20.0)}},
	{"title": "Коробки ×3", "item_row": 3, "base": "ItemBoxSpot"},
	{"title": "Коробка ×1", "item_row": 1, "base": "ItemBoxSpot"},
	{"title": "Знак «ТУДА»", "scene": ROAD_SIGN_SCENE, "base": "RoadSign", "wall": true},
]
## Коробки в ряду — через столько метров (как в c3_extract_track).
const ITEM_BOX_SPACING := 4.0
## Фоны новой карты.
const BACKGROUNDS := [
	["Вода", "res://assets/materials/background_water.tres"],
	["Кислота", "res://assets/materials/background_acid.tres"],
]

var _dock: EditorDock
var _info: Label
var _status: Label
var _report: Label
var _snap_lanes: CheckBox
var _along_step: SpinBox
var _place_buttons: Array[Button] = []
var _new_name: LineEdit
var _new_background: OptionButton
## Что ставим сейчас (индекс PALETTE), -1 — ничего.
var _placing: int = -1
## Режим «ширина участка»: клик по дороге задаёт ширину участка ломаной под курсором.
var _widening := false
var _width_button: Button
var _width_blocks: SpinBox
var _lifting := false
var _height_button: Button
var _height_value: SpinBox
## Поворот следующего объекта относительно трассы (R — +90°).
var _place_relative: float = 0.0
var _self_test: RefCounted
## Рамки и выбор кликом для зон карты (их картинка не сохраняется — своих гизмо нет).
var _zone_gizmo: EditorNode3DGizmoPlugin


func _enter_tree() -> void:
	_dock = EditorDock.new()
	_dock.title = "Трасса"
	_dock.default_slot = EditorDock.DOCK_SLOT_LEFT_BR
	_dock.add_child(_build_ui())
	add_dock(_dock)
	_zone_gizmo = ZONE_GIZMO.new()
	add_node_3d_gizmo_plugin(_zone_gizmo)
	set_input_event_forwarding_always_enabled()
	scene_changed.connect(_on_scene_changed)
	_refresh_info()
	if SELF_TEST.requested():
		_self_test = SELF_TEST.new()
		_self_test.run.call_deferred(self)


func _exit_tree() -> void:
	if scene_changed.is_connected(_on_scene_changed):
		scene_changed.disconnect(_on_scene_changed)
	remove_node_3d_gizmo_plugin(_zone_gizmo)
	_zone_gizmo = null
	remove_dock(_dock)
	_dock.queue_free()
	_dock = null


# --------------------------------------------------------------------------
# Интерфейс
# --------------------------------------------------------------------------

func _build_ui() -> Control:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)

	_info = _wrapped_label()
	box.add_child(_info)

	box.add_child(_header("Поставить на дорогу"))
	var grid := GridContainer.new()
	grid.columns = 2
	box.add_child(grid)
	for i in PALETTE.size():
		var button := Button.new()
		button.text = PALETTE[i]["title"]
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.toggled.connect(_on_place_toggled.bind(i))
		grid.add_child(button)
		_place_buttons.append(button)
	_status = _wrapped_label()
	_status.text = "Выберите объект и кликайте по дороге в 3D-виде."
	box.add_child(_status)

	_snap_lanes = CheckBox.new()
	_snap_lanes.text = "Ставить на полосы (жёлтые линии)"
	_snap_lanes.button_pressed = true
	box.add_child(_snap_lanes)
	var step_row := HBoxContainer.new()
	var step_label := Label.new()
	step_label.text = "Шаг вдоль трассы, м"
	step_row.add_child(step_label)
	_along_step = SpinBox.new()
	_along_step.min_value = 0.0
	_along_step.max_value = 10.0
	_along_step.step = 0.5
	_along_step.value = 1.0
	_along_step.tooltip_text = "0 — без округления вдоль трассы"
	step_row.add_child(_along_step)
	box.add_child(step_row)

	box.add_child(_header("Ширина дороги"))
	var width_row := HBoxContainer.new()
	var width_label := Label.new()
	width_label.text = "Блоков по 3 м"
	width_row.add_child(width_label)
	_width_blocks = SpinBox.new()
	_width_blocks.min_value = 0.0
	_width_blocks.max_value = 10.0
	_width_blocks.step = 0.5
	_width_blocks.value = 2.0
	_width_blocks.tooltip_text = "0 — обычная ширина (Road Width у корня трассы)"
	width_row.add_child(_width_blocks)
	box.add_child(width_row)
	_width_button = Button.new()
	_width_button.text = "Задать ширину участка (клик)"
	_width_button.toggle_mode = true
	_width_button.toggled.connect(_on_width_toggled)
	box.add_child(_width_button)

	box.add_child(_header("Высота (подъёмы и спуски)"))
	var height_row := HBoxContainer.new()
	var height_label := Label.new()
	height_label.text = "Высота точки, м"
	height_row.add_child(height_label)
	_height_value = SpinBox.new()
	_height_value.min_value = -200.0
	_height_value.max_value = 200.0
	_height_value.step = 0.5
	_height_value.value = 6.0
	_height_value.tooltip_text = "Высота точки трассы над нулём. Подъём круче 44° машина не заедет:\nна 6 м подъёма нужно не меньше 6.5 м по горизонтали\n(удобнее — до 35°: 9 м)."
	height_row.add_child(_height_value)
	box.add_child(height_row)
	_height_button = Button.new()
	_height_button.text = "Задать высоту точки (клик)"
	_height_button.toggle_mode = true
	_height_button.toggled.connect(_on_height_toggled)
	box.add_child(_height_button)

	box.add_child(_header("Порядок"))
	box.add_child(_action_button("Выровнять выделенные", _on_align_selected))
	box.add_child(_action_button("Выровнять все объекты", _on_align_all))
	box.add_child(_action_button("Проверить карту", _on_check))
	_report = _wrapped_label()
	box.add_child(_report)

	box.add_child(_header("Заезд"))
	box.add_child(_action_button("▶ Гонка на этой карте", _on_play))

	box.add_child(_header("Новая карта"))
	_new_name = LineEdit.new()
	_new_name.placeholder_text = "имя латиницей, напр. my_map"
	box.add_child(_new_name)
	_new_background = OptionButton.new()
	for entry in BACKGROUNDS:
		_new_background.add_item("Фон: %s" % entry[0])
	box.add_child(_new_background)
	box.add_child(_action_button("Создать и открыть", _on_new_map))
	return scroll


func _header(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override(&"font_color", Color(1.0, 0.85, 0.3))
	return label


func _wrapped_label() -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(200, 0)
	return label


func _action_button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	return button


func _on_scene_changed(_root: Node) -> void:
	_stop_placing()
	_report.text = ""
	_refresh_info()


func _refresh_info() -> void:
	if _info == null:
		return
	var track := _current_track()
	if track == null:
		_info.text = "Откройте сцену трассы (scenes/tracks/*.tscn), чтобы редактировать карту."
		return
	var props := track.get_node_or_null(^"Props")
	var width := "%.1f м" % track.road_width
	if not is_equal_approx(track.min_road_width(), track.max_road_width()):
		width = "%.1f–%.1f м" % [track.min_road_width(), track.max_road_width()]
	_info.text = "Карта: %s\nкруг %.0f м, дорога %s, полоса %.2f м, объектов %d" % [
		track.scene_file_path.get_file(), track.length, width,
		TrackLayout.lane_step(track), props.get_child_count() if props != null else 0]


## Корень открытой сцены, если это трасса.
func _current_track() -> Track:
	return EditorInterface.get_edited_scene_root() as Track


# --------------------------------------------------------------------------
# Постановка объектов кликом
# --------------------------------------------------------------------------

func _on_place_toggled(pressed: bool, index: int) -> void:
	if not pressed:
		if _placing == index:
			_stop_placing()
		return
	if _current_track() == null:
		_place_buttons[index].set_pressed_no_signal(false)
		_status.text = "Сначала откройте сцену трассы."
		return
	_placing = index
	_place_relative = 0.0
	for i in _place_buttons.size():
		if i != index:
			_place_buttons[i].set_pressed_no_signal(false)
	_update_place_status("")


func _stop_placing() -> void:
	_placing = -1
	_widening = false
	_lifting = false
	if _width_button != null:
		_width_button.set_pressed_no_signal(false)
	if _height_button != null:
		_height_button.set_pressed_no_signal(false)
	for button in _place_buttons:
		button.set_pressed_no_signal(false)
	if _status != null:
		_status.text = "Выберите объект и кликайте по дороге в 3D-виде."


func _update_place_status(where: String) -> void:
	if _placing < 0:
		return
	_status.text = "Ставим: %s (поворот %d°). Клик — поставить, R — повернуть, Esc/ПКМ — закончить.%s" % [
		PALETTE[_placing]["title"], roundi(rad_to_deg(_place_relative)), "\n" + where if where != "" else ""]


func _forward_3d_gui_input(viewport_camera: Camera3D, event: InputEvent) -> int:
	if _widening:
		return _width_input(viewport_camera, event)
	if _lifting:
		return _height_input(viewport_camera, event)
	if _placing < 0:
		return AFTER_GUI_INPUT_PASS
	var track := _current_track()
	if track == null:
		_stop_placing()
		return AFTER_GUI_INPUT_PASS
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		if key.keycode == KEY_ESCAPE:
			_stop_placing()
			return AFTER_GUI_INPUT_STOP
		if key.keycode == KEY_R:
			_place_relative = fposmod(_place_relative + PI * 0.5, TAU)
			_update_place_status("")
			return AFTER_GUI_INPUT_STOP
	var button := event as InputEventMouseButton
	if button != null and button.pressed:
		if button.button_index == MOUSE_BUTTON_RIGHT:
			_stop_placing()
			return AFTER_GUI_INPUT_STOP
		if button.button_index == MOUSE_BUTTON_LEFT:
			var hit: Variant = _road_hit(track, viewport_camera, button.position)
			if hit != null:
				_place(track, hit)
			return AFTER_GUI_INPUT_STOP
	var motion := event as InputEventMouseMotion
	if motion != null:
		var hit: Variant = _road_hit(track, viewport_camera, motion.position)
		if hit != null:
			var where := TrackLayout.locate(track, hit)
			_update_place_status("Под курсором: %.1f м от старта, %+.2f м от середины." % [
				where["offset"], where["lateral"]])
	return AFTER_GUI_INPUT_PASS


# --------------------------------------------------------------------------
# Ширина участков (Track.segment_widths)
# --------------------------------------------------------------------------

func _on_width_toggled(pressed: bool) -> void:
	if not pressed:
		_stop_placing()
		return
	if _current_track() == null:
		_width_button.set_pressed_no_signal(false)
		_status.text = "Сначала откройте сцену трассы."
		return
	_stop_placing()
	_widening = true
	_width_button.set_pressed_no_signal(true)
	_status.text = "Ширина: клик по участку дороги задаёт ему %s. Esc/ПКМ — закончить." % _width_text()


func _width_text() -> String:
	return "обычную ширину" if _width_blocks.value <= 0.0 else "%s блока (%.1f м)" % [
		String.num(_width_blocks.value), _width_blocks.value * 3.0]


func _width_input(camera: Camera3D, event: InputEvent) -> int:
	var track := _current_track()
	if track == null:
		_stop_placing()
		return AFTER_GUI_INPUT_PASS
	var key := event as InputEventKey
	if key != null and key.pressed and key.keycode == KEY_ESCAPE:
		_stop_placing()
		return AFTER_GUI_INPUT_STOP
	var button := event as InputEventMouseButton
	if button != null and button.pressed:
		if button.button_index == MOUSE_BUTTON_RIGHT:
			_stop_placing()
			return AFTER_GUI_INPUT_STOP
		if button.button_index == MOUSE_BUTTON_LEFT:
			var hit: Variant = _road_hit(track, camera, button.position)
			if hit != null:
				_set_segment_width(track, track.segment_at(float(TrackLayout.locate(track, hit)["offset"])),
						_width_blocks.value * 3.0)
			return AFTER_GUI_INPUT_STOP
	var motion := event as InputEventMouseMotion
	if motion != null:
		var hit: Variant = _road_hit(track, camera, motion.position)
		if hit != null:
			var segment: int = track.segment_at(float(TrackLayout.locate(track, hit)["offset"]))
			var count := (track.get_node(^"Path") as Path3D).curve.point_count
			_status.text = "Ширина: клик задаёт участку %s. Esc/ПКМ — закончить.\nПод курсором участок от точки %d до %d: %.1f м." % [
				_width_text(), segment, (segment + 1) % count, track.segment_width(segment)]
	return AFTER_GUI_INPUT_PASS


## Ширина участка i (0 — обычная); через отмену/повтор.
func _set_segment_width(track: Track, segment: int, width: float) -> void:
	if segment < 0:
		return
	var count := (track.get_node(^"Path") as Path3D).curve.point_count
	var widths: PackedFloat32Array = track.segment_widths.duplicate()
	if widths.size() < count:
		widths.resize(count)
	widths[segment] = width
	var undo := get_undo_redo()
	undo.create_action("Трасса: ширина участка %d" % segment)
	undo.add_do_property(track, &"segment_widths", widths)
	undo.add_undo_property(track, &"segment_widths", track.segment_widths.duplicate())
	undo.commit_action()
	_refresh_info()


# --------------------------------------------------------------------------
# Высота точек (подъёмы и спуски): Y точки Path3D
# --------------------------------------------------------------------------

func _on_height_toggled(pressed: bool) -> void:
	if not pressed:
		_stop_placing()
		return
	if _current_track() == null:
		_height_button.set_pressed_no_signal(false)
		_status.text = "Сначала откройте сцену трассы."
		return
	_stop_placing()
	_lifting = true
	_height_button.set_pressed_no_signal(true)
	_status.text = "Высота: клик у точки трассы ставит её на %.1f м. Esc/ПКМ — закончить." % _height_value.value


func _height_input(camera: Camera3D, event: InputEvent) -> int:
	var track := _current_track()
	if track == null:
		_stop_placing()
		return AFTER_GUI_INPUT_PASS
	var key := event as InputEventKey
	if key != null and key.pressed and key.keycode == KEY_ESCAPE:
		_stop_placing()
		return AFTER_GUI_INPUT_STOP
	var button := event as InputEventMouseButton
	if button != null and button.pressed:
		if button.button_index == MOUSE_BUTTON_RIGHT:
			_stop_placing()
			return AFTER_GUI_INPUT_STOP
		if button.button_index == MOUSE_BUTTON_LEFT:
			var hit: Variant = _road_hit(track, camera, button.position)
			if hit != null:
				_set_point_height(track, _nearest_path_point(track, hit), _height_value.value)
			return AFTER_GUI_INPUT_STOP
	var motion := event as InputEventMouseMotion
	if motion != null:
		var hit: Variant = _road_hit(track, camera, motion.position)
		if hit != null:
			var index := _nearest_path_point(track, hit)
			var curve := (track.get_node(^"Path") as Path3D).curve
			var count := curve.point_count
			var p := curve.get_point_position(index)
			_status.text = "Высота: клик ставит точку на %.1f м. Esc/ПКМ — закончить.\nБлижайшая точка %d: высота %.1f м; склон к соседним — %s и %s." % [
				_height_value.value, index, p.y,
				_slope_text(curve.get_point_position(posmod(index - 1, count)), p),
				_slope_text(p, curve.get_point_position((index + 1) % count))]
	return AFTER_GUI_INPUT_PASS


## Ближайшая к точке мира точка Path3D (по горизонтали).
func _nearest_path_point(track: Track, world: Vector3) -> int:
	var path := track.get_node(^"Path") as Path3D
	var best := 0
	var best_distance := INF
	for i in path.curve.point_count:
		var p := path.global_transform * path.curve.get_point_position(i)
		var distance := Vector2(p.x - world.x, p.z - world.z).length()
		if distance < best_distance:
			best_distance = distance
			best = i
	return best


func _slope_text(a: Vector3, b: Vector3) -> String:
	var run := Vector2(b.x - a.x, b.z - a.z).length()
	var deg := rad_to_deg(atan2(b.y - a.y, maxf(run, 0.001)))
	return "%+.0f°%s" % [deg, " (круто!)" if deg > TrackCheck.MAX_SLOPE_DEG else ""]


## Высота точки i Path3D; через отмену/повтор.
func _set_point_height(track: Track, index: int, height: float) -> void:
	var curve := (track.get_node(^"Path") as Path3D).curve
	var old := curve.get_point_position(index)
	var new := Vector3(old.x, height, old.z)
	var undo := get_undo_redo()
	undo.create_action("Трасса: высота точки %d" % index)
	undo.add_do_method(curve, &"set_point_position", index, new)
	undo.add_undo_method(curve, &"set_point_position", index, old)
	undo.commit_action()
	_refresh_info()


## Точка дороги под курсором (или null, если мимо трассы).
func _road_hit(track: Track, camera: Camera3D, screen_pos: Vector2) -> Variant:
	var origin := camera.project_ray_origin(screen_pos)
	var normal := camera.project_ray_normal(screen_pos)
	if normal.y > -0.001:
		return null
	# Плоскость на высоте дороги: сначала высота трассы, потом — точки трассы под курсором.
	var height := track.global_position.y
	var point := Vector3.ZERO
	for i in 2:
		point = origin + normal * ((height - origin.y) / normal.y)
		height = track.get_point_at(float(TrackLayout.locate(track, point)["offset"])).y
	var where := TrackLayout.locate(track, point)
	if absf(float(where["lateral"])) > track.outline_half_width_at(float(where["offset"])) + track.wall_width + 1.0:
		return null
	return point


func _place(track: Track, hit: Vector3) -> void:
	var entry: Dictionary = PALETTE[_placing]
	var props := _props(track)
	var step: float = _along_step.value if _snap_lanes.button_pressed else 0.0
	var nodes: Array[Node3D] = []
	if entry.has("item_row"):
		nodes = _item_row(track, props, hit, int(entry["item_row"]), step)
	else:
		var node := (load(entry["scene"]) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node3D
		var settings: Dictionary = entry.get("set", {})
		for property in settings:
			node.set(property, settings[property])
		var xform: Transform3D
		if entry.get("wall", false):
			xform = TrackLayout.wall_transform(track, node, hit, step)
		else:
			var offset := float(TrackLayout.locate(track, hit)["offset"])
			var yaw := TrackLayout.track_yaw(track, offset) + _place_relative
			xform = TrackLayout.snapped_transform(track, node, hit, yaw, step, _snap_lanes.button_pressed)
		node.transform = props.global_transform.affine_inverse() * xform
		nodes.append(node)
	_add_nodes(track, props, nodes, entry["base"], "Трасса: поставить «%s»" % entry["title"])


## Ряд мест коробок поперёк дороги (через ITEM_BOX_SPACING), целиком на дороге.
func _item_row(track: Track, props: Node3D, hit: Vector3, count: int, step: float) -> Array[Node3D]:
	var where := TrackLayout.locate(track, hit)
	var offset := float(where["offset"])
	if step > 0.0:
		offset = snappedf(offset, step)
	var half_span := (count - 1) * 0.5 * ITEM_BOX_SPACING
	var limit := maxf(track.road_half_width_at(offset) - TrackLayout.DEFAULT_HALF_SIZE - TrackLayout.WALL_CLEARANCE - half_span, 0.0)
	var center := clampf(snappedf(float(where["lateral"]), ITEM_BOX_SPACING * 0.5), -limit, limit)
	var result: Array[Node3D] = []
	for k in count:
		var marker := Marker3D.new()
		marker.gizmo_extents = 1.0
		marker.add_to_group(TrackLayout.ITEM_BOX_GROUP, true)
		var lateral := center + (k - (count - 1) * 0.5) * ITEM_BOX_SPACING
		var xform := Transform3D(Basis(Vector3.UP, TrackLayout.track_yaw(track, offset)), track.get_point_at(offset, lateral))
		marker.transform = props.global_transform.affine_inverse() * xform
		result.append(marker)
	return result


func _add_nodes(track: Track, props: Node3D, nodes: Array[Node3D], base: String, title: String) -> void:
	var taken := {}
	var undo := get_undo_redo()
	undo.create_action(title)
	for node in nodes:
		node.name = _free_name(props, base, taken)
		undo.add_do_method(props, &"add_child", node, true)
		undo.add_do_method(node, &"set_owner", track)
		undo.add_do_reference(node)
		undo.add_undo_method(props, &"remove_child", node)
	undo.commit_action()
	_refresh_info()


func _free_name(props: Node, base: String, taken: Dictionary) -> String:
	var i := 1
	while props.has_node(NodePath("%s%d" % [base, i])) or taken.has("%s%d" % [base, i]):
		i += 1
	var result := "%s%d" % [base, i]
	taken[result] = true
	return result


## Узел Props трассы (создаётся, если его нет).
func _props(track: Track) -> Node3D:
	var props := track.get_node_or_null(^"Props") as Node3D
	if props == null:
		props = Node3D.new()
		props.name = "Props"
		track.add_child(props)
		props.owner = track
	return props


# --------------------------------------------------------------------------
# Выравнивание, проверка, заезд, новая карта
# --------------------------------------------------------------------------

func _on_align_selected() -> void:
	var track := _current_track()
	if track == null:
		return
	var props := _props(track)
	var nodes: Array[Node3D] = []
	for node in EditorInterface.get_selection().get_top_selected_nodes():
		if node is Node3D and node.get_parent() == props:
			nodes.append(node)
	if nodes.is_empty():
		_report.text = "Выделите объекты из узла Props."
		return
	_align(track, nodes, "Трасса: выровнять выделенные")


func _on_align_all() -> void:
	var track := _current_track()
	if track == null:
		return
	var nodes: Array[Node3D] = []
	for node in _props(track).get_children():
		if node is Node3D:
			nodes.append(node)
	_align(track, nodes, "Трасса: выровнять все объекты")


func _align(track: Track, nodes: Array[Node3D], title: String) -> void:
	var step: float = _along_step.value if _snap_lanes.button_pressed else 0.0
	var undo := get_undo_redo()
	undo.create_action(title)
	for node in nodes:
		var target: Transform3D
		if node.scene_file_path == ROAD_SIGN_SCENE:
			target = TrackLayout.wall_transform(track, node, node.global_position, step)
		else:
			target = TrackLayout.snapped_transform(track, node, node.global_position,
					node.global_basis.orthonormalized().get_euler().y, step, _snap_lanes.button_pressed)
		undo.add_do_property(node, &"global_transform", target)
		undo.add_undo_property(node, &"global_transform", node.global_transform)
	undo.commit_action()
	_report.text = "Выровнено объектов: %d (Ctrl+Z — отменить)." % nodes.size()


func _on_check() -> void:
	var track := _current_track()
	if track == null:
		_report.text = "Откройте сцену трассы."
		return
	var result := TrackCheck.run(track)
	var problems: PackedStringArray = result["problems"]
	var lines := PackedStringArray([result["summary"]])
	if problems.is_empty():
		lines.append("Замечаний нет.")
	else:
		lines.append("Замечания (%d):" % problems.size())
		for problem in problems:
			lines.append("• " + problem)
	# Проходимость и логика (level-дизайн): TrackFlow, метки — прямо на трассе в 3D-виде.
	var flow := TrackFlow.analyze(track)
	lines.append("Проходимость: " + flow["summary"])
	for issue in flow["issues"]:
		lines.append(("✗ " if issue["level"] == TrackFlow.ERROR else "• ") + TrackFlow.format(issue))
	_show_flow_markers(track, flow["issues"])
	_report.text = "\n".join(lines)


## Метки замечаний проходимости над трассой (не сохраняются в сцену; новая проверка — заново).
func _show_flow_markers(track: Track, issues: Array) -> void:
	var old := track.get_node_or_null(^"FlowMarkers")
	if old != null:
		old.free()
	if issues.is_empty():
		return
	var holder := Node3D.new()
	holder.name = "FlowMarkers"
	track.add_child(holder)
	for issue in issues:
		var label := Label3D.new()
		var is_error: bool = issue["level"] == TrackFlow.ERROR
		label.text = "%s %.0f м" % ["✗" if is_error else "!", issue["offset"]]
		label.modulate = Color(1.0, 0.25, 0.2) if is_error else Color(1.0, 0.8, 0.1)
		label.outline_size = 12
		label.font_size = 96
		label.pixel_size = 0.02
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		holder.add_child(label)
		label.global_position = track.get_point_at(issue["offset"], issue["lateral"]) + Vector3.UP * 4.0


func _on_play() -> void:
	var track := _current_track()
	if track == null or track.scene_file_path.is_empty():
		_report.text = "Откройте сохранённую сцену трассы."
		return
	EditorInterface.save_scene()
	var file := FileAccess.open(Race.EDITOR_TEST_MAP_FILE, FileAccess.WRITE)
	if file == null:
		_report.text = "Не удалось записать %s." % Race.EDITOR_TEST_MAP_FILE
		return
	file.store_string(track.scene_file_path)
	file.close()
	# Главная сцена — меню; пробный заезд — сразу сцена гонки.
	EditorInterface.play_custom_scene(RACE_SCENE)


func _on_new_map() -> void:
	var map_name := _new_name.text.strip_edges().to_lower()
	var regex := RegEx.create_from_string("^[a-z0-9_]+$")
	if map_name.is_empty() or regex.search(map_name) == null or map_name.begins_with("_"):
		_report.text = "Имя — латиница, цифры и «_» (не в начале), например my_map."
		return
	var path := TRACKS_DIR + map_name + ".tscn"
	if ResourceLoader.exists(path):
		_report.text = "Карта %s уже есть." % path
		return
	var track := _make_track(map_name, BACKGROUNDS[_new_background.selected][1])
	var packed := PackedScene.new()
	var err := packed.pack(track)
	if err == OK:
		err = ResourceSaver.save(packed, path)
	track.free()
	if err != OK:
		_report.text = "Не удалось сохранить %s: %s" % [path, error_string(err)]
		return
	EditorInterface.get_resource_filesystem().scan()
	EditorInterface.open_scene_from_path(path)
	_report.text = "Создана %s. Двигайте точки кривой Path (выделите Path), расставляйте объекты." % path


## Заготовка: прямоугольник 80 × 120 м со скруглёнными углами, эстакада над фоном.
func _make_track(map_name: String, background_path: String) -> Track:
	var track := Track.new()
	track.name = map_name.to_pascal_case()
	track.road_width = 13.5
	track.background_depth = 6.0
	track.background_scroll = Vector2(1.0, -2.0)
	track.support_scene = load("res://scenes/props/column.tscn")
	track.road_material = load("res://assets/materials/road.tres")
	track.wall_material = load("res://assets/materials/wall.tres")
	track.background_material = load(background_path)
	track.start_line_material = load("res://assets/materials/checker.tres")
	track.start_gate_scene = load("res://scenes/props/start_gate.tscn")
	var curve := Curve3D.new()
	curve.bake_interval = 0.5
	for p in [Vector3(0, 0, 0), Vector3(0, 0, -60), Vector3(80, 0, -60), Vector3(80, 0, 60), Vector3(0, 0, 60)]:
		curve.add_point(p)
	curve.closed = true
	var path := Path3D.new()
	path.name = "Path"
	path.curve = curve
	track.add_child(path)
	path.owner = track
	var props := Node3D.new()
	props.name = "Props"
	track.add_child(props)
	props.owner = track
	return track
