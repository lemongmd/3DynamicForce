class_name CarParry
extends Node
## Окно парирования машины — как переменная Parry в оригинале.
##
## Кнопка парирования (E) открывает окно на window_seconds (оригинал: 0.4 с).
## Пока окно открыто, повторное нажатие ничего не делает (как в оригинале).
## Гудка нет (решение автора ремейка); вместо него — волны у капота
## (эмоция CarEmoteShow оригинала).
##
## Общий механизм «опасность с окном парирования»: любая опасность
## (ограждение BarrierParry, позже бумеранг, лазер, банан, снежки…) решает исход
## через CarParry.resolve(car, …):
##   * окно открыто — машина проходит сквозь: звук и вспышка парирования;
##   * окно закрыто — машина полностью останавливается (Car.stop в оригинале)
##     и звучат звуки удара конкретной опасности.
## Узел должен называться «Parry» и быть дочерним узлом CarController.

signal window_opened
signal parried(hazard: Node)
signal hit(hazard: Node)

const NODE_NAME := ^"Parry"

## Длительность окна парирования, с (в оригинале 0.4).
@export var window_seconds: float = 0.4
@export var parry_sound: AudioStream
## Вспышка парирования (ParryFX оригинала), ставится на землю у машины.
@export var parry_fx_scene: PackedScene
## Волны у капота, пока окно открыто (CarEmoteShow оригинала).
@export var window_fx_scene: PackedScene

## Сколько ещё открыто окно, с.
var window_left: float = 0.0

var _car: CarController


func _ready() -> void:
	_car = get_parent() as CarController
	if _car == null:
		push_warning("CarParry: родитель не CarController, парирование отключено.")
		return
	_car.parry_requested.connect(_on_parry_requested)


func _physics_process(delta: float) -> void:
	window_left = maxf(window_left - delta, 0.0)


func is_window_open() -> bool:
	return window_left > 0.0


## Компонент парирования машины (или null).
static func of(car: Node) -> CarParry:
	return car.get_node_or_null(NODE_NAME) as CarParry


## Исход столкновения машины с опасностью. true — парировано (проезжает сквозь),
## false — удар: машина остановлена, звучат hit_sounds.
static func resolve(car: CarController, hazard: Node, hit_sounds: Array[AudioStream] = []) -> bool:
	var parry := of(car)
	return resolve_as(car, hazard, hit_sounds, parry != null and parry.is_window_open())


## Исход с заранее известным результатом парирования (сеть: окно проверила машина-хозяин,
## хост подтвердил). У чужой машины («марионетки») остановку делает её хозяин.
static func resolve_as(car: CarController, hazard: Node, hit_sounds: Array[AudioStream], was_parried: bool) -> bool:
	var parry := of(car)
	if was_parried:
		if parry != null:
			parry._on_parried(hazard)
		return true
	if not car.is_puppet:
		car.stop()
	if parry != null:
		parry._on_hit(hazard, hit_sounds)
	return false


func _on_parry_requested() -> void:
	if window_left > 0.0:
		return
	window_left = window_seconds
	if window_fx_scene != null:
		var fx := window_fx_scene.instantiate()
		_car.add_child(fx)
	window_opened.emit()


func _on_parried(hazard: Node) -> void:
	Sfx.play(_car, parry_sound)
	if parry_fx_scene != null and _car.get_parent() != null:
		var fx := parry_fx_scene.instantiate() as Node3D
		_car.get_parent().add_child(fx)
		# Чуть над дорогой, чтобы не мерцать с ней.
		fx.global_position = _car.global_position + Vector3.UP * 0.1
	_car.emote(&"parry", 1.0)
	parried.emit(hazard)


func _on_hit(hazard: Node, hit_sounds: Array[AudioStream]) -> void:
	for stream in hit_sounds:
		Sfx.play(_car, stream)
	_car.emote(&"angry", 1.0)
	hit.emit(hazard)
