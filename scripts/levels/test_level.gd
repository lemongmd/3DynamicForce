extends Node3D
## Тестовая площадка этапа 1: машина, камера, препятствия, отладочный ввод.

@export var car: CarController
@export var camera: TopDownCamera


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(GameActions.DEBUG_RESET):
		car.respawn()
		camera.snap_to_target()
		get_viewport().set_input_as_handled()
