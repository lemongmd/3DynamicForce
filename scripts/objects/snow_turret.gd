class_name SnowTurret
extends StaticBody3D
## Снежная турель оригинала (SnowTurret, Снежная): твёрдая коробка 2×2×3 м
## (16×16 px, высота 24 px), каждые 0.5 с выпускает снежок (Snowball) по своей оси +X
## (угол объекта в оригинале). Все турели стреляют одновременно (общий таймер Time).

const INTERVAL := 0.5

@export var snowball_scene: PackedScene

var _time: float = 0.0


func _physics_process(delta: float) -> void:
	_time -= delta
	if _time > 0.0:
		return
	_time += INTERVAL
	if snowball_scene == null:
		return
	# Снежок — дочерний узел турели, но в мировых координатах (top_level): в узле Props
	# трассы он мешал бы проверкам карты и автопилоту.
	var ball := snowball_scene.instantiate() as Node3D
	ball.top_level = true
	add_child(ball)
	ball.global_transform = Transform3D(Basis(Vector3.UP, global_rotation.y), global_position)
