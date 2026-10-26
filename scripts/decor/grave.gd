@tool
extends Node3D
## Надгробие «Хэллоуина» (декор): чуть покосившееся — наклон и поворот от места, чтобы
## кладбище не стояло по линейке.


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(roundi(global_position.x * 3.0), roundi(global_position.z * 3.0)))
	rotation.x = deg_to_rad(rng.randf_range(-6.0, 6.0))
	rotation.z = deg_to_rad(rng.randf_range(-8.0, 8.0))
	rotation.y += deg_to_rad(rng.randf_range(-12.0, 12.0))
