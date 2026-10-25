@tool
extends RefCounted
## Самопроверка редактора карт в настоящем редакторе Godot (без окна):
##   godot --headless --path . --editor -- --track-editor-selftest
## Создаёт временную карту, ставит объекты «кликом», отменяет/повторяет, выравнивает,
## проверяет карту, удаляет временную карту и закрывает редактор с кодом 0 (всё прошло) или 1.

const ARG := "--track-editor-selftest"
const MAP_NAME := "zz_editor_selftest"

var _plugin: EditorPlugin
var _failures: PackedStringArray = []


static func requested() -> bool:
	return OS.get_cmdline_user_args().has(ARG)


func run(plugin: EditorPlugin) -> void:
	_plugin = plugin
	print("TRACK EDITOR SELFTEST: старт")
	var tree := plugin.get_tree()
	await _frames(tree, 30)
	print("TRACK EDITOR SELFTEST: редактор готов")
	var path: String = plugin.TRACKS_DIR + MAP_NAME + ".tscn"
	if ResourceLoader.exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	# Новая карта.
	plugin._new_name.text = MAP_NAME
	plugin._on_new_map()
	await _frames(tree, 10)
	var track := EditorInterface.get_edited_scene_root() as Track
	_check(track != null and track.scene_file_path == path, "новая карта создана и открыта")
	if track == null:
		_finish(tree, path)
		return
	_check(track.length > 300.0, "трасса построена в редакторе (круг %.0f м)" % track.length)
	_check(track.get_node_or_null(^"Generated/EditorGuides") != null, "в редакторе видны полосы и отметки")

	# Бочка «кликом»: точка чуть правее середины -> встаёт на середину полосы, по трассе.
	var lane := TrackLayout.lane_step(track)
	plugin._placing = _palette_index(plugin, "Бочка")
	plugin._place(track, track.get_point_at(30.3, 1.0))
	var barrel := track.get_node_or_null(^"Props/Barrel1") as Node3D
	_check(barrel != null and barrel.owner == track, "бочка поставлена и сохранится в сцене")
	if barrel != null:
		var where := TrackLayout.locate(track, barrel.global_position)
		_check(is_equal_approx(float(where["offset"]), 30.0) and absf(float(where["lateral"])) < 0.01,
				"бочка на полосе: %.2f м от старта, %+.2f м вбок" % [where["offset"], where["lateral"]])

	# Ряд коробок и отмена/повтор.
	plugin._placing = _palette_index(plugin, "Коробки ×3")
	plugin._place(track, track.get_point_at(60.0, 0.0))
	_check(_count_boxes(track) == 3, "ряд из 3 коробок (%d)" % _count_boxes(track))
	var undo := plugin.get_undo_redo()
	var history := undo.get_history_undo_redo(undo.get_object_history_id(track))
	history.undo()
	_check(_count_boxes(track) == 0, "Ctrl+Z убирает ряд коробок")
	history.redo()
	_check(_count_boxes(track) == 3, "повтор возвращает ряд")

	# Зона (лёд): её картинка не сохраняется в сцену, выбрать кликом её можно только по гизмо плагина.
	plugin._placing = _palette_index(plugin, "Лёд 8×10")
	plugin._place(track, track.get_point_at(150.0, 0.0))
	await _frames(tree, 2)
	var zone: MapZone = null
	for child in track.get_node(^"Props").get_children():
		if child is MapZone:
			zone = child
	_check(zone != null and zone.get_gizmos().any(func(gizmo: Node3DGizmo) -> bool:
			return gizmo is EditorNode3DGizmo and (gizmo as EditorNode3DGizmo).get_plugin() == plugin._zone_gizmo),
			"у зоны есть рамка-гизмо (выделяется кликом и двигается)")

	# Ширина участка: 2 блока (6 м) на участке у отметки 150 м, Ctrl+Z — обратно.
	var segment: int = track.segment_at(150.0)
	var normal_half: float = track.road_half_width_at(150.0)
	plugin._set_segment_width(track, segment, 6.0)
	await _frames(tree, 2)
	_check(segment >= 0 and is_equal_approx(track.road_half_width_at(150.0), 3.0)
			and track.get_node_or_null(^"Generated/TrackBody/Road") != null,
			"ширина участка %d: 2 блока (%.1f м), дорога перестроена" % [segment, track.road_half_width_at(150.0) * 2.0])
	history = undo.get_history_undo_redo(undo.get_object_history_id(track))
	history.undo()
	await _frames(tree, 2)
	_check(is_equal_approx(track.road_half_width_at(150.0), normal_half), "Ctrl+Z возвращает прежнюю ширину")

	# Выравнивание: сдвинутая и повёрнутая бочка возвращается на полосу.
	if barrel != null:
		barrel.global_position += TrackLayout.track_right(track, 30.0) * (lane + 0.7)
		barrel.rotate_y(deg_to_rad(13.0))
		EditorInterface.get_selection().clear()
		EditorInterface.get_selection().add_node(barrel)
		await _frames(tree, 2)
		plugin._on_align_selected()
		var where := TrackLayout.locate(track, barrel.global_position)
		var yaw_error := absf(wrapf(barrel.global_basis.orthonormalized().get_euler().y - TrackLayout.track_yaw(track, 30.0), -PI, PI))
		_check(absf(float(where["lateral"]) - lane) < 0.01 and yaw_error < 0.01,
				"«Выровнять выделенные»: бочка на соседней полосе (%+.2f м), повёрнута по трассе" % where["lateral"])

	# Клик мышью: камера над дорогой, луч из точки экрана попадает в нужное место.
	var camera := Camera3D.new()
	track.add_child(camera)
	var target := track.get_point_at(100.0, 2.0)
	camera.global_position = target + Vector3(0.0, 40.0, 25.0)
	camera.look_at(target)
	await _frames(tree, 2)
	var hit: Variant = plugin._road_hit(track, camera, camera.unproject_position(target))
	_check(hit != null and (hit as Vector3).distance_to(target) < 0.05, "клик по экрану попадает в точку дороги")
	camera.queue_free()

	plugin._on_check()
	_check(plugin._report.text.contains("пустой участок"), "проверка карты сообщает о пустых участках")
	await _screenshot_if_requested(tree, track)
	_finish(tree, path)


## С окном и аргументом --track-editor-shot=<файл.png> — снимок окна редактора.
func _screenshot_if_requested(tree: SceneTree, track: Track) -> void:
	var shot := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--track-editor-shot="):
			shot = arg.trim_prefix("--track-editor-shot=")
	if shot.is_empty() or DisplayServer.get_name() == "headless":
		return
	# Редактор без изменений не перерисовывается — на время снимка рисуем каждый кадр.
	OS.low_processor_usage_mode = false
	EditorInterface.set_main_screen_editor("3D")
	_plugin._dock.make_visible()
	EditorInterface.edit_node(track.get_node(^"Props/Barrel1"))
	_plugin._placing = _palette_index(_plugin, "Бочка")
	_plugin._update_place_status("Под курсором: 30.0 м от старта, +0.00 м от середины.")
	_plugin._place_buttons[_plugin._placing].set_pressed_no_signal(true)
	await _frames(tree, 30)
	await RenderingServer.frame_post_draw
	EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(shot)
	_plugin._stop_placing()


func _finish(tree: SceneTree, path: String) -> void:
	EditorInterface.close_scene()
	if ResourceLoader.exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if _failures.is_empty():
		print("TRACK EDITOR SELFTEST: ВСЁ ПРОШЛО")
	else:
		print("TRACK EDITOR SELFTEST: ОШИБКИ (%d)" % _failures.size())
		for failure in _failures:
			print("  - ", failure)
	tree.quit(0 if _failures.is_empty() else 1)


func _palette_index(plugin: EditorPlugin, title: String) -> int:
	for i in plugin.PALETTE.size():
		if plugin.PALETTE[i]["title"] == title:
			return i
	return -1


func _count_boxes(track: Track) -> int:
	var count := 0
	for node in track.get_node(^"Props").get_children():
		if node.is_in_group(TrackLayout.ITEM_BOX_GROUP):
			count += 1
	return count


func _frames(tree: SceneTree, count: int) -> void:
	for i in count:
		await tree.process_frame


func _check(condition: bool, description: String) -> void:
	print("[%s] %s" % ["OK" if condition else "FAIL", description])
	if not condition:
		_failures.append(description)
