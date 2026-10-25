class_name CarVisual
extends Node3D
## Косметика машины: наклон по поверхности, крен в поворотах, доворот модели
## в дрифте и вращение колёс.
##
## Физика от этого узла не зависит. Модель внутри можно заменить на любую:
## колёса ищутся по префиксу имени, и если их нет — просто не крутятся.

## Модель машины. Если задана — при старте заменяет дочерний узел Model.
@export var model_scene: PackedScene
## Скин (CarSkin): модель по кузову, цвет, стёкла, рисунок, колёса — главнее model_scene.
## Гонка ставит его каждой машине до входа в дерево (или set_skin потом).
var skin: CarSkin
## Дополнительный доворот модели в сторону заноса, градусы.
@export var drift_yaw_deg: float = 14.0
## Крен кузова в повороте на максимальной скорости, градусы.
@export var lean_deg: float = 5.0
## Скорость сглаживания всех поворотов модели (1/с).
@export var smoothing: float = 12.0
## Крутить колёса по ходу движения (для круглых колёс). Поворот рулём работает всегда.
@export var spin_wheels: bool = true
@export var wheel_radius: float = 0.36
@export var front_wheel_steer_deg: float = 25.0
## Узлы, имя которых начинается с этого префикса, крутятся как колёса.
@export var wheel_prefix: String = "Wheel_"
## Из них эти ещё и поворачиваются рулём.
@export var front_wheel_prefix: String = "Wheel_F"

var _car: CarController
var _wheels: Array[Node3D] = []
var _front_wheels: Array[Node3D] = []
var _wheel_rest: Dictionary = {}
var _wheel_spin: float = 0.0
var _drift_yaw: float = 0.0
var _lean: float = 0.0
var _tilt: Quaternion = Quaternion.IDENTITY


func _ready() -> void:
	_car = get_parent() as CarController
	if _car == null:
		push_warning("CarVisual: родитель не CarController, визуальные эффекты отключены.")
	if skin != null:
		set_skin(skin)
	elif model_scene != null:
		set_model(model_scene)
	else:
		_collect_wheels(self)


## Сменить скин: модель кузова, текстура, колёса.
func set_skin(value: CarSkin) -> void:
	skin = value
	set_model(skin.model_scene())


## Заменить модель машины (узел Model) на экземпляр сцены.
func set_model(scene: PackedScene) -> void:
	var old := get_node_or_null(^"Model")
	if old != null:
		remove_child(old)
		old.queue_free()
	var model := scene.instantiate()
	model.name = "Model"
	add_child(model)
	if skin != null and model is Node3D:
		skin.paint(model)
	_wheels.clear()
	_front_wheels.clear()
	_wheel_rest.clear()
	_collect_wheels(self)


func _physics_process(delta: float) -> void:
	if _car == null:
		return
	var k := 1.0 - exp(-smoothing * delta)

	# Занос вправо -> нос модели доворачивается вправо (отрицательный угол вокруг Y).
	_drift_yaw = lerpf(_drift_yaw, -_car.drift_direction * deg_to_rad(drift_yaw_deg), k)

	# Поворот вправо -> кузов кренится влево (положительный угол вокруг +Z).
	var target_lean := _car.current_input.steer * minf(_car.get_speed_ratio(), 1.0) * deg_to_rad(lean_deg)
	_lean = lerpf(_lean, target_lean, k)

	# Наклон по нормали поверхности в локальных осях машины.
	var target_tilt := Quaternion.IDENTITY
	# У чужой машины (сеть) физики нет — нормали пола тоже, едет ровно.
	if _car.is_grounded() and not _car.is_puppet:
		var local_normal := (_car.global_basis.inverse() * _car.get_floor_normal()).normalized()
		target_tilt = Quaternion(Vector3.UP, local_normal)
	_tilt = _tilt.slerp(target_tilt, k)

	basis = Basis(_tilt) * Basis(Vector3.UP, _drift_yaw) * Basis(Vector3.BACK, _lean)

	_update_wheels(delta)


func _update_wheels(delta: float) -> void:
	if _wheels.is_empty():
		return
	if spin_wheels:
		_wheel_spin = fmod(_wheel_spin + _car.forward_speed / maxf(wheel_radius, 0.01) * delta, TAU)
	# Езда вперёд (-Z) — верх колеса уходит вперёд, это отрицательный поворот вокруг +X.
	var spin := Basis(Vector3.RIGHT, -_wheel_spin)
	var steer := Basis(Vector3.UP, -_car.current_input.steer * deg_to_rad(front_wheel_steer_deg))
	for wheel in _wheels:
		var rest: Basis = _wheel_rest[wheel]
		if wheel in _front_wheels:
			wheel.basis = steer * spin * rest
		else:
			wheel.basis = spin * rest


func _collect_wheels(node: Node) -> void:
	for child in node.get_children():
		if child is Node3D and String(child.name).begins_with(wheel_prefix):
			var wheel := child as Node3D
			_wheels.append(wheel)
			_wheel_rest[wheel] = wheel.basis
			if String(child.name).begins_with(front_wheel_prefix):
				_front_wheels.append(wheel)
		_collect_wheels(child)
