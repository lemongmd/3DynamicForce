class_name CarController
extends CharacterBody3D
## Аркадная машина на CharacterBody3D (VehicleBody3D не используется).
##
## Модель движения повторяет поведение Car из оригинала (Construct 3) в масштабе
## 8 px = 1 м (машина оригинала — 24 px, у нас 3 м):
##   * forward_speed — скорость со знаком (минус — задний ход);
##   * нос машины поворачивается рулём со скоростью steer-speed, которая растёт
##     со скоростью машины (в оригинале lerp(60, 120, |v|/240) °/с);
##   * направление движения догоняет нос с постоянной угловой скоростью
##     drift_recover (в оригинале 120 °/с) — отсюда встроенный занос;
##   * удар о стену оставляет долю скорости friction (в оригинале 0.45).
## Кнопка дрифта — наше дополнение (в оригинале её нет): занос сильнее,
## машина поворачивает в сторону заноса.
##
## Машина не читает Input напрямую: управление приходит из input_source
## (локальный игрок, сеть, автопилот тестов). Модель лежит в дочернем узле
## Visual и на физику не влияет.

## Нажата кнопка парирования (сам механизм — этап 3).
signal parry_requested
## Нажата кнопка предмета (система предметов — этап 4).
signal item_requested
signal drift_started(direction: int)
signal drift_ended
signal respawned
## Машина ударилась о стену (начало касания).
signal wall_hit
## Дрифт держится достаточно долго — при выходе будет ускорение.
## Занос дошёл до новой стадии заряда (1, 2, 3 — синие, оранжевые, фиолетовые искры).
signal drift_charged(stage: int)
## Ускорение после дрифта сработало.
signal drift_boosted
## Машина оторвалась от земли (трамплин) / приземлилась.
signal jumped
signal landed
## Машину перенесло (портал), скорость сохранилась.
signal warped
## Эмоция на иконке игрока в HUD (PlayerCarIcon оригинала): имя (angry, parry, item…), секунды.
signal emote_requested(emote: StringName, seconds: float)

## Пикселей оригинала в метре.
const PIXELS_PER_METER := 8.0
## Слой «world» — с ним призрак сталкивается всегда.
const WORLD_LAYER_MASK := 1
## Группа всех машин гонки (флешка показывает эмоцию «ослеп» у всех, кроме хозяина).
const GROUP := &"cars"

## Источник управления. Если не задан, машина стоит (нейтральный ввод).
@export var input_source: CarInputSource

@export_group("Скорость (как в оригинале)")
## Максимальная скорость, м/с (оригинал: 240 px/с).
@export var max_speed: float = 30.0
## Разгон, м/с² (оригинал: 128 px/с²).
@export var acceleration: float = 16.0
## Торможение, м/с² (оригинал: 320 px/с²).
@export var deceleration: float = 40.0
## Предел заднего хода — доля max_speed.
## Приближение: точное поведение Car не сверено (документация Construct закрыта для автоматического доступа).
@export_range(0.0, 1.0) var reverse_speed_ratio: float = 0.25
## Замедление накатом (газ отпущен), м/с². Приближение, см. выше.
@export var coast_deceleration: float = 10.0

@export_group("Руль (как в оригинале)")
## Скорость поворота носа на месте и на максимальной скорости, °/с. В оригинале 60 и 120,
## но автор оригинала попросил: после удара медленная машина еле разворачивалась — на малой
## скорости поворот быстрее (как в Mario Kart).
@export var steer_speed_min_deg: float = 150.0
@export var steer_speed_max_deg: float = 120.0
## Поворачивать ли на месте (в оригинале — да).
@export var turn_while_stopped: bool = true
## Доля руля в воздухе.
@export_range(0.0, 1.0) var air_control: float = 0.3

@export_group("Занос и столкновения (как в оригинале)")
## С какой угловой скоростью направление движения догоняет нос, °/с (оригинал: 120).
@export var drift_recover_deg: float = 120.0
## Доля скорости, которая остаётся после удара о стену. В оригинале 0.45 — по просьбе автора
## оригинала наказание мягче («слишком жестоко»).
@export_range(0.0, 1.0) var wall_friction: float = 0.7

@export_group("Дрифт (наше дополнение)")
## Догонялка направления в дрифте, °/с (меньше — сильнее занос). Больше — траектория
## послушнее рулю (просьба автора оригинала: «дрифт неуправляемый»).
@export var drift_mode_recover_deg: float = 100.0
## Во сколько раз сильнее поворот в дрифте (усилено после теста беты 0.10.4: «дрифт слабенький»).
@export var drift_steer_multiplier: float = 1.2
## Минимальная скорость для дрифта, м/с.
@export var drift_min_speed: float = 6.0
## Минимальное отклонение руля, чтобы войти в дрифт.
@export_range(0.0, 1.0) var drift_steer_threshold: float = 0.2
## Поворот в дрифте: руль от заноса / нейтрально / в занос (доли поворота). Широкий
## разброс — рулём можно подправлять дугу на ходу, как в Mario Kart.
@export var drift_turn_min: float = 0.3
@export var drift_turn_neutral: float = 1.0
@export var drift_turn_max: float = 1.7
## Плавный вход: за это время управление переходит от обычного к дрифтовому, с.
@export var drift_entry_time: float = 0.25
## Наибольший угол заноса (между носом и движением) в дрифте — машину не разворачивает.
@export_range(5.0, 90.0) var drift_max_slide_deg: float = 32.0
## Выход из дрифта: столько секунд направление движения догоняет нос быстро (°/с) — машину
## не несёт боком после отпускания кнопки (тестеры: «дрифт залипает после отпуска Shift»).
@export var drift_exit_time: float = 0.25
@export var drift_exit_recover_deg: float = 360.0
## Ускорение после дрифта по стадиям (как мини-турбо Mario Kart): чем дольше держишь занос,
## тем выше стадия — 1 (синие искры), 2 (оранжевые), 3 (фиолетовые). Отпустил кнопку —
## толчок (kicks, м/с) и временно повышенный предел скорости (bonus, м/с), который плавно
## спадает за durations, с. Индекс — стадия − 1.
@export var drift_stage_times: PackedFloat32Array = PackedFloat32Array([0.6, 1.2, 2.0])
@export var drift_stage_kicks: PackedFloat32Array = PackedFloat32Array([5.0, 8.0, 12.0])
@export var drift_stage_bonus: PackedFloat32Array = PackedFloat32Array([6.0, 9.0, 12.0])
@export var drift_stage_durations: PackedFloat32Array = PackedFloat32Array([0.8, 1.3, 2.0])

## Первая стадия — с какого времени заноса есть ускорение, с.
var drift_boost_min_time: float:
	get:
		return drift_stage_times[0] if not drift_stage_times.is_empty() else INF

@export_group("Прыжки (наше)")
## Доля вертикальной скорости на краю трамплина, с которой машина улетает в воздух.
@export var ramp_launch_scale: float = 1.0
## Отрыв на гребне: если машина шла в подъём быстрее этого (м/с вверх) и подъём
## резко кончился — она улетает, а не «переваливается» через край.
@export var crest_launch_min_speed: float = 2.0

@export_group("Гравитация")
@export var gravity: float = 32.0
@export var max_fall_speed: float = 50.0
## Ниже этой высоты машина возвращается на точку появления.
@export var kill_height: float = -25.0

## Множители для системы эффектов (этап 4): как set-max-speed/acceleration/… в оригинале.
var max_speed_multiplier: float = 1.0
var acceleration_multiplier: float = 1.0
var deceleration_multiplier: float = 1.0
var steering_multiplier: float = 1.0
var drift_recover_multiplier: float = 1.0
var wall_friction_multiplier: float = 1.0

## false — управление игнорируется (обратный отсчёт перед стартом и т.п.).
var controls_enabled: bool = true
## Призрак: другие машины проезжают сквозь (см. set_ghost).
var is_ghost: bool = false
## Чужая машина в сетевой игре: физику не считает, её ставит NetCarSync по присланным
## состояниям. Опасности, коробки и звуки на неё не действуют — это решает её хозяин.
var is_puppet: bool = false
## Состояние чужой машины для эффектов (приходит по сети): на земле, дрифт «заряжен», ускорение.
var puppet_grounded: bool = true
var puppet_drift_stage: int = 0
var puppet_boosting: bool = false

## Скорость вдоль направления движения, м/с. Отрицательная — задний ход.
var forward_speed: float = 0.0
var is_drifting: bool = false
## -1 — занос влево, +1 — вправо, 0 — нет дрифта.
var drift_direction: int = 0
## Управление на текущем физическом кадре. Снаружи только читать.
var current_input: CarInput = CarInput.new()

## Направление движения (единичный вектор в плоскости земли), догоняет нос.
var _move_dir: Vector3 = Vector3.FORWARD
var _touching_wall: bool = false
var _drift_time: float = 0.0
var _boost_left: float = 0.0
## Текущее ускорение после дрифта: длительность и прибавка к пределу (по стадии).
var _boost_total: float = 0.0
var _boost_bonus: float = 0.0
## Толчок от объектов трассы (ускорители, конвейеры) на текущий кадр, м/с.
var _push: Vector3 = Vector3.ZERO
## Вертикальная скорость на земле в прошлом кадре (на подъёме трамплина — больше нуля).
var _floor_vertical_speed: float = 0.0
## Сколько ещё длится быстрое выравнивание после дрифта, с.
var _exit_left: float = 0.0
var _was_on_floor: bool = true
## После отрыва с гребня машина какое-то время не «прилипает» к полу, с.
var _air_lock: float = 0.0

## Сколько после отрыва не прилипать к полу, с.
const LAUNCH_AIR_LOCK := 0.15
## Группа трамплинов: только с них машина улетает на гребне (TrackLayout.RAMP_GROUP).
const RAMP_GROUP := &"ramps"
var _spawn_transform: Transform3D
var _default_collision_layer: int = 0
var _default_collision_mask: int = 0


func _ready() -> void:
	_spawn_transform = global_transform
	_default_collision_layer = collision_layer
	_default_collision_mask = collision_mask
	_move_dir = get_flat_forward()
	add_to_group(GROUP)


func _physics_process(delta: float) -> void:
	if is_puppet:
		return
	if input_source != null:
		input_source.read_input(current_input)
	else:
		current_input.clear()
	if not controls_enabled:
		current_input.clear()

	var on_floor := is_on_floor() and _air_lock <= 0.0
	_air_lock = maxf(_air_lock - delta, 0.0)
	_update_drift_state(on_floor, delta)
	_boost_left = maxf(_boost_left - delta, 0.0)
	_exit_left = maxf(_exit_left - delta, 0.0)
	_update_speed(delta)
	_update_heading(delta, on_floor)
	_update_move_direction(delta)

	var vertical := 0.0
	if not on_floor:
		if _was_on_floor:
			# Съехал с трамплина: улетаем с той вертикальной скоростью, что была на подъёме.
			velocity.y = maxf(_floor_vertical_speed, 0.0) * ramp_launch_scale
			if _floor_vertical_speed > crest_launch_min_speed:
				jumped.emit()
		vertical = maxf(velocity.y - gravity * delta, -max_fall_speed)
	elif not _was_on_floor:
		landed.emit()
	_was_on_floor = on_floor
	var planar := _move_dir * forward_speed + _push
	_push = Vector3.ZERO
	velocity = Vector3(planar.x, vertical, planar.z)
	move_and_slide()
	_check_crest_launch()
	_resolve_wall_hits()

	if global_position.y < kill_height:
		respawn()
		return

	if current_input.parry_pressed:
		parry_requested.emit()
	if current_input.item_pressed:
		item_requested.emit()


## Текущий предел скорости с учётом эффектов и ускорения после дрифта.
func get_max_speed() -> float:
	var boost := 0.0
	if _boost_total > 0.0:
		boost = _boost_bonus * _boost_left / _boost_total
	return max_speed * max_speed_multiplier + boost


## Толкнуть машину на этот кадр (ускорители, конвейеры): v, м/с, в плоскости земли.
## Как move-forward/move-at-angle в оригинале — к скорости машины не прибавляется.
func add_push(push: Vector3) -> void:
	_push += Vector3(push.x, 0.0, push.z)


## Сразу разогнаться до предела (ускоритель MaxSpeed оригинала).
func set_speed_to_max() -> void:
	forward_speed = get_max_speed()
	_move_dir = get_flat_forward()


## Сколько продолжается дрифт, с (0 — не дрифтует).
func get_drift_time() -> float:
	if is_puppet:
		var stage := puppet_drift_stage
		return drift_stage_times[stage - 1] if is_drifting and stage > 0 else 0.0
	return _drift_time if is_drifting else 0.0


## Стадия заряда дрифта: 0 — нет, 1–3 (синие, оранжевые, фиолетовые искры).
func get_drift_stage() -> int:
	if is_puppet:
		return puppet_drift_stage if is_drifting else 0
	return _stage_for(_drift_time) if is_drifting else 0


func _stage_for(time: float) -> int:
	var stage := 0
	for i in drift_stage_times.size():
		if time >= drift_stage_times[i]:
			stage = i + 1
	return stage


## Длительность текущего ускорения после дрифта, с.
func get_boost_duration() -> float:
	return _boost_total


## Идёт ли ускорение после дрифта.
func is_boosting() -> bool:
	return puppet_boosting if is_puppet else _boost_left > 0.0


## Доля от базовой максимальной скорости (0..1, может быть больше 1 под эффектами).
func get_speed_ratio() -> float:
	return absf(forward_speed) / maxf(max_speed, 0.01)


## Скорость поворота носа (рад/с) при скорости speed — как lerp(60, 120, |v|/240) в оригинале.
func get_turn_rate(speed: float) -> float:
	var t := clampf(absf(speed) / maxf(max_speed, 0.01), 0.0, 1.0)
	return deg_to_rad(lerpf(steer_speed_min_deg, steer_speed_max_deg, t)) * steering_multiplier


## Фактическая горизонтальная скорость движения.
func get_planar_velocity() -> Vector3:
	return _move_dir * forward_speed


## Нос машины в горизонтальной плоскости.
func get_flat_forward() -> Vector3:
	var forward := -global_basis.z
	forward.y = 0.0
	return forward.normalized() if forward.length_squared() > 1e-6 else Vector3.FORWARD


## Угол заноса (радианы): между носом и направлением движения.
func get_slide_angle() -> float:
	return get_flat_forward().signed_angle_to(_move_dir, Vector3.UP)


## Мгновенная остановка (как Car.stop в оригинале).
func stop() -> void:
	forward_speed = 0.0
	_move_dir = get_flat_forward()
	_boost_left = 0.0
	_end_drift(false)


## Призрак: машина не сталкивается с другими машинами и опасностями, только с миром.
## Нужен после финиша, чтобы доехавший не мешал остальным.
func set_ghost(enabled: bool) -> void:
	is_ghost = enabled
	collision_layer = 0 if enabled else _default_collision_layer
	collision_mask = WORLD_LAYER_MASK if enabled else _default_collision_mask


## Вернуть машину на точку появления.
func respawn() -> void:
	teleport(_spawn_transform)


## Мгновенно переставить машину (без интерполяции) и обнулить скорость.
func teleport(target: Transform3D) -> void:
	global_transform = target
	velocity = Vector3.ZERO
	forward_speed = 0.0
	_move_dir = get_flat_forward()
	_touching_wall = false
	_boost_left = 0.0
	_push = Vector3.ZERO
	_was_on_floor = true
	_floor_vertical_speed = 0.0
	_air_lock = 0.0
	_end_drift(false)
	reset_physics_interpolation()
	respawned.emit()


## Точка появления (для сброса). В гонке её задаёт RaceManager (последний чекпоинт).
func set_spawn_transform(target: Transform3D) -> void:
	_spawn_transform = target


## Трамплин: пока машина едет в подъём, запоминаем вертикальную скорость; когда
## подъём резко кончился (гребень), машина улетает с ней, а не переваливается
## через край (иначе её задняя часть ещё «стоит» на кромке и прыжка нет).
func _check_crest_launch() -> void:
	if not is_on_floor() or _air_lock > 0.0:
		return
	var vertical := get_real_velocity().y
	if _floor_vertical_speed > crest_launch_min_speed and vertical < _floor_vertical_speed * 0.5:
		velocity.y = _floor_vertical_speed * ramp_launch_scale
		_floor_vertical_speed = 0.0
		_air_lock = LAUNCH_AIR_LOCK
		_was_on_floor = false
		jumped.emit()
	else:
		# Взлетаем только с трамплинов (группа ramps). С гребня холма обычной дороги машина
		# не улетает, а едет дальше по дороге: на трассах без стен (Rainbow Road друга
		# Лимона) прыжок с каждого холма уносил её за край, особенно с поворотом наверху.
		_floor_vertical_speed = vertical if _on_ramp() else 0.0


## Пол под машиной — трамплин (StaticBody3D в группе ramps).
func _on_ramp() -> bool:
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		if collision.get_normal().y < 0.5:
			continue
		var collider := collision.get_collider() as Node
		if collider != null and collider.is_in_group(RAMP_GROUP):
			return true
	return false


func _update_drift_state(on_floor: bool, delta: float) -> void:
	if is_drifting:
		var stage_before := _stage_for(_drift_time)
		_drift_time += delta
		var stage := _stage_for(_drift_time)
		if stage > stage_before:
			drift_charged.emit(stage)
		if forward_speed < drift_min_speed * 0.6:
			_end_drift(false)
		elif not current_input.drift:
			# Отпустил кнопку сам — после долгого заноса положено ускорение.
			_end_drift(true)
		return
	# Дрифт — наше дополнение (в оригинале нет): зажат дрифт + руль + скорость
	# -> занос в сторону руля; долгий занос даёт ускорение на выходе.
	if current_input.drift and on_floor and forward_speed >= drift_min_speed \
			and absf(current_input.steer) >= drift_steer_threshold:
		is_drifting = true
		_drift_time = 0.0
		drift_direction = 1 if current_input.steer > 0.0 else -1
		drift_started.emit(drift_direction)


## allow_boost — выход из дрифта отпусканием кнопки (не остановка, не телепорт).
func _end_drift(allow_boost: bool) -> void:
	if not is_drifting:
		return
	is_drifting = false
	drift_direction = 0
	_exit_left = drift_exit_time
	var stage := _stage_for(_drift_time)
	if allow_boost and stage > 0:
		_boost_total = drift_stage_durations[stage - 1]
		_boost_bonus = drift_stage_bonus[stage - 1]
		_boost_left = _boost_total
		forward_speed = minf(forward_speed + drift_stage_kicks[stage - 1], get_max_speed())
		_move_dir = get_flat_forward()
		drift_boosted.emit()
	_drift_time = 0.0
	drift_ended.emit()


func _update_speed(delta: float) -> void:
	var throttle := current_input.throttle
	var top := get_max_speed()
	var reverse_top := top * reverse_speed_ratio
	if throttle > 0.01:
		if forward_speed < 0.0:
			forward_speed = move_toward(forward_speed, 0.0, deceleration * deceleration_multiplier * delta)
		else:
			forward_speed += acceleration * acceleration_multiplier * throttle * delta
	elif throttle < -0.01:
		# Тормоз, потом задний ход — с темпом торможения.
		forward_speed -= deceleration * deceleration_multiplier * -throttle * delta
	else:
		forward_speed = move_toward(forward_speed, 0.0, coast_deceleration * delta)
	# Как set-max-speed в оригинале: предел действует сразу (бомба режет скорость мгновенно).
	forward_speed = clampf(forward_speed, -reverse_top, top)


func _update_heading(delta: float, on_floor: bool) -> void:
	if forward_speed == 0.0 and not turn_while_stopped:
		return
	# amount > 0 — поворот вправо. Задним ходом руль работает как у настоящей машины.
	var amount := current_input.steer * (-1.0 if forward_speed < 0.0 else 1.0)
	if is_drifting:
		# В дрифте машина всегда поворачивает в сторону заноса;
		# руль «в занос» закручивает сильнее, «от заноса» — расширяет дугу.
		var along := current_input.steer * drift_direction
		var k := drift_turn_neutral
		if along > 0.0:
			k = lerpf(drift_turn_neutral, drift_turn_max, along)
		else:
			k = lerpf(drift_turn_neutral, drift_turn_min, -along)
		amount = lerpf(amount, drift_direction * k * drift_steer_multiplier, _drift_blend())
	var yaw_rate := -amount * get_turn_rate(forward_speed)
	if not on_floor:
		yaw_rate *= air_control
	rotate_y(yaw_rate * delta)


## Направление движения догоняет нос с постоянной угловой скоростью (drift recover).
func _update_move_direction(delta: float) -> void:
	var forward := get_flat_forward()
	var recover_deg := drift_recover_deg
	if is_drifting:
		recover_deg = lerpf(drift_recover_deg, drift_mode_recover_deg, _drift_blend())
	elif _exit_left > 0.0:
		recover_deg = maxf(recover_deg, drift_exit_recover_deg)
	var max_turn := deg_to_rad(recover_deg) * drift_recover_multiplier * delta
	var angle := _move_dir.signed_angle_to(forward, Vector3.UP)
	_move_dir = _move_dir.rotated(Vector3.UP, clampf(angle, -max_turn, max_turn)).normalized()
	if is_drifting:
		# Занос не больше drift_max_slide_deg: дрифт не превращается в разворот.
		var slide := _move_dir.signed_angle_to(forward, Vector3.UP)
		var limit := deg_to_rad(drift_max_slide_deg)
		if absf(slide) > limit:
			_move_dir = forward.rotated(Vector3.UP, -signf(slide) * limit).normalized()


## Доля дрифтового управления: плавно растёт от 0 до 1 за drift_entry_time после входа.
func _drift_blend() -> float:
	if drift_entry_time <= 0.0:
		return 1.0
	return clampf(_drift_time / drift_entry_time, 0.0, 1.0)


## Стена: в момент удара остаётся доля скорости wall_friction, дальше машина
## скользит вдоль стены (направление движения — вдоль неё, скорость — не больше
## фактической).
func _resolve_wall_hits() -> void:
	if not is_on_wall():
		_touching_wall = false
		return
	if not _touching_wall:
		_touching_wall = true
		forward_speed *= clampf(wall_friction * wall_friction_multiplier, 0.0, 1.0)
		wall_hit.emit()
	var real := get_real_velocity()
	real.y = 0.0
	var real_speed := real.length()
	if real_speed > 0.1:
		_move_dir = real / real_speed * (1.0 if forward_speed >= 0.0 else -1.0)
	forward_speed = signf(forward_speed) * minf(absf(forward_speed), real_speed)


## Показать эмоцию на иконке игрока (как IconEmote оригинала).
func emote(emote_name: StringName, seconds: float) -> void:
	emote_requested.emit(emote_name, seconds)


## На земле (у чужой машины — по присланному состоянию).
func is_grounded() -> bool:
	return puppet_grounded if is_puppet else is_on_floor()


## Флаги сетевого состояния машины (NetCarSync).
const NET_DRIFTING := 1
const NET_DRIFT_CHARGED := 2
const NET_BOOSTING := 4
const NET_GROUNDED := 8
const NET_GHOST := 16
## Стадия заряда дрифта (0–3) — в битах 5–6 флагов.
const NET_DRIFT_STAGE_SHIFT := 5


## Состояние своей машины для отправки по сети:
## [позиция, поворот, скорость, направление движения (угол), вертикальная скорость, руль, флаги].
func get_net_state() -> Array:
	var flags := 0
	if is_drifting:
		flags |= NET_DRIFTING
		var stage := _stage_for(_drift_time)
		if stage > 0:
			flags |= NET_DRIFT_CHARGED | (stage << NET_DRIFT_STAGE_SHIFT)
	if is_boosting() or forward_speed > max_speed + 0.5:
		flags |= NET_BOOSTING
	if is_on_floor():
		flags |= NET_GROUNDED
	if is_ghost:
		flags |= NET_GHOST
	return [global_position, global_rotation.y, forward_speed, atan2(-_move_dir.x, -_move_dir.z),
			velocity.y, current_input.steer, flags]


## Применить присланное состояние к чужой машине (кроме положения — его ставит NetCarSync).
func apply_puppet_state(speed: float, move_yaw: float, vertical_speed: float, steer: float, flags: int) -> void:
	forward_speed = speed
	_move_dir = Vector3(-sin(move_yaw), 0.0, -cos(move_yaw))
	velocity = _move_dir * speed + Vector3.UP * vertical_speed
	current_input.steer = steer
	is_drifting = flags & NET_DRIFTING != 0
	drift_direction = (1 if steer >= 0.0 else -1) if is_drifting else 0
	puppet_drift_stage = (flags >> NET_DRIFT_STAGE_SHIFT) & 3
	puppet_boosting = flags & NET_BOOSTING != 0
	var grounded := flags & NET_GROUNDED != 0
	if grounded and not puppet_grounded:
		landed.emit()
	puppet_grounded = grounded
	var ghost := flags & NET_GHOST != 0
	if ghost != is_ghost:
		set_ghost(ghost)


## Перенести машину в target, сохранив скорость (портал): движение — по новому носу.
func warp(target: Transform3D) -> void:
	global_transform = target
	_move_dir = get_flat_forward()
	_end_drift(false)
	reset_physics_interpolation()
	warped.emit()


## Отразить направление (Reverser оригинала): flip_x / flip_z — поменять знак составляющей
## направления по оси X / Z мира (RevX / RevY оригинала).
func reverse_heading(flip_x: bool, flip_z: bool) -> void:
	var forward := get_flat_forward()
	var flipped := Vector3(-forward.x if flip_x else forward.x, 0.0, -forward.z if flip_z else forward.z)
	if flipped.length_squared() < 1e-6:
		return
	global_rotation.y = atan2(-flipped.x, -flipped.z)
	_move_dir = Vector3(-_move_dir.x if flip_x else _move_dir.x, 0.0, -_move_dir.z if flip_z else _move_dir.z)
	_end_drift(false)
