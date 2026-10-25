class_name ItemSpawn
extends Item
## Предмет, который оставляет объекты на трассе (ItemObject) там, где сейчас машина,
## повёрнутые по её носу:
##   * Bullet (лазер) — 4 луча через 0.3 с (каждый — от текущего места машины);
##   * Spine (шипы) — полоса 40 м вдоль машины (по 20 м назад и вперёд);
##   * Banana, Bomb — под себя;
##   * Bumer (бумеранг) — летит вперёд и обратно;
##   * Icecream — 5 пятен льда через 0.3 с (как в оригинале).

@export var object_scene: PackedScene
## Сколько объектов и через сколько секунд друг за другом.
@export var count: int = 1
@export var interval: float = 0.0
## Сдвиг вбок по очереди: −шаг, 0, +шаг… (змейка поперёк дороги), м.
@export var lateral_step: float = 0.0


func use(car: CarController) -> void:
	for i in count:
		var side := lateral_step * float(i % 3 - 1)
		if i == 0 or interval <= 0.0:
			_spawn_one(car, side)
		else:
			car.get_tree().create_timer(i * interval, false, true).timeout.connect(_spawn_one.bind(car, side))


## car без типа: таймер может сработать, когда машины уже нет (гонка закрыта).
func _spawn_one(car, side: float = 0.0) -> void:
	if object_scene == null or not is_instance_valid(car) or not car.is_inside_tree():
		return
	var forward: Vector3 = car.get_flat_forward()
	var basis := Basis.looking_at(forward, Vector3.UP)
	var right := forward.cross(Vector3.UP).normalized()
	ItemObject.spawn(object_scene, car, Transform3D(basis, car.global_position + right * side))
