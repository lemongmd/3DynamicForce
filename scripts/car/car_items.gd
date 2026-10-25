class_name CarItems
extends Node
## Слот предмета машины (CurItem оригинала): один предмет, взятый из коробки.
##
## Как в оригинале: новая коробка заменяет предмет в слоте; кнопка предмета
## (Q) применяет его и очищает слот. Узел «Items», дочерний у CarController;
## применяет предмет по сигналу машины item_requested. Предмет с зарядом (charge_time > 0,
## помидор): нажатие начинает заряд, пока кнопка зажата — сила растёт, отпустил — бросок.

## Предмет в слоте сменился (null — слот опустел).
signal item_changed(item: Item)
## Предмет применён (звуки уже запущены, эффект наложен).
signal item_used(item: Item)

const NODE_NAME := ^"Items"

## Предмет в слоте (null — пусто).
var current: Item

var _car: CarController
## Сколько держат кнопку заряжаемого предмета, с (< 0 — заряда нет).
var _charge: float = -1.0


func _ready() -> void:
	_car = get_parent() as CarController
	if _car == null:
		push_warning("CarItems: родитель не CarController, предметы отключены.")
		return
	_car.item_requested.connect(use_item)


## Компонент предметов машины (или null).
static func of(car: Node) -> CarItems:
	return car.get_node_or_null(NODE_NAME) as CarItems


## Положить предмет в слот (из коробки); прежний пропадает.
func give(item: Item) -> void:
	current = item
	item_changed.emit(item)
	if item != null and _car != null:
		_car.emote(&"item", 0.6)


## Применить предмет из слота (заряжаемый — начать заряд). false — слот пуст.
func use_item() -> bool:
	if current == null or _car == null:
		return false
	if current.charge_time > 0.0:
		if _charge < 0.0:
			_charge = 0.0
		return true
	return _use(current, 1.0)


## Заряд броска: доля 0..1 (< 0 — не заряжаем). Для полоски в HUD.
func get_charge() -> float:
	if _charge < 0.0 or current == null or current.charge_time <= 0.0:
		return -1.0
	return clampf(_charge / current.charge_time, 0.0, 1.0)


func _physics_process(delta: float) -> void:
	if _charge < 0.0 or _car == null:
		return
	if current == null:
		_charge = -1.0
		return
	if _car.current_input.item_held:
		_charge += delta
		return
	var power := get_charge()
	_charge = -1.0
	_use(current, power)


func _use(item: Item, power: float) -> bool:
	current = null
	item_changed.emit(null)
	for sound in item.use_sounds:
		Sfx.play(_car, sound)
	# Цель автонаводки (помидор) выбирает хозяин; в сети она уходит всем вместе с предметом.
	var target := item.pick_target(_car)
	item.use_at(_car, power, target)
	# Сеть: остальные повторят предмет у себя (объекты на трассе, вспышка) с той же силой и целью.
	Network.session().item_used(item, power, target)
	if item.use_emote != &"":
		_car.emote(item.use_emote, 1.0)
	item_used.emit(item)
	return true


## Очистить слот (перезапуск гонки).
func clear() -> void:
	_charge = -1.0
	if current != null:
		current = null
		item_changed.emit(null)
