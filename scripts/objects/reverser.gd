class_name Reverser
extends Area3D
## Разворот оригинала (Reverser, Снежная/Шинозавод): въехал — направление машины
## отражается: RevX — меняется знак составляющей по X мира, RevY — по Z мира
## (Player.set-angle(angle(0, 0, cos·−(RevX·2−1), sin·−(RevY·2−1)))). Скорость сохраняется.
## Повторно срабатывает только после выезда (on-collision в оригинале — при касании).
## TODO(уточнить): разворачиваем и нос, и движение сразу; в оригинале (Car) движение могло
## догонять нос по drift-recover. На картах сейчас не стоит.

@export var rev_x: bool = true
@export var rev_z: bool = false
@export var sound: AudioStream

signal car_reversed(car: CarController)


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	var car := body as CarController
	if car == null or car.is_puppet:
		return
	car.reverse_heading(rev_x, rev_z)
	Sfx.play(car, sound)
	car_reversed.emit(car)
