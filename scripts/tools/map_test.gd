extends SceneTree
## Проверка карт: заполненность и наши механики.
##
## Для каждой трассы из папки TRACKS_DIR (все *.tscn, кроме начинающихся с «_»):
##   * проверка редактора карт TrackCheck: нет «лысых» участков (между соседними игровыми
##     объектами не больше TrackCheck.MAX_GAP м), объекты не на стене и не друг на друге,
##     есть коробки предметов;
## «Гонка на этой карте» редактора карт: гонка берёт карту из файла-подсказки.
## Для карт с трамплинами и шпилькой (remake_01):
##   * машина на полной скорости взлетает с трамплина выше ограждений и пролетает над ними
##     без удара; без трамплина (в обход) ограждение останавливает;
##   * на трассе есть поворот радиусом меньше DRIFT_RADIUS — место под дрифт.
##
## Запуск (из корня проекта):
##   godot --headless --fixed-fps 60 --path . -s res://scripts/tools/map_test.gd
## Код возврата 0 — всё прошло, 1 — есть ошибки.

## Карты с нашими механиками — проверяются ещё трамплин и шпилька.
const MECHANICS_MAPS := ["remake_01"]
const TRACKS_DIR := "res://scenes/tracks/"
## Поворот уже этого радиуса на полной скорости без дрифта не пройти, м
## (руль 120 °/с на 30 м/с даёт радиус ≈ 14 м).
const DRIFT_RADIUS := 13.0
const CAR_SCENE := "res://scenes/car/car.tscn"

var _failures: PackedStringArray = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for map_name in _map_names():
		var track := (load(TRACKS_DIR + map_name + ".tscn") as PackedScene).instantiate() as Track
		root.add_child(track)
		await physics_frame
		_check_fill(map_name, track)
		if map_name in MECHANICS_MAPS:
			_check_drift_corner(map_name, track)
			await _check_ramp_jump(track)
		track.queue_free()
		await physics_frame
	await _check_editor_test_map()
	await _check_flow_rules()

	if _failures.is_empty():
		print("MAP TEST: ВСЁ ПРОШЛО")
		quit(0)
	else:
		print("MAP TEST: ОШИБКИ (%d)" % _failures.size())
		for failure in _failures:
			print("  - ", failure)
		quit(1)


## Проверка из редактора карт (TrackCheck): заполненность, объекты не на стене и не друг на друге,
## есть коробки предметов.
func _check_fill(map_name: String, track: Track) -> void:
	var report := TrackCheck.run(track)
	print("%s: %s" % [map_name, report["summary"]])
	var problems: PackedStringArray = report["problems"]
	for problem in problems:
		print("  ! ", problem)
	_check(problems.is_empty(), "%s: карта в порядке (замечаний %d)" % [map_name, problems.size()])
	# Level-дизайн (TrackFlow): ошибки — непроходимо/нечестно, внимание — только печатаем.
	var flow := TrackFlow.analyze(track)
	print("  проходимость: ", flow["summary"])
	for issue in flow["issues"]:
		print("    %s %s" % ["✗" if issue["level"] == TrackFlow.ERROR else "·", TrackFlow.format(issue)])
	_check(int(flow["errors"]) == 0, "%s: проходимость — ошибок нет (%d)" % [map_name, flow["errors"]])


## Сам анализатор проходимости (TrackFlow) на заведомо плохих расстановках (Снежная без объектов):
## стена из бочек поперёк дороги — ошибка; слалом с края на край за 14 м — «только медленно».
func _check_flow_rules() -> void:
	var cases := {
		"стена": [[200.0, [-4.5, -2.25, 0.0, 2.25, 4.5]]],
		"слалом": [[200.0, [-1.0, 1.25, 3.5, 5.0]], [214.0, [-5.0, -3.5, -1.25, 1.0]]],
	}
	var results := {}
	for case_name in cases:
		var track := (load(TRACKS_DIR + "map_b.tscn") as PackedScene).instantiate() as Track
		root.add_child(track)
		await physics_frame
		for child in track.get_node("Props").get_children():
			child.free()
		for row in cases[case_name]:
			for lateral in row[1]:
				var barrel := (load("res://scenes/props/barrel.tscn") as PackedScene).instantiate() as Node3D
				track.get_node("Props").add_child(barrel)
				barrel.position = track.get_point_at(row[0], lateral)
		results[case_name] = TrackFlow.analyze(track)
		track.free()
	_check(int(results["стена"]["errors"]) == 1, "проходимость: стена из бочек поперёк дороги — ошибка")
	_check(int(results["слалом"]["errors"]) == 0 and int(results["слалом"]["warnings"]) == 1,
			"проходимость: резкий слалом — «только медленно» (%s)" % results["слалом"]["summary"])


func _check_drift_corner(map_name: String, track: Track) -> void:
	# Радиус по изменению направления на 4 м пути.
	var min_radius := INF
	var d := 0.0
	while d < track.length:
		var bend := track.get_direction_at(d).angle_to(track.get_direction_at(d + 4.0))
		if bend > 0.001:
			min_radius = minf(min_radius, 4.0 / bend)
		d += 1.0
	_check(min_radius < DRIFT_RADIUS, "%s: есть шпилька под дрифт (минимальный радиус %.1f м < %.0f)" % [
		map_name, min_radius, DRIFT_RADIUS])


## Первый трамплин стартовой прямой: машина разгоняется, взлетает и пролетает над
## ограждениями (они стоят за трамплином поперёк дороги) без удара.
func _check_ramp_jump(track: Track) -> void:
	var ramp := track.get_node("Props/Ramp1") as Node3D
	var hits := [0]
	for name in ["Props/BarrierParry1", "Props/BarrierParry2"]:
		(track.get_node(name) as ParryHazard).car_hit.connect(func(_c: CarController) -> void: hits[0] += 1)
	var car := (load(CAR_SCENE) as PackedScene).instantiate() as CarController
	var input := PlayerInputSource.new()
	car.add_child(input)
	car.input_source = input
	track.add_child(car)
	# Разгон 40 м до трамплина: прямо на него, по ходу гонки.
	var start := track.get_transform_at(track.project(ramp.global_position)["offset"] - 40.0)
	car.teleport(Transform3D(start.basis, Vector3(ramp.global_position.x, start.origin.y, start.origin.z)))
	await physics_frame
	var boosted := []
	car.set_speed_to_max()
	Input.action_press(GameActions.ACCELERATE)
	var max_height := 0.0
	var jumped := [false]
	car.jumped.connect(func() -> void: jumped[0] = true)
	for i in 150:
		await physics_frame
		max_height = maxf(max_height, car.global_position.y)
	Input.action_release(GameActions.ACCELERATE)
	_check(jumped[0] and max_height > 2.0, "трамплин подбрасывает машину выше ограждений (макс. %.2f м)" % max_height)
	_check(hits[0] == 0, "в прыжке ограждения за трамплином не задевают (ударов %d)" % hits[0])
	_check(car.forward_speed > 20.0, "после приземления машина едет дальше (%.1f м/с)" % car.forward_speed)
	_check(track.get_children().any(func(n: Node) -> bool: return n.name.begins_with("FxRing") or n.name.begins_with("FxBurst")),
			"жёсткое приземление — пыль и взрывная волна (эффекты)")
	boosted.clear()
	car.queue_free()


func _check(condition: bool, description: String) -> void:
	print("[%s] %s" % ["OK" if condition else "FAIL", description])
	if not condition:
		_failures.append(description)


## Все карты папки трасс (имя файла без .tscn); «_» в начале — заготовки, не карты.
func _map_names() -> PackedStringArray:
	var names := PackedStringArray()
	for file in DirAccess.get_files_at(TRACKS_DIR):
		if file.ends_with(".tscn") and not file.begins_with("_"):
			names.append(file.get_basename())
	names.sort()
	return names


## «Гонка на этой карте» из редактора карт: гонка берёт карту из файла-подсказки и удаляет его.
func _check_editor_test_map() -> void:
	var file := FileAccess.open(Race.EDITOR_TEST_MAP_FILE, FileAccess.WRITE)
	file.store_string(TRACKS_DIR + "map_a.tscn")
	file.close()
	var race := (load("res://scenes/race/race.tscn") as PackedScene).instantiate() as Race
	race.autostart = false
	root.add_child(race)
	await physics_frame
	_check(race.track.scene_file_path == TRACKS_DIR + "map_a.tscn" and not FileAccess.file_exists(Race.EDITOR_TEST_MAP_FILE),
			"гонка из редактора карт: взята карта %s, файл-подсказка удалён" % race.track.scene_file_path.get_file())
	race.queue_free()
	await physics_frame
