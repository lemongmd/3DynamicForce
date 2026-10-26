class_name Ghost
extends ParryHazard
## Призрак «Хэллоуина»: плавает поперёк дороги туда-обратно (синус — замедляется у краёв),
## покачивается вверх-вниз, клонится по ходу и машет ручками. Задел машину — как все парируемые: окно
## парирования открыто — проезд сквозь, нет — остановка. Призраки одной карты не в такт
## (фаза — от места).

## Период хода туда-обратно и покачивания, с; размах покачивания, м; наклон по ходу, градусы.
const MOVE_PERIOD := 3.4
const BOB_PERIOD := 1.6
const BOB_HEIGHT := 0.3
const LEAN_DEG := 12.0
## Ручки: период и размах взмаха, градусы.
const ARM_PERIOD := 0.9
const ARM_SWING_DEG := 22.0

## Размах движения поперёк дороги, м (layout_map ставит по ширине дороги).
@export var sweep: float = 4.0

var _origin: Vector3
var _time: float = 0.0
var _visual: Node3D
var _visual_y: float = 0.0
var _arms: Array[Node3D] = []


func _ready() -> void:
	super._ready()
	_origin = position
	add_to_group(ItemObject.PARRY_ITEMS_GROUP)
	_time = fposmod(_origin.x * 0.31 + _origin.z * 0.17, MOVE_PERIOD)
	_visual = get_node_or_null(^"Visual") as Node3D
	if _visual != null:
		_visual_y = _visual.position.y
		for arm_name in [^"ArmL", ^"ArmR"]:
			var arm := _visual.get_node_or_null(arm_name) as Node3D
			if arm != null:
				_arms.append(arm)


func _physics_process(delta: float) -> void:
	_time += delta
	var phase := _time / MOVE_PERIOD * TAU
	position = _origin + basis.x.normalized() * sin(phase) * sweep
	if _visual != null:
		_visual.position.y = _visual_y + sin(_time / BOB_PERIOD * TAU) * BOB_HEIGHT
		# Клонится туда, куда летит (скорость — cos фазы).
		_visual.rotation.z = -cos(phase) * deg_to_rad(LEAN_DEG)
	# Ручки машут зеркально («у-у-у!»).
	var swing := sin(_time / ARM_PERIOD * TAU) * deg_to_rad(ARM_SWING_DEG)
	for i in _arms.size():
		_arms[i].rotation.z = swing * (1.0 if i == 0 else -1.0)
