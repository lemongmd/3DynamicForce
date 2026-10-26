extends SceneTree
## Автоматическая проверка этапа 2: целая гонка четырёх участников на автопилоте
## (AutopilotInputSource — только для тестов, ботов в игре нет) на каждой карте из MAPS.
##
## Проверяет: трассу (длину), обратный отсчёт (машины стоят), старт, круги через
## чекпоинты, места, финиш всех участников, барьеры (никто не выезжает за край),
## «призрака» после финиша, отсутствие провалов под трассу.
##
## Запуск (из корня проекта; --fixed-fps 60 — симуляция быстрее реального времени):
##   godot --headless --fixed-fps 60 --path . -s res://scripts/tools/race_test.gd
## С окном и скриншотом в начале гонки:
##   godot --fixed-fps 60 --path . -s res://scripts/tools/race_test.gd -- --screenshot=C:/путь/race.png
## Код возврата 0 — всё прошло, 1 — есть ошибки.

const RACE_PATH := "res://scenes/race/race.tscn"
## Карты, на которых проводится гонка (res://scenes/tracks/<имя>.tscn).
const MAPS := ["remake_01", "map_a", "map_b", "map_d", "map_e", "map_f", "map_g"]
const TEST_LAPS := 2
## Предел симуляции на всю гонку, с.
const MAX_RACE_TIME := 240.0
## Участники: имя, доля скорости автопилота, полоса.
const RACERS := [["Игрок", 0.95, 0.0], ["Гость 1", 0.92, -2.5], ["Гость 2", 0.89, 2.5], ["Гость 3", 0.86, 0.0]]

var _failures: PackedStringArray = []
var _race: Race
var _manager: RaceManager
var _respawns: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# -- --maps=map_a,map_f — только эти карты (по умолчанию MAPS).
	var maps: Array = MAPS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--maps="):
			maps = Array(arg.trim_prefix("--maps=").split(","))
	for map_name in maps:
		print("\n=== Карта %s ===" % map_name)
		await _race_on(map_name)

	if _failures.is_empty():
		print("RACE TEST: ВСЁ ПРОШЛО")
		quit(0)
	else:
		print("RACE TEST: ОШИБКИ (%d)" % _failures.size())
		for failure in _failures:
			print("  - ", failure)
		quit(1)


func _race_on(map_name: String) -> void:
	_respawns.clear()
	_race = (load(RACE_PATH) as PackedScene).instantiate() as Race
	_race.track_scene = load("res://scenes/tracks/%s.tscn" % map_name) as PackedScene
	_race.laps = TEST_LAPS
	_race.autostart = false
	root.add_child(_race)
	_manager = _race.race_manager
	for i in RACERS.size():
		var autopilot := AutopilotInputSource.new()
		autopilot.name = "Autopilot%d" % i
		autopilot.track = _race.track
		autopilot.skill = RACERS[i][1]
		autopilot.lane_offset = RACERS[i][2]
		_race.add_child(autopilot)
		var racer := _race.spawn_racer(RACERS[i][0], i == 0, autopilot)
		autopilot.car = racer.car
	_race.begin()
	var items_used := {}
	for racer in _manager.racers:
		_respawns[racer.display_name] = 0
		var racer_name := racer.display_name
		racer.car.respawned.connect(func() -> void: _respawns[racer_name] += 1)
		CarItems.of(racer.car).item_used.connect(func(item: Item) -> void:
				items_used[item.id] = int(items_used.get(item.id, 0)) + 1)

	var track := _race.track
	_check(track.length > 300.0 and track.length < 1500.0, "трасса построена (длина круга %.0f м)" % track.length)
	_check(_manager.racers.size() == 4, "в гонке 4 участника (%d)" % _manager.racers.size())
	# Скины: у каждой машины своя покраска (CarSkin.paint), цвета иконок разные.
	var codes := {}
	var painted := 0
	for racer in _manager.racers:
		codes[racer.skin.to_code()] = true
		var model := racer.car.get_node("Visual/Model")
		for mesh in model.find_children("*", "MeshInstance3D", true, false):
			if (mesh as MeshInstance3D).get_surface_override_material(0) != null:
				painted += 1
				break
	_check(codes.size() == 4 and painted == 4, "у машин свои скины (%d разных, покрашено %d)" % [codes.size(), painted])

	await _frames(60)
	_check(_manager.state == RaceManager.State.COUNTDOWN, "идёт обратный отсчёт")
	var max_speed := 0.0
	for racer in _manager.racers:
		max_speed = maxf(max_speed, absf(racer.car.forward_speed))
		_check(racer.lap == 0, "%s ещё не начал круг до старта" % racer.display_name)
	_check(max_speed < 0.5, "во время отсчёта машины стоят (макс. скорость %.2f)" % max_speed)

	await _frames(150)
	_check(_manager.state == RaceManager.State.RACING, "после отсчёта гонка началась")
	await _take_screenshot_if_requested()

	await _frames(600)
	var places := {}
	for racer in _manager.racers:
		places[racer.place] = true
		_check(racer.lap == 1, "%s едет 1-й круг через 10 с" % racer.display_name)
		# По дистанции, а не по мгновенной скорости: машину могло только что остановить ограждение.
		_check(racer.race_distance > 120.0, "%s едет (за 10 с проехал %.0f м)" % [racer.display_name, racer.race_distance])
	_check(places.size() == 4, "места 1..4 без повторов")
	_check(_race.track.music != null and GameMusic.player().current == _race.track.music,
			"после старта играет музыка карты")
	# Пауза (Esc): одиночная игра встаёт, «ПРОДОЛЖИТЬ» — едет дальше.
	var pause := _race.get_node("PauseMenu") as PauseMenu
	pause.open()
	var was_paused := paused
	pause.close()
	_check(was_paused and not paused, "пауза останавливает игру и снимается")

	var max_off := {}
	var lowest := INF
	var frames := 0
	while _manager.state != RaceManager.State.FINISHED and frames < int(MAX_RACE_TIME * 60.0):
		await physics_frame
		frames += 1
		for racer in _manager.racers:
			max_off[racer.display_name] = maxf(max_off.get(racer.display_name, 0.0), racer.progress.distance_from_center)
			lowest = minf(lowest, racer.car.global_position.y)

	_check(_manager.state == RaceManager.State.FINISHED, "гонка закончилась (время %.1f с)" % _manager.race_time)
	_check(GameMusic.player().current == GameMusic.FINISH, "после финиша первого — музыка финиша")
	# Дно — самая низкая точка трассы (у карт с подъёмами и спусками она ниже нуля).
	var floor_y := _race.track.lowest_point_y()
	_check(lowest > floor_y - 1.0, "никто не провалился под трассу (мин. высота %.2f, дно трассы %.2f)" % [lowest, floor_y])
	await _frames(2)
	var results := _race.get_node("RaceHud/Results") as Control
	var results_list := _race.get_node("RaceHud/Results/Window/Panel/Box/List") as Label
	_check(results.visible, "после гонки показаны результаты")
	_check(results_list.text.count("\n") == 3, "в результатах 4 строки")
	_check(RaceHud.format_time(83.456) == "1:23.46", "формат времени (%s)" % RaceHud.format_time(83.456))
	var used_total := 0
	for id in items_used:
		used_total += int(items_used[id])
	_check(_race.item_boxes.size() > 0 and used_total > 0,
			"коробок на трассе %d, применено предметов %d %s" % [_race.item_boxes.size(), used_total, items_used])
	var road_edge: float = track.max_road_width() * 0.5
	print("\nРезультаты:")
	for racer in _manager.get_sorted_racers():
		var laps_text := PackedStringArray()
		for t in racer.lap_times:
			laps_text.append("%.2f" % t)
		print("  %d. %-8s финиш %7.2f с  круги [%s]  макс. от центра %.1f м  возвратов %d" % [
			racer.place, racer.display_name, racer.finish_time, ", ".join(laps_text),
			max_off[racer.display_name], _respawns[racer.display_name]])
		_check(racer.finish_time > 0.0, "%s доехал до финиша" % racer.display_name)
		_check(racer.lap_times.size() == TEST_LAPS, "%s: засчитано кругов %d" % [racer.display_name, racer.lap_times.size()])
		for t in racer.lap_times:
			_check(t > track.length / 60.0, "%s: круг не короче физически возможного (%.1f с)" % [racer.display_name, t])
		_check(max_off[racer.display_name] < road_edge,
				"%s не заехал на стену (макс. %.1f м от центра, стена на %.1f м)" % [
					racer.display_name, max_off[racer.display_name], road_edge])
		_check(racer.car.is_ghost, "%s после финиша — призрак" % racer.display_name)
	_race.queue_free()
	await _frames(30)


func _take_screenshot_if_requested() -> void:
	var path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshot="):
			path = arg.trim_prefix("--screenshot=")
	if path.is_empty() or DisplayServer.get_name() == "headless":
		return
	await _frames(150)
	await RenderingServer.frame_post_draw
	var err := root.get_texture().get_image().save_png(path)
	_check(err == OK, "скриншот сохранён в %s" % path)


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _check(condition: bool, description: String) -> void:
	if not condition:
		print("[FAIL] ", description)
		_failures.append(description)
	else:
		print("[OK] ", description)
