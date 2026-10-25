class_name ParryFx
extends Sprite3D
## Вспышка парирования (ParryFX оригинала): лежит на земле под машиной,
## крутится (Rotate) и тает (Fade), затем удаляется.

## Скорость вращения, °/с.
@export var spin_deg: float = 360.0
## Время жизни, с.
@export var lifetime: float = 0.5

var _age: float = 0.0


func _ready() -> void:
	rotation.y = randf() * TAU


func _process(delta: float) -> void:
	_age += delta
	rotate_y(deg_to_rad(spin_deg) * delta)
	modulate.a = clampf(1.0 - _age / lifetime, 0.0, 1.0)
	if _age >= lifetime:
		queue_free()
