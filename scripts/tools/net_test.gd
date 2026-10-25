extends SceneTree
## Проверка этапа 6: настоящая сетевая игра двух копий игры на этом компьютере (Tube,
## локальная сеть, без интернета). Хост создаёт сессию и сам запускает клиента отдельным
## процессом (вход по ID сессии); обе машины едут на автопилоте круг с предметами.
## Проверяется: вход по ID, лобби, старт по команде хоста, плавность чужих машин (нет
## рывков), круги/финиш/места от хоста, коробки через хоста, конец гонки у клиента.
##
## Запуск (из корня проекта; без --fixed-fps — время должно идти по-настоящему):
##   godot --headless --path . -s res://scripts/tools/net_test.gd
## Код возврата 0 — всё прошло, 1 — есть ошибки. Клиент пишет итоги в user://net_test_client.json.

const MAP := "remake_01"
const LAPS := 1
const CLIENT_LOG := "user://net_test_client.json"
## Ограничения по времени, с.
const JOIN_TIMEOUT := 30.0
const RACE_TIMEOUT := 120.0
const CLIENT_REPORT_TIMEOUT := 20.0
## Чужая машина не должна прыгать за кадр дальше, чем проехала бы, + запас, м.
const JUMP_MARGIN := 1.5
## Скин клиента (синий спорт с рисунком) — должен прийти хосту.
const CLIENT_SKIN := "01301251"

var _failures: PackedStringArray = []
var _role := "host"
var _session_id := ""


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			_role = arg.trim_prefix("--role=")
		elif arg.begins_with("--id="):
			_session_id = arg.trim_prefix("--id=")
	_run.call_deferred()


func _run() -> void:
	var net := Network.session()
	while not net.is_inside_tree():
		await process_frame
	net.use_internet = false
	if not Network.is_available():
		_check(false, "есть WebRTC (addons/webrtc_native)")
		_finish()
		return
	if _role == "client":
		await _run_client(net)
	else:
		await _run_host(net)


# --------------------------------------------------------------------------
# Хост
# --------------------------------------------------------------------------

func _run_host(net: Network) -> void:
	_check(net.host_game("Хост", MAP), "хост создал сессию")
	_check(net.session_id.length() == 5, "ID сессии из 5 знаков (%s)" % net.session_id)
	var race := await _wait_race(net)
	if race == null:
		_finish()
		return
	_drive_on_start(race)
	# Коробки, которые хост выдал чужой машине (клиенту), — считаем с самого начала:
	# клиент заезжает в коробку сразу после входа.
	var client_boxes := [0]
	for box in race.item_boxes:
		box.picked.connect(func(car: CarController, _item: Item) -> void:
			if car != null and car.is_puppet:
				client_boxes[0] += 1)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CLIENT_LOG))
	var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"),
			"-s", "res://scripts/tools/net_test.gd", "--", "--role=client", "--id=" + net.session_id])
	var pid := OS.create_process(OS.get_executable_path(), args)
	_check(pid > 0, "клиент запущен (процесс %d)" % pid)

	var waited := await _wait_until(func() -> bool: return net.players.size() == 2, JOIN_TIMEOUT)
	_check(waited, "клиент вошёл по ID за %.1f с (игроков %d)" % [_elapsed, net.players.size()])
	if not waited:
		_kill(pid)
		_finish()
		return
	var client_id := 0
	for id in net.players:
		if int(id) != 1:
			client_id = int(id)
	var client_car := race.get_net_car(client_id)
	_check(client_car != null and client_car.is_puppet, "машина клиента у хоста — марионетка")
	# Скин клиента (CLIENT_SKIN) дошёл до хоста вместе с ником, машина клиента — в нём.
	var client_skin := String(net.players[client_id].get("skin", ""))
	var skinned := race.race_manager.racers.filter(func(r: RacerState) -> bool: return r.car == client_car)
	_check(client_skin == CLIENT_SKIN and not skinned.is_empty() and skinned[0].skin.to_code() == CLIENT_SKIN,
			"скин клиента у хоста: %s" % client_skin)
	var synced := await _wait_until(func() -> bool:
		return client_car != null and NetCarSync.of(client_car).has_data(), 10.0)
	_check(synced, "состояние машины клиента доходит до хоста")

	var host_jumps := _watch_jumps(client_car)
	# В лобби клиент заезжает в коробку: её выдаёт хост (до старта — чтобы проверка не
	# зависела от того, проедет ли автопилот через коробку за круг).
	var boxed := await _wait_until(func() -> bool: return client_boxes[0] > 0, 15.0)
	_check(boxed, "клиент взял коробку через хоста (%d)" % client_boxes[0])
	net.request_start(LAPS)
	var finished := await _wait_until(func() -> bool:
		return race.race_manager.state == RaceManager.State.FINISHED, RACE_TIMEOUT)
	_check(finished, "гонка закончилась за %.0f с" % _elapsed)
	var client_racer := race.get_net_racer(client_id)
	_check(client_racer != null and client_racer.finish_time > 0.0,
			"хост засчитал клиенту круг и финиш (%.1f с)" % (client_racer.finish_time if client_racer != null else -1.0))
	_check(race.player_racer.finish_time > 0.0, "хост сам доехал (%.1f с)" % race.player_racer.finish_time)
	_check(host_jumps["max"] < JUMP_MARGIN + 2.0,
			"у хоста машина клиента едет без рывков (лишнее смещение за кадр до %.2f м)" % host_jumps["max"])

	var report_ready := await _wait_until(func() -> bool:
		return FileAccess.file_exists(CLIENT_LOG), CLIENT_REPORT_TIMEOUT)
	_check(report_ready, "клиент прислал итоги")
	if report_ready:
		var report = JSON.parse_string(FileAccess.get_file_as_string(CLIENT_LOG))
		if report is Dictionary:
			for line in report.get("ok", []):
				print("[OK] клиент: ", line)
			for line in report.get("fail", []):
				print("[FAIL] клиент: ", line)
				_failures.append("клиент: " + String(line))
	_kill(pid)
	net.leave("")
	_finish()


# --------------------------------------------------------------------------
# Клиент
# --------------------------------------------------------------------------

func _run_client(net: Network) -> void:
	var report := {"ok": [], "fail": []}
	net.player_skin = CLIENT_SKIN
	var joined := net.join_game(_session_id, "Клиент")
	_report(report, joined, "вход по ID %s начат" % _session_id)
	var race := await _wait_race(net)
	_report(report, race != null, "клиент в лобби на карте хоста")
	if race == null:
		_write_report(report)
		quit(1)
		return
	_drive_on_start(race)
	var host_car := race.get_net_car(1)
	_report(report, host_car != null and host_car.is_puppet, "машина хоста у клиента — марионетка")
	# Заехать в коробку (лобби): хост решает, что внутри, предмет приходит в свой слот.
	var items := CarItems.of(race.player_racer.car)
	var box: ItemBox = race.item_boxes[0]
	race.player_racer.car.teleport(Transform3D(Basis.IDENTITY, box.global_position + Vector3.UP * 0.1))
	var got_item := await _wait_until(func() -> bool: return items.current != null, 10.0)
	_report(report, got_item, "коробка через хоста: в слоте %s" % (items.current.id if items.current != null else "пусто"))
	var jumps := _watch_jumps(host_car)
	var finished := await _wait_until(func() -> bool:
		return race.race_manager.state == RaceManager.State.FINISHED, RACE_TIMEOUT + 15.0)
	_report(report, finished, "клиент получил от хоста конец гонки")
	var me := race.player_racer
	_report(report, me.finish_time > 0.0 and me.finish_place > 0,
			"хост засчитал клиенту финиш: %d место, %.1f с" % [me.finish_place, me.finish_time])
	var host_racer := race.get_net_racer(1)
	_report(report, host_racer != null and host_racer.finish_place > 0 and host_racer.finish_place != me.finish_place,
			"места не совпадают (хост %d, клиент %d)" % [host_racer.finish_place if host_racer != null else 0, me.finish_place])
	_report(report, jumps["max"] < JUMP_MARGIN + 2.0 and jumps["frames"] > 600,
			"машина хоста едет плавно: кадров %d, лишнее смещение до %.2f м" % [jumps["frames"], jumps["max"]])
	_write_report(report)
	await _wait_until(func() -> bool: return false, 5.0)
	quit(0)


func _report(report: Dictionary, condition: bool, text: String) -> void:
	(report["ok"] if condition else report["fail"]).append(text)


func _write_report(report: Dictionary) -> void:
	var file := FileAccess.open(CLIENT_LOG, FileAccess.WRITE)
	file.store_string(JSON.stringify(report))
	file.close()


# --------------------------------------------------------------------------
# Общее
# --------------------------------------------------------------------------

var _elapsed: float = 0.0


func _wait_until(condition: Callable, timeout: float) -> bool:
	var start := Time.get_ticks_msec()
	while not condition.call():
		_elapsed = (Time.get_ticks_msec() - start) / 1000.0
		if _elapsed > timeout:
			return false
		await physics_frame
	_elapsed = (Time.get_ticks_msec() - start) / 1000.0
	return true


## Сцена гонки сессии со своей машиной.
func _wait_race(net: Network) -> Race:
	var ok := await _wait_until(func() -> bool:
		return net.race != null and net.race.player_racer != null, JOIN_TIMEOUT)
	return net.race if ok else null


## На старте своя машина переходит на автопилот (в лобби стоит на месте).
func _drive_on_start(race: Race) -> void:
	race.race_manager.countdown_tick.connect(func(_left: int) -> void:
		var car := race.player_racer.car
		if car.input_source is AutopilotInputSource:
			return
		var autopilot := AutopilotInputSource.new()
		autopilot.track = race.track
		autopilot.car = car
		autopilot.skill = 0.9
		race.add_child(autopilot)
		car.input_source = autopilot)
	race.player_racer.car.input_source = null


## Следить за чужой машиной: насколько её смещение за кадр больше, чем она могла проехать.
## Телепорты (решётка) не считаются — первые кадры после смены отсчёта пропускаются.
func _watch_jumps(car: CarController) -> Dictionary:
	var stats := {"max": 0.0, "frames": 0}
	if car == null:
		return stats
	var state := {"prev": car.global_position, "skip": 30}
	physics_frame.connect(func() -> void:
		if not is_instance_valid(car):
			return
		var pos := car.global_position
		var moved: float = (pos - (state["prev"] as Vector3)).length()
		state["prev"] = pos
		var race := Network.session().race
		if race == null or race.race_manager.state != RaceManager.State.RACING:
			state["skip"] = 30
			return
		if int(state["skip"]) > 0:
			state["skip"] = int(state["skip"]) - 1
			return
		var allowed := maxf(absf(car.forward_speed), 30.0) * car.get_physics_process_delta_time()
		stats["max"] = maxf(float(stats["max"]), moved - allowed)
		stats["frames"] = int(stats["frames"]) + 1)
	return stats


func _kill(pid: int) -> void:
	if pid > 0 and OS.is_process_running(pid):
		OS.kill(pid)


func _check(condition: bool, description: String) -> void:
	print("[%s] %s" % ["OK" if condition else "FAIL", description])
	if not condition:
		_failures.append(description)


func _finish() -> void:
	if _failures.is_empty():
		print("NET TEST: ВСЁ ПРОШЛО")
		quit(0)
	else:
		print("NET TEST: ОШИБКИ (%d)" % _failures.size())
		for failure in _failures:
			print("  - ", failure)
		quit(1)
