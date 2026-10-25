class_name TopDownCamera
extends Camera3D
## Камера как в оригинале (3D camera Construct 3, масштаб 8 px = 1 м):
##   * позиция — позади машины на 0.6·32 px (2.4 м) и выше на 96 px (12 м);
##   * взгляд — в точку впереди на 1.4·32 px (5.6 м) на высоте машины
##     (наклон ≈ 34° от вертикали);
##   * «верх» экрана — направление машины;
##   * плавность: позиция lerp(…, 8·dt), поворот anglelerp(…, 14·dt);
##   * угол обзора 95° (вертикальный) задан в сцене top_down_camera.tscn.
##
## Двигается в _physics_process, чтобы интерполяция физики
## (physics/common/physics_interpolation) сглаживала её вместе с машиной.
## Как в оригинале: если рядом (ближе OPPONENT_RANGE) другой игрок, камера смещается
## к нему на OPPONENT_SHIFT (30 %).

## За кем следить (обычно машина локального игрока).
@export var target: Node3D
## Насколько камера позади машины, м.
@export var back_offset: float = 2.4
## Высота камеры над машиной, м.
@export var height: float = 12.0
## Куда смотрит камера — точка впереди машины, м.
@export var look_ahead: float = 5.6
## Резкость следования за позицией (1/с), в оригинале 8.
@export var follow_sharpness: float = 8.0
## Резкость доворота за машиной (1/с), в оригинале 14.
@export var rotation_sharpness: float = 14.0

## Группа камер — эффекты зовут shake_from() у всех (наше дополнение: в оригинале тряски нет).
const GROUP := &"cameras"
## Тряска затухает за столько секунд.
const SHAKE_TIME := 0.35
## Дальше этого от цели камеры события не трясут, м.
const SHAKE_RANGE := 30.0
## Смещение к сопернику: ближе этого (128 px = 16 м) и на какую долю.
const OPPONENT_RANGE := 16.0
const OPPONENT_SHIFT := 0.3

var _yaw: float = 0.0
var _focus: Vector3 = Vector3.ZERO
var _shake: float = 0.0
## Машины соперников (смещение к ближайшему).
var opponents: Array[Node3D] = []
var _shake_left: float = 0.0


func _ready() -> void:
	add_to_group(GROUP)
	snap_to_target()


## Тряхнуть камеру от события в точке at: strength — размах у самой цели, м
## (дальше — слабее, за SHAKE_RANGE — не трясёт).
func shake_from(at: Vector3, strength: float) -> void:
	if target == null:
		return
	var falloff := 1.0 - clampf(target.global_position.distance_to(at) / SHAKE_RANGE, 0.0, 1.0)
	if strength * falloff > _shake * (_shake_left / SHAKE_TIME):
		_shake = strength * falloff
		_shake_left = SHAKE_TIME


## Мгновенно поставить камеру на место (старт, сброс, смена цели).
func snap_to_target() -> void:
	if target == null:
		return
	_yaw = target.global_rotation.y
	_focus = target.global_position
	_apply()
	reset_physics_interpolation()


func _physics_process(delta: float) -> void:
	if target == null:
		return
	_yaw = lerp_angle(_yaw, target.global_rotation.y, 1.0 - exp(-rotation_sharpness * delta))
	_focus = _focus.lerp(_focus_target(), 1.0 - exp(-follow_sharpness * delta))
	_shake_left = maxf(_shake_left - delta, 0.0)
	_apply()


func _apply() -> void:
	var forward := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	var offset := Vector3.ZERO
	if _shake_left > 0.0:
		var amount := _shake * _shake_left / SHAKE_TIME
		offset = Vector3(randf_range(-amount, amount), 0.0, randf_range(-amount, amount))
	global_position = _focus + offset - forward * back_offset + Vector3.UP * height
	# «Верх» камеры — вперёд по ходу машины, как up-x/up-y в оригинале.
	look_at(_focus + forward * look_ahead, forward)


## Куда смотрит камера: на машину, а если рядом соперник — на 30 % к нему.
func _focus_target() -> Vector3:
	var focus := target.global_position
	var nearest: Node3D = null
	var nearest_distance := OPPONENT_RANGE
	for opponent in opponents:
		if not is_instance_valid(opponent):
			continue
		var distance := opponent.global_position.distance_to(focus)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = opponent
	if nearest != null:
		focus = focus.lerp(nearest.global_position, OPPONENT_SHIFT)
	return focus
