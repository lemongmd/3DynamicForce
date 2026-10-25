class_name Snowball
extends ParryHazard
## Снежок турели (Snowball оригинала): летит по своей оси +X со скоростью 320 px/с
## (40 м/с), пролетев 192 px (24 м), исчезает; сквозь стены (как Bullet оригинала).
## Попал — парирование, иначе остановка + BassBubble + злость (ParryHazard).

const SPEED := 40.0
const RANGE := 24.0

var _travelled: float = 0.0


func _ready() -> void:
	super._ready()
	add_to_group(ItemObject.PARRY_ITEMS_GROUP)


func _physics_process(delta: float) -> void:
	var step := SPEED * delta
	global_position += global_basis.x * step
	_travelled += step
	if _travelled >= RANGE:
		queue_free()
