class_name CarSfx
extends Node
## Звуки событий машины (из звуков оригинала) для наших механик:
## заряд дрифта, ускорение после дрифта, прыжок с трамплина, приземление.
## Узел — дочерний у CarController.

## Новая стадия заряда дрифта 1, 2, 3 (свои звуки: «тук» + треск искр, build_sounds.gd).
@export var drift_charged_sounds: Array[AudioStream] = []
@export var drift_boost_sound: AudioStream
@export var jump_sound: AudioStream
@export var land_sound: AudioStream
## Приземление тише этой вертикальной скорости не озвучивается (мелкие кочки), м/с.
@export var land_min_fall_speed: float = 4.0

var _car: CarController
var _fall_speed: float = 0.0


func _ready() -> void:
	_car = get_parent() as CarController
	if _car == null:
		return
	_car.drift_charged.connect(_on_drift_charged)
	_car.drift_boosted.connect(func() -> void: Sfx.play(_car, drift_boost_sound))
	_car.jumped.connect(func() -> void: Sfx.play(_car, jump_sound))
	_car.landed.connect(_on_landed)


func _physics_process(_delta: float) -> void:
	if _car != null and not _car.is_on_floor():
		_fall_speed = -_car.velocity.y


## Своя стадия — свой звук, выше стадия — ярче и чуть громче.
func _on_drift_charged(stage: int) -> void:
	if drift_charged_sounds.is_empty():
		return
	var index := clampi(stage - 1, 0, drift_charged_sounds.size() - 1)
	Sfx.play(_car, drift_charged_sounds[index], -4.0 + 1.5 * stage)


func _on_landed() -> void:
	if _fall_speed >= land_min_fall_speed:
		Sfx.play(_car, land_sound)
	_fall_speed = 0.0
