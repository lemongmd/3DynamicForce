class_name CarInput
extends RefCounted
## Снимок управления машиной за один физический кадр.
##
## Машина знает только об этом объекте и не знает, откуда пришло управление:
## клавиатура, геймпад, сенсорные кнопки, бот или сеть.

## -1 — полностью влево, +1 — полностью вправо.
var steer: float = 0.0
## -1 — тормоз / задний ход, +1 — полный газ.
var throttle: float = 0.0
## Кнопка дрифта зажата.
var drift: bool = false
## Кнопка парирования нажата именно в этом кадре.
var parry_pressed: bool = false
## Кнопка предмета нажата именно в этом кадре.
var item_pressed: bool = false
## Кнопка предмета зажата (заряд броска).
var item_held: bool = false


func clear() -> void:
	steer = 0.0
	throttle = 0.0
	drift = false
	parry_pressed = false
	item_pressed = false
	item_held = false


func copy_from(other: CarInput) -> void:
	steer = other.steer
	throttle = other.throttle
	drift = other.drift
	parry_pressed = other.parry_pressed
	item_pressed = other.item_pressed
	item_held = other.item_held
