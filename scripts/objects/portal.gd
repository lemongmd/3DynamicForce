class_name Portal
extends Area3D
## Портал оригинала (Portal): въехал — звук SuperPower (−10 дБ) и машина переносится
## к парному порталу target (To = UID парного), носом по его оси −Z (Portal.Angle − 90°
## в оригинале); скорость сохраняется. Портал без пары — только выход.
## Частицы (PortalParticles) летят по оси −Z цвета портала.

const SOUND_DB := -10.0

## Выход (парный портал). Пусто — это выход, сам не переносит.
@export var target: NodePath
@export var color: Color = Color(0.2, 0.6, 1.0):
	set(value):
		color = value
		_apply_color()
@export var sound: AudioStream

## Машину перенесло (для тестов и автопилота).
signal car_warped(car: CarController)


func _ready() -> void:
	_apply_color()
	body_entered.connect(_on_body_entered)


func get_target() -> Portal:
	return get_node_or_null(target) as Portal if not target.is_empty() else null


func _on_body_entered(body: Node3D) -> void:
	var car := body as CarController
	var exit := get_target()
	if car == null or car.is_puppet or exit == null:
		return
	Sfx.play(car, sound, SOUND_DB)
	# Чуть впереди выхода, чтобы не стоять в его зоне.
	var facing := Basis(Vector3.UP, exit.global_rotation.y)
	car.warp(Transform3D(facing, exit.global_position + Vector3.UP * 0.1))
	car_warped.emit(car)


func _apply_color() -> void:
	var sprite := get_node_or_null(^"Sprite") as Sprite3D
	if sprite != null:
		sprite.modulate = color
	var particles := get_node_or_null(^"Particles") as CPUParticles3D
	if particles != null:
		particles.color = color
