extends SceneTree
## Снимки окон интерфейса (нужно окно): страницы меню (1152×648), лобби хоста и гостя, пауза,
## настройки в паузе, результаты (384×216) — проверить вёрстку после правок UI.
## Данные — «как в игре»: ID игры, 4 игрока с длинными никами, найденные игры, результат
## проверки сети, — чтобы увидеть самые большие окна.
## Запуск: godot --path . -s res://scripts/tools/ui_shots.gd -- C:/папка/для/png [--size=1024x768]

const NAMES := ["Лимон", "stysan", "МаксимусМакс", "Гость_42"]

var _out := ""


func _initialize() -> void:
	_run.call_deferred()


func _shot(shot_name: String) -> void:
	for i in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(_out + "/" + shot_name + ".png")
	print("снимок ", shot_name, " ", img.get_size())


func _run() -> void:
	_out = OS.get_cmdline_user_args()[0]
	var window_size := Vector2i(1152, 648)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--size="):
			var parts := arg.trim_prefix("--size=").split("x")
			window_size = Vector2i(int(parts[0]), int(parts[1]))
	DisplayServer.window_set_size(window_size)
	root.size = window_size
	var net := Network.session()
	net.session_id = "K7QX2"
	net.online_status = Network.OnlineStatus.AVAILABLE
	net.found_games = {
		"K7QX2": {"name": "МаксимусМакс", "map": "remake_01", "players": 3, "max": 4, "open": true, "seen": 0.0},
		"B3ZTA": {"name": "stysan", "map": "map_h", "players": 1, "max": 4, "open": true, "seen": 0.0},
	}
	# Меню.
	var menu := (load("res://scenes/net/lobby_menu.tscn") as PackedScene).instantiate()
	root.add_child(menu)
	await _shot("menu_main")
	menu.call("_refresh_games")
	var check := menu.get("_check_result") as Label
	check.text = "\n".join(["трекеры: 3 из 3 отвечают",
			"роутер: строгий NAT. Войти получится, если у друга обычный. Если строгий у обоих, нужен TURN-сервер"])
	check.visible = true
	for page in [["menu_maps", 1], ["menu_garage", 2], ["menu_friends", 3], ["menu_settings", 4]]:
		menu.call("_show_page", page[1], false)
		await _shot(page[0])
	menu.queue_free()
	await process_frame
	# Гонка: лобби, пауза, настройки, результаты (4 участника).
	var race := (load("res://scenes/race/race.tscn") as PackedScene).instantiate() as Race
	race.track_scene = load("res://scenes/tracks/map_a.tscn") as PackedScene
	race.autostart = false
	root.add_child(race)
	var racers: Array[RacerState] = []
	for i in NAMES.size():
		var autopilot := AutopilotInputSource.new()
		autopilot.track = race.track
		race.add_child(autopilot)
		racers.append(race.spawn_racer(NAMES[i], i == 0, autopilot))
	race.begin()
	var hud := race.get_node("RaceHud") as RaceHud
	await _shot("race_hud")
	net.players = {1: {"name": NAMES[0], "slot": 0}}
	hud.show_lobby(true)
	# Хост один в комнате (сети нет — показываем как у настоящего хоста).
	(hud.get("_lobby_empty") as Control).visible = true
	(hud.get("_lobby_label") as Control).visible = false
	await _shot("lobby_host")
	for i in NAMES.size():
		net.players[i + 1] = {"name": NAMES[i], "slot": i}
	hud.show_lobby(false)
	await _shot("lobby_guest")
	hud.hide_lobby()
	var pause := race.get_node("PauseMenu") as PauseMenu
	pause.open()
	await _shot("pause")
	pause.call("_open_settings")
	await _shot("pause_settings")
	pause.close()
	var times := [83.46, 85.12, 91.07, -1.0]
	for i in racers.size():
		racers[i].finished = times[i] >= 0.0
		racers[i].finish_time = times[i]
		racers[i].finish_place = i + 1 if times[i] >= 0.0 else 0
		racers[i].place = i + 1
	hud.call("_show_results")
	await _shot("results")
	quit(0)
