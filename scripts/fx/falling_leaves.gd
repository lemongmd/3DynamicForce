extends CPUParticles3D
## Падающие осенние листья вокруг камеры («Хэллоуин»): источник частиц каждый кадр — над
## точкой, куда смотрит камера; листья — в мире (local_coords выключен), кружатся и сносятся
## ветром. Только в игре (в редакторе стоит на месте).

## Высота над землёй и сдвиг вперёд от камеры, м.
const HEIGHT := 9.0
const AHEAD := 10.0


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var forward := -camera.global_basis.z
	forward.y = 0.0
	if forward.length_squared() > 0.0001:
		forward = forward.normalized()
	var ground := camera.global_position + forward * AHEAD
	global_position = Vector3(ground.x, camera.global_position.y - 12.0 + HEIGHT, ground.z)
