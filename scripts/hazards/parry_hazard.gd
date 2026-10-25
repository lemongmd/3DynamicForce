class_name ParryHazard
extends Area3D
## Неподвижная опасность с окном парирования (ограждение BarrierParry оригинала;
## так же устроены CrabbyParry и MapDecorWetFloorParry).
##
## Сама опасность не твёрдая: машина в неё въезжает, и в момент касания
## CarParry.resolve решает исход — окно парирования открыто: проезд сквозь,
## нет: полная остановка (дальше можно ехать сквозь, как в оригинале).
## Призраки (финишировавшие) не задеваются.

signal car_parried(car: CarController)
signal car_hit(car: CarController)

## Звуки удара, если не успел парировать (у ограждения в оригинале — StockSplat + StockPain).
@export var hit_sounds: Array[AudioStream] = []


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	var car := body as CarController
	if car == null or car.is_ghost or car.is_puppet:
		return
	if CarParry.resolve(car, self, hit_sounds):
		car_parried.emit(car)
	else:
		car_hit.emit(car)
