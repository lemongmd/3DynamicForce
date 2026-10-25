class_name ThrownObject
extends ItemObject
## Брошенный предмет (наш «Помидор», ItemThrow): летит дугой; есть цель (target_car) — падает
## туда, где она сейчас (доворачивает в полёте, автонаводка), нет — на throw_distance по носу.
## На излёте (ниже HIT_HEIGHT над землёй) задевает машины, упав — брызги и клякса на дороге
## (вид Visual вместо летящего Ball). Попадание парируется, как банан (ItemObject).

## Скорость полёта по горизонтали, м/с, и высота дуги на метр дальности.
const FLIGHT_SPEED := 32.0
const ARC_PER_METER := 0.12
const ARC_MIN := 2.0
## Задевает машины, только когда ниже этого над землёй, м.
const HIT_HEIGHT := 2.2
const LAND_SOUND := preload("res://assets/original/sounds/stocksplat.wav")

## Дальность броска без цели, м (ставит ItemThrow через prepare).
var throw_distance: float = 30.0
## Цель автонаводки (или null).
var target_car: CarController

var _ball: Node3D
var _landed: bool = false
var _start: Vector3
var _land_point: Vector3
var _height: float = ARC_MIN


## Экземпляр сцены с дальностью броска и целью (до ItemObject.spawn_prepared).
static func prepare(scene: PackedScene, distance: float, target: CarController = null) -> ThrownObject:
	var thrown := scene.instantiate() as ThrownObject
	thrown.throw_distance = distance
	thrown.target_car = target
	return thrown


func _on_spawned() -> void:
	super._on_spawned()
	_ball = get_node_or_null(^"Ball") as Node3D
	if _visual != null:
		_visual.visible = false
	set_deferred(&"monitoring", false)
	_start = global_position
	var forward := -global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	_land_point = find_landing(get_world_3d().direct_space_state, _start, forward, throw_distance)
	if _has_target():
		_land_point = target_car.global_position
	var distance := Vector2(_land_point.x - _start.x, _land_point.z - _start.z).length()
	_height = arc_height(distance)
	var tween := create_tween()
	tween.tween_method(_fly, 0.0, 1.0, distance / FLIGHT_SPEED + 0.2)
	tween.tween_callback(_land)


func _has_target() -> bool:
	return is_instance_valid(target_car) and target_car.is_inside_tree() and not target_car.is_ghost


## Куда упадёт брошенное из start по forward на distance: земля под точкой (дорога, трамплин);
## мимо всего — на высоту машины.
static func find_landing(space: PhysicsDirectSpaceState3D, start: Vector3, forward: Vector3, distance: float) -> Vector3:
	var target := start + forward * distance
	var land := Vector3(target.x, start.y - 1.2, target.z)
	var query := PhysicsRayQueryParameters3D.create(target + Vector3.UP * 6.0, target + Vector3.DOWN * 30.0, WORLD_MASK)
	var hit := space.intersect_ray(query)
	if not hit.is_empty():
		land = hit["position"]
	return land


## Высота дуги полёта на дальность distance, м.
static func arc_height(distance: float) -> float:
	return maxf(ARC_MIN, distance * ARC_PER_METER)


## Точка дуги в доле полёта t 0..1.
static func arc_point(start: Vector3, land: Vector3, height: float, t: float) -> Vector3:
	return start.lerp(land, t) + Vector3.UP * height * 4.0 * t * (1.0 - t)


func _fly(t: float) -> void:
	# Автонаводка: точка падения едет за целью.
	if _has_target():
		_land_point = target_car.global_position
	var arc := _height * 4.0 * t * (1.0 - t)
	global_position = arc_point(_start, _land_point, _height, t)
	if _ball != null:
		_ball.rotation.x -= 0.25
	set_deferred(&"monitoring", arc + (_start.y - _land_point.y) * (1.0 - t) < HIT_HEIGHT)


func _land() -> void:
	_landed = true
	if _ball != null:
		_ball.visible = false
	if _visual != null:
		_visual.visible = true
	_drop_to_ground()
	set_deferred(&"monitoring", true)
	Sfx.play(self, LAND_SOUND, -6.0)
	Fx.burst([&"tomato_splash"], get_parent(), global_position + Vector3.UP * 0.3)


## Упал ли уже (лежит кляксой).
func is_landed() -> bool:
	return _landed
