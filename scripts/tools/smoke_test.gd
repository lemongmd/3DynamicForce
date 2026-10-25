extends SceneTree
## Автоматическая проверка этапов 1 и 3 на тестовой площадке.
##
## Грузит тестовый уровень, «нажимает» действия InputMap и проверяет, что
## машина разгоняется, рулит, дрифтует, тормозит, упирается в стену,
## прыгает с трамплина, возвращается после падения, сенсорная кнопка и
## разовые кнопки (парирование/предмет) доходят до машины, а парирование
## работает: без него ограждение останавливает машину, с ним — пропускает,
## просроченное окно не спасает.
##
## Запуск (из корня проекта):
##   godot --headless --path . -s res://scripts/tools/smoke_test.gd
## С окном и скриншотом:
##   godot --path . -s res://scripts/tools/smoke_test.gd -- --screenshot=C:/путь/shot.png
## Код возврата 0 — всё прошло, 1 — есть ошибки.

const LEVEL_PATH := "res://scenes/levels/test_level.tscn"
## Пустой угол площадки, где тесты не мешают препятствия.
const TEST_SPOT := Vector3(60.0, 0.05, 70.0)
## Старт перед парируемым ограждением (оно стоит поперёк на z = 0, x = -60).
const PARRY_START := Vector3(-60.0, 0.05, 30.0)
## Где у машины нос и у ограждения передний край (для расчёта момента нажатия).
const CAR_NOSE := 1.5
const BARRIER_FRONT_Z := 0.5

var _failures: PackedStringArray = []
var _level: Node
var _car: CarController
var _parry_count: int = 0
var _item_count: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_level = (load(LEVEL_PATH) as PackedScene).instantiate()
	root.add_child(_level)
	_car = _level.get_node("Car") as CarController
	_car.parry_requested.connect(func() -> void: _parry_count += 1)
	_car.item_requested.connect(func() -> void: _item_count += 1)
	await _frames(10)
	_check(_car.is_on_floor(), "машина стоит на земле")

	await _test_acceleration()
	await _test_steering()
	await _test_drift()
	await _test_drift_boost()
	await _test_brake_and_reverse()
	await _test_wall()
	await _test_ramp()
	await _test_one_shot_buttons()
	await _test_touch_button()
	await _test_respawn()
	await _test_parry()
	await _take_screenshot_if_requested()
	_level.queue_free()
	await _frames(30)

	if _failures.is_empty():
		print("SMOKE TEST: ВСЁ ПРОШЛО")
		quit(0)
	else:
		print("SMOKE TEST: ОШИБКИ (%d)" % _failures.size())
		for failure in _failures:
			print("  - ", failure)
		quit(1)


func _test_acceleration() -> void:
	await _place(TEST_SPOT)
	Input.action_press(GameActions.ACCELERATE)
	await _frames(180)
	_check(_car.forward_speed > _car.max_speed * 0.9, "разгон почти до максимума за 3 с (скорость %.1f)" % _car.forward_speed)
	_check(_car.global_position.z < TEST_SPOT.z - 20.0, "едет носом вперёд, к -Z (z = %.1f)" % _car.global_position.z)
	_release_all()


func _test_steering() -> void:
	await _place(TEST_SPOT)
	Input.action_press(GameActions.ACCELERATE)
	await _frames(60)
	Input.action_press(GameActions.STEER_RIGHT)
	await _frames(40)
	_check(_car.rotation.y < -0.5, "руль вправо поворачивает вправо (yaw = %.2f)" % _car.rotation.y)
	_check(_car.global_position.x > TEST_SPOT.x + 1.0, "машина уходит вправо (+X) (x = %.1f)" % _car.global_position.x)
	_release_all()


func _test_drift() -> void:
	await _place(TEST_SPOT)
	Input.action_press(GameActions.ACCELERATE)
	await _frames(70)
	Input.action_press(GameActions.DRIFT)
	Input.action_press(GameActions.STEER_LEFT)
	await _frames(5)
	_check(_car.is_drifting and _car.drift_direction == -1, "дрифт влево начинается")
	await _frames(30)
	_check(absf(_car.get_slide_angle()) > deg_to_rad(10.0), "в дрифте есть занос (%.0f°)" % rad_to_deg(_car.get_slide_angle()))
	Input.action_release(GameActions.STEER_LEFT)
	var yaw_before := _car.rotation.y
	await _frames(20)
	_check(_car.is_drifting, "дрифт держится без руля, пока зажата кнопка")
	_check(angle_difference(yaw_before, _car.rotation.y) > 0.2, "без руля машина продолжает поворачивать в сторону заноса")
	Input.action_release(GameActions.DRIFT)
	await _frames(2)
	_check(not _car.is_drifting, "отпустил кнопку — дрифт закончился")
	_release_all()


## Ускорение после дрифта (наша механика): короткий занос не даёт ничего,
## долгий (≥ drift_boost_min_time) при отпускании кнопки — толчок и повышенный предел.
func _test_drift_boost() -> void:
	var boosts := [0]
	var on_boost := func() -> void: boosts[0] += 1
	_car.drift_boosted.connect(on_boost)

	await _place(TEST_SPOT)
	Input.action_press(GameActions.ACCELERATE)
	await _frames(70)
	Input.action_press(GameActions.DRIFT)
	Input.action_press(GameActions.STEER_LEFT)
	await _frames(20)
	Input.action_release(GameActions.DRIFT)
	await _frames(2)
	_check(boosts[0] == 0, "короткий дрифт (0.3 с) ускорения не даёт")
	_release_all()

	await _place(TEST_SPOT)
	Input.action_press(GameActions.ACCELERATE)
	await _frames(70)
	Input.action_press(GameActions.DRIFT)
	Input.action_press(GameActions.STEER_LEFT)
	await _frames(int(_car.drift_boost_min_time * 60.0) + 10)
	Input.action_release(GameActions.STEER_LEFT)
	Input.action_release(GameActions.DRIFT)
	await _frames(2)
	_check(boosts[0] == 1 and _car.is_boosting(), "долгий дрифт — ускорение на выходе")
	_check(_car.get_max_speed() > _car.max_speed, "во время ускорения предел скорости выше обычного (%.1f > %.1f)" % [
		_car.get_max_speed(), _car.max_speed])
	await _frames(int(_car.get_boost_duration() * 60.0) + 5)
	_check(not _car.is_boosting() and is_equal_approx(_car.get_max_speed(), _car.max_speed),
			"ускорение заканчивается, предел возвращается")
	_car.drift_boosted.disconnect(on_boost)
	_release_all()

	# Стадии заряда (как мини-турбо Mario Kart): чем дольше занос, тем выше стадия и сильнее толчок.
	var stages: Array[int] = []
	var on_stage := func(stage: int) -> void: stages.append(stage)
	_car.drift_charged.connect(on_stage)
	await _place(TEST_SPOT)
	Input.action_press(GameActions.ACCELERATE)
	await _frames(70)
	Input.action_press(GameActions.DRIFT)
	Input.action_press(GameActions.STEER_LEFT)
	await _frames(int(_car.drift_stage_times[2] * 60.0) + 10)
	var stage := _car.get_drift_stage()
	Input.action_release(GameActions.STEER_LEFT)
	Input.action_release(GameActions.DRIFT)
	await _frames(2)
	_check(stages == [1, 2, 3] and stage == 3, "долгий занос проходит стадии 1, 2, 3 (%s)" % [stages])
	_check(is_equal_approx(_car.get_boost_duration(), _car.drift_stage_durations[2]),
			"выход на 3-й стадии — самое длинное ускорение (%.1f с)" % _car.get_boost_duration())
	_car.drift_charged.disconnect(on_stage)
	_release_all()


func _test_brake_and_reverse() -> void:
	await _place(TEST_SPOT)
	Input.action_press(GameActions.ACCELERATE)
	await _frames(60)
	Input.action_release(GameActions.ACCELERATE)
	Input.action_press(GameActions.BRAKE)
	await _frames(90)
	_check(_car.forward_speed < -1.0, "тормоз, затем задний ход (скорость %.1f)" % _car.forward_speed)
	_release_all()


func _test_wall() -> void:
	# Дальняя стена тестовой площадки стоит поперёк на z = -70.
	await _place(Vector3(0.0, 0.05, -60.0))
	Input.action_press(GameActions.ACCELERATE)
	await _frames(90)
	_check(_car.global_position.z > -70.0, "стена не пропускает машину (z = %.1f)" % _car.global_position.z)
	_check(absf(_car.forward_speed) < 3.0, "упёршись в стену, машина почти стоит (скорость %.1f)" % _car.forward_speed)
	_release_all()


func _test_ramp() -> void:
	# Трамплин стоит на z = -50 и поднимается к -Z.
	await _place(Vector3(0.0, 0.05, -25.0))
	Input.action_press(GameActions.ACCELERATE)
	var max_height := 0.0
	for i in 150:
		await physics_frame
		max_height = maxf(max_height, _car.global_position.y)
	_check(max_height > 1.0, "машина заезжает на трамплин (макс. высота %.2f)" % max_height)
	_release_all()
	await _frames(60)
	_check(_car.is_on_floor(), "после трамплина машина снова на земле")


func _test_one_shot_buttons() -> void:
	await _place(TEST_SPOT)
	_parry_count = 0
	_item_count = 0
	Input.action_press(GameActions.PARRY)
	Input.action_press(GameActions.USE_ITEM)
	await _frames(10)
	_release_all()
	await _frames(2)
	_check(_parry_count == 1, "удержание парирования = одно нажатие (%d)" % _parry_count)
	_check(_item_count == 1, "удержание кнопки предмета = одно нажатие (%d)" % _item_count)


func _test_touch_button() -> void:
	var touch := _level.get_node("TouchControls") as CanvasLayer
	touch.visible = true
	await _frames(2)
	var button := touch.get_node("RightPad/Accelerate") as TouchScreenButton
	var center := button.get_global_transform_with_canvas() * (button.texture_normal.get_size() * 0.5)
	# Событие подаётся сразу в координатах вьюпорта: в headless окно крошечное,
	# и экранные координаты не совпадают с координатами кнопок.
	var press := InputEventScreenTouch.new()
	press.index = 0
	press.position = center
	press.pressed = true
	root.push_input(press, true)
	await _frames(3)
	_check(Input.is_action_pressed(GameActions.ACCELERATE), "сенсорная кнопка ГАЗ включает действие accelerate")
	var release := InputEventScreenTouch.new()
	release.index = 0
	release.position = center
	release.pressed = false
	root.push_input(release, true)
	await _frames(3)
	_check(not Input.is_action_pressed(GameActions.ACCELERATE), "отпускание сенсорной кнопки отпускает действие")
	touch.visible = false


func _test_respawn() -> void:
	await _place(Vector3(0.0, -40.0, 0.0))
	await _frames(2)
	_check(_car.global_position.y > -1.0, "упавшая машина возвращается на старт")


func _test_parry() -> void:
	var hazard := _level.get_node("Props/BarrierParry") as ParryHazard
	_check(CarParry.of(_car) != null, "у машины есть компонент парирования")
	var result := {"hit": 0, "parried": 0}
	hazard.car_hit.connect(func(_car_hit: CarController) -> void: result["hit"] += 1)
	hazard.car_parried.connect(func(_car_parried: CarController) -> void: result["parried"] += 1)

	# 1. Без парирования: полная остановка, потом ограждение можно проехать насквозь.
	await _place(PARRY_START)
	Input.action_press(GameActions.ACCELERATE)
	var stopped := false
	for i in 200:
		await physics_frame
		if result["hit"] > 0 and not stopped:
			stopped = absf(_car.forward_speed) < 0.5
	_check(result["hit"] == 1 and result["parried"] == 0 and stopped,
			"без парирования — удар и полная остановка (ударов %d)" % result["hit"])
	_check(_car.global_position.z < -5.0, "после остановки ограждение проезжается насквозь (z = %.1f)" % _car.global_position.z)
	_release_all()

	# 2. Нажал за 0.2 с до касания: проезд без потери скорости.
	result["hit"] = 0
	result["parried"] = 0
	var min_speed := await _drive_into_barrier_pressing_parry_before(0.2)
	_check(result["parried"] == 1 and result["hit"] == 0,
			"парирование за 0.2 с до касания — проезд сквозь (парировано %d, ударов %d)" % [result["parried"], result["hit"]])
	_check(min_speed > 20.0, "при парировании скорость не теряется (мин. %.1f м/с)" % min_speed)

	# 3. Нажал за 0.8 с до касания: окно (0.4 с) уже закрылось — удар.
	result["hit"] = 0
	result["parried"] = 0
	await _drive_into_barrier_pressing_parry_before(0.8)
	_check(result["hit"] == 1 and result["parried"] == 0, "окно парирования истекло — удар (ударов %d)" % result["hit"])


## Разгон к ограждению, нажатие парирования за lead секунд до касания.
## Возвращает минимальную скорость после нажатия.
func _drive_into_barrier_pressing_parry_before(lead: float) -> float:
	await _place(PARRY_START)
	Input.action_press(GameActions.ACCELERATE)
	var pressed := false
	var min_speed := INF
	for i in 200:
		await physics_frame
		var gap := _car.global_position.z - CAR_NOSE - BARRIER_FRONT_Z
		if not pressed and gap < _car.forward_speed * lead:
			Input.action_press(GameActions.PARRY)
			pressed = true
		if pressed:
			min_speed = minf(min_speed, _car.forward_speed)
		if _car.global_position.z < -6.0:
			break
	_release_all()
	return min_speed


func _take_screenshot_if_requested() -> void:
	var path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshot="):
			path = arg.trim_prefix("--screenshot=")
	if path.is_empty() or DisplayServer.get_name() == "headless":
		return
	# Сцена «в движении»: разгон по прямой к препятствиям (удобно сравнивать с оригиналом).
	_car.respawn()
	(_level.get_node("TopDownCamera") as TopDownCamera).snap_to_target()
	Input.action_press(GameActions.ACCELERATE)
	await _frames(45)
	(_level.get_node("TouchControls") as CanvasLayer).visible = true
	await RenderingServer.frame_post_draw
	var err := root.get_texture().get_image().save_png(path)
	_check(err == OK, "скриншот сохранён в %s" % path)
	_release_all()


func _place(position: Vector3) -> void:
	_release_all()
	_car.teleport(Transform3D(Basis.IDENTITY, position))
	await _frames(3)


func _release_all() -> void:
	for action in [GameActions.ACCELERATE, GameActions.BRAKE, GameActions.STEER_LEFT,
			GameActions.STEER_RIGHT, GameActions.DRIFT, GameActions.PARRY, GameActions.USE_ITEM]:
		Input.action_release(action)


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _check(condition: bool, description: String) -> void:
	print("[%s] %s" % ["OK" if condition else "FAIL", description])
	if not condition:
		_failures.append(description)
