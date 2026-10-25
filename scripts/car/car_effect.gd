class_name CarEffect
extends RefCounted
## Одна запись в стеке эффектов машины (CarEffects): множители параметров Car
## и толчок вперёд на время duration.

## Что за эффект (обычно id предмета): по нему HUD и логика узнают эффект.
var id: StringName
## Полная длительность, с (INF — пока не снимут вручную).
var duration: float = 0.0
## Сколько осталось, с.
var time_left: float = 0.0
## Параметр машины -> множитель. Ключи — CarEffects.FIELDS
## (max_speed, acceleration, deceleration, steering, drift_recover, wall_friction).
var multipliers: Dictionary = {}
## Толчок по носу машины, пока эффект действует, м/с (рывок Dash). 0 — нет.
var forward_push: float = 0.0


func _init(effect_id: StringName = &"", seconds: float = 0.0, mults: Dictionary = {}, push: float = 0.0) -> void:
	id = effect_id
	duration = seconds
	time_left = seconds
	multipliers = mults
	forward_push = push


## Доля оставшегося времени (1 — только начался, 0 — кончился).
func get_fraction() -> float:
	if duration <= 0.0 or is_inf(duration):
		return 1.0
	return clampf(time_left / duration, 0.0, 1.0)
