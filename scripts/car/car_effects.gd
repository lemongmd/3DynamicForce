class_name CarEffects
extends Node
## Стек эффектов машины с таймерами (этап 4).
##
## В оригинале эффект предмета — пара действий поведения Car: «параметр ×k»,
## пауза, «параметр ÷k» (Nitro: max-speed ×1.5 и acceleration ×4 на 1 с).
## Здесь каждое такое наложение — запись CarEffect со своим таймером; множители
## всех записей перемножаются. Поэтому два одинаковых эффекта подряд
## складываются (×1.5 · ×1.5), как и в оригинале, а снимается каждый в свой срок.
##
## Узел «Effects», дочерний у CarController. Он единственный пишет поля
## *_multiplier машины; объекты трасс (лёд и т.п.) тоже ставят сюда эффекты
## (с duration = INF и снимают их через remove).

signal effect_added(effect: CarEffect)
signal effect_removed(effect: CarEffect)

const NODE_NAME := ^"Effects"
const TIME_EPSILON := 1e-4
## Параметр эффекта -> поле множителя в CarController.
const FIELDS := {
	&"max_speed": &"max_speed_multiplier",
	&"acceleration": &"acceleration_multiplier",
	&"deceleration": &"deceleration_multiplier",
	&"steering": &"steering_multiplier",
	&"drift_recover": &"drift_recover_multiplier",
	&"wall_friction": &"wall_friction_multiplier",
}

var _car: CarController
var _effects: Array[CarEffect] = []


func _ready() -> void:
	_car = get_parent() as CarController
	if _car == null:
		push_warning("CarEffects: родитель не CarController, эффекты отключены.")
		return
	# Раньше машины: множители и толчки этого кадра уже действуют в её _physics_process.
	process_physics_priority = _car.process_physics_priority - 1


## Компонент эффектов машины (или null).
static func of(car: Node) -> CarEffects:
	return car.get_node_or_null(NODE_NAME) as CarEffects


## Наложить эффект на seconds секунд. multipliers — {параметр: множитель}, см. FIELDS.
func add(id: StringName, seconds: float, multipliers: Dictionary = {}, forward_push: float = 0.0) -> CarEffect:
	for key in multipliers:
		if not FIELDS.has(key):
			push_warning("CarEffects: неизвестный параметр «%s» у эффекта %s" % [key, id])
	var effect := CarEffect.new(id, seconds, multipliers, forward_push)
	_effects.append(effect)
	_apply()
	effect_added.emit(effect)
	return effect


## Снять запись досрочно.
func remove(effect: CarEffect) -> void:
	var index := _effects.find(effect)
	if index < 0:
		return
	_effects.remove_at(index)
	_apply()
	effect_removed.emit(effect)


## Снять все эффекты (перезапуск гонки).
func clear() -> void:
	while not _effects.is_empty():
		remove(_effects.back())


func has_effect(id: StringName) -> bool:
	return _effects.any(func(e: CarEffect) -> bool: return e.id == id)


## Активные записи (только читать).
func get_effects() -> Array[CarEffect]:
	return _effects


## Итоговый множитель параметра по всем записям.
func get_multiplier(key: StringName) -> float:
	var result := 1.0
	for effect in _effects:
		result *= float(effect.multipliers.get(key, 1.0))
	return result


func _physics_process(delta: float) -> void:
	if _car == null:
		return
	# Сначала действие этого кадра (эффект на 1/3 с толкает ровно 20 кадров при 60 Гц),
	# потом отсчёт времени.
	for effect in _effects:
		if effect.forward_push != 0.0:
			_car.add_push(_car.get_flat_forward() * effect.forward_push)
	var expired: Array[CarEffect] = []
	for effect in _effects:
		effect.time_left -= delta
		# Допуск на округление: 1/3 с при 60 Гц — ровно 20 кадров, а не 21.
		if effect.time_left <= TIME_EPSILON:
			expired.append(effect)
	for effect in expired:
		remove(effect)


func _apply() -> void:
	if _car == null:
		return
	for key in FIELDS:
		_car.set(FIELDS[key], get_multiplier(key))
