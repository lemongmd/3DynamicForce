class_name NetCarSync
extends Node
## Чужая машина в сетевой игре (узел «NetSync» у машины-«марионетки», is_puppet = true).
##
## Плавность (главное требование автора ремейка):
##   * хозяин шлёт состояние ~30 раз в секунду с отметкой своего времени;
##   * здесь — буфер снимков и показ «в прошлом» на INTERP_DELAY (100 мс): машина плавно
##     едет между двумя настоящими снимками, даже если пакеты приходят неровно;
##   * снимки кончились (потеря пакетов) — экстраполяция по скорости, не дольше
##     MAX_EXTRAPOLATION, потом машина стоит на последнем месте;
##   * расхождение после экстраполяции убирается мягкой подтяжкой, а не рывком;
##   * телепорт (решётка, возврат на чекпоинт) и большие расхождения — мгновенно.
## Часы хозяина и наши не совпадают: смещение оценивается по самым «быстрым» пакетам
## и медленно подстраивается (дрейф часов, колебания задержки).

const NODE_NAME := ^"NetSync"
## Показываем чужую машину с таким запаздыванием, с (буфер на 3 пакета при 30 Гц).
const INTERP_DELAY := 0.1
## Дольше этого без новых пакетов не угадываем, с.
const MAX_EXTRAPOLATION := 0.25
## Больше этого расхождения — ставим сразу (телепорт), м.
const SNAP_DISTANCE := 6.0
## Меньше этого расхождения — без подтяжки, м.
const SMOOTH_DISTANCE := 0.3
## Резкость подтяжки, 1/с.
const SMOOTH_SHARPNESS := 15.0
const BUFFER_SIZE := 32

var _car: CarController
var _snapshots: Array[Dictionary] = []
## Время хозяина минус наше время, с (NAN — ещё не знаем).
var _clock_offset: float = NAN
var _snap_next: bool = true


func _ready() -> void:
	_car = get_parent() as CarController
	# Раньше машины и эффектов: в этом кадре они видят уже новое положение.
	if _car != null:
		process_physics_priority = _car.process_physics_priority - 2


## Компонент синхронизации машины (или null).
static func of(car: Node) -> NetCarSync:
	return car.get_node_or_null(NODE_NAME) as NetCarSync


static func now() -> float:
	return Time.get_ticks_usec() / 1000000.0


## Новый снимок от хозяина. sender_time — его часы, state — CarController.get_net_state(),
## teleport — машина переставлена (не сглаживать).
func push(sender_time: float, state: Array, teleport: bool) -> void:
	var offset := sender_time - now()
	if is_nan(_clock_offset) or offset > _clock_offset:
		# Пакет пришёл быстрее прежних — ближе к настоящему смещению.
		_clock_offset = offset
	else:
		# Медленно «отпускаем» оценку: часы дрейфуют, задержка меняется.
		_clock_offset = lerpf(_clock_offset, offset, 0.01)
	if not _snapshots.is_empty() and sender_time <= float(_snapshots.back()["t"]):
		return
	if teleport:
		_snapshots.clear()
		_snap_next = true
	_snapshots.append({"t": sender_time, "pos": state[0], "yaw": state[1], "speed": state[2],
			"move_yaw": state[3], "vy": state[4], "steer": state[5], "flags": state[6]})
	while _snapshots.size() > BUFFER_SIZE:
		_snapshots.pop_front()


## Есть ли данные о машине.
func has_data() -> bool:
	return not _snapshots.is_empty()


func _physics_process(delta: float) -> void:
	if _car == null or _snapshots.is_empty():
		return
	var render_time := now() + _clock_offset - INTERP_DELAY
	var sample := _sample(render_time)
	var target: Vector3 = sample["pos"]
	var error := target - _car.global_position
	if _snap_next or error.length() > SNAP_DISTANCE:
		_car.global_position = target
		_car.reset_physics_interpolation()
		_snap_next = false
	elif error.length() < SMOOTH_DISTANCE:
		_car.global_position = target
	else:
		_car.global_position += error * (1.0 - exp(-SMOOTH_SHARPNESS * delta))
	_car.global_rotation = Vector3(0.0, float(sample["yaw"]), 0.0)
	var last: Dictionary = _snapshots.back()
	_car.apply_puppet_state(float(sample["speed"]), float(sample["move_yaw"]), float(sample["vy"]),
			float(sample["steer"]), int(last["flags"]))


## Положение и угол на момент time: между снимками — интерполяция, после последнего —
## экстраполяция по скорости (не дольше MAX_EXTRAPOLATION).
func _sample(time: float) -> Dictionary:
	var first: Dictionary = _snapshots[0]
	if time <= float(first["t"]):
		return first
	for i in range(_snapshots.size() - 1):
		var a: Dictionary = _snapshots[i]
		var b: Dictionary = _snapshots[i + 1]
		if time < float(b["t"]):
			var k := (time - float(a["t"])) / maxf(float(b["t"]) - float(a["t"]), 1e-4)
			return {
				"pos": (a["pos"] as Vector3).lerp(b["pos"], k),
				"yaw": lerp_angle(float(a["yaw"]), float(b["yaw"]), k),
				"speed": lerpf(float(a["speed"]), float(b["speed"]), k),
				"move_yaw": lerp_angle(float(a["move_yaw"]), float(b["move_yaw"]), k),
				"vy": lerpf(float(a["vy"]), float(b["vy"]), k),
				"steer": lerpf(float(a["steer"]), float(b["steer"]), k),
			}
	var last: Dictionary = _snapshots.back()
	var ahead := minf(time - float(last["t"]), MAX_EXTRAPOLATION)
	var move_yaw := float(last["move_yaw"])
	var dir := Vector3(-sin(move_yaw), 0.0, -cos(move_yaw))
	var result := last.duplicate()
	result["pos"] = (last["pos"] as Vector3) + dir * float(last["speed"]) * ahead
	return result
