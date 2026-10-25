class_name ItemThrow
extends Item
## Бросок с автонаводкой (наш предмет «Помидор», просьба автора оригинала): по нажатию летит
## в ближайшую машину впереди — не дальше max_distance и не больше aim_angle_deg от носа —
## и в полёте доворачивает за ней (ThrownObject.target_car). Целей нет — падает на
## blind_distance по носу. Летит дугой; на излёте сбивает машину, упав — остаётся кляксой
## на дороге. И то и другое парируется (как банан). Раньше был заряд и прицел — тестеры
## попросили автонаводку без прицела.

@export var object_scene: PackedScene
## Дальше этого цель не ищется, м.
@export var max_distance: float = 70.0
## Цель — не дальше этого угла от носа машины, °.
@export var aim_angle_deg: float = 60.0
## Дальность броска без цели, м.
@export var blind_distance: float = 30.0


## Откуда летит предмет: над машиной.
static func throw_start(car: CarController) -> Vector3:
	return car.global_position + Vector3.UP * 1.2


## Ближайшая машина впереди в секторе (не своя, не «призрак» после финиша) или null.
func pick_target(car: CarController) -> CarController:
	if not is_instance_valid(car) or not car.is_inside_tree():
		return null
	var forward := car.get_flat_forward()
	var best: CarController = null
	var best_distance := max_distance
	for node in car.get_tree().get_nodes_in_group(CarController.GROUP):
		var other := node as CarController
		if other == null or other == car or other.is_ghost:
			continue
		var to := other.global_position - car.global_position
		to.y = 0.0
		var distance := to.length()
		if distance < 1.0 or distance > best_distance:
			continue
		if rad_to_deg(forward.angle_to(to / distance)) > aim_angle_deg:
			continue
		best = other
		best_distance = distance
	return best


func use(car: CarController) -> void:
	use_at(car, 1.0, pick_target(car))


func use_at(car: CarController, _power: float, target: CarController) -> void:
	if object_scene == null or not is_instance_valid(car) or not car.is_inside_tree():
		return
	var basis := Basis.looking_at(car.get_flat_forward(), Vector3.UP)
	var thrown := ThrownObject.prepare(object_scene, blind_distance, target)
	ItemObject.spawn_prepared(thrown, car, Transform3D(basis, throw_start(car)))
