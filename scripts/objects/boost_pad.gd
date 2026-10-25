@tool
class_name BoostPad
extends Area3D
## Ускоритель оригинала (BoostPad), 24 px = 3 м:
##   * PlusSpeed / SuperSpeed — пока машина на нём, толкает её вперёд по её
##     направлению на 96 / 224 px/с (12 / 28 м/с), как move-forward в оригинале;
##   * MaxSpeed — при въезде сразу разгоняет до предела.
## При въезде — звук BoostPad (у MaxSpeed ещё BassJump).

enum Kind { PLUS_SPEED, SUPER_SPEED, MAX_SPEED }

const PUSH_SPEED := {Kind.PLUS_SPEED: 12.0, Kind.SUPER_SPEED: 28.0, Kind.MAX_SPEED: 0.0}
## Кадров в секунду у анимации стрелок.
const FRAME_RATE := 10.0

@export var kind: Kind = Kind.PLUS_SPEED:
	set(value):
		kind = value
		_frame_time = 0.0
		_show_frame(0)
## Кадры анимации по видам (в оригинале по 3).
@export var plus_frames: Array[Texture2D] = []
@export var super_frames: Array[Texture2D] = []
@export var max_frames: Array[Texture2D] = []
@export var enter_sound: AudioStream
@export var max_speed_sound: AudioStream

var _frame_time: float = 0.0


func _ready() -> void:
	_show_frame(0)
	if Engine.is_editor_hint():
		return
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_frame_time += delta
	_show_frame(int(_frame_time * FRAME_RATE))


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or kind == Kind.MAX_SPEED:
		return
	for body in get_overlapping_bodies():
		var car := body as CarController
		if car != null and not car.is_puppet:
			car.add_push(car.get_flat_forward() * float(PUSH_SPEED[kind]))


func _on_body_entered(body: Node3D) -> void:
	var car := body as CarController
	if car == null or car.is_puppet:
		return
	Sfx.play(car, enter_sound)
	if kind == Kind.MAX_SPEED:
		car.set_speed_to_max()
		Sfx.play(car, max_speed_sound)


func _frames() -> Array[Texture2D]:
	match kind:
		Kind.SUPER_SPEED:
			return super_frames
		Kind.MAX_SPEED:
			return max_frames
	return plus_frames


func _show_frame(index: int) -> void:
	var sprite := get_node_or_null(^"Sprite") as Sprite3D
	var frames := _frames()
	if sprite != null and not frames.is_empty():
		sprite.texture = frames[index % frames.size()]
