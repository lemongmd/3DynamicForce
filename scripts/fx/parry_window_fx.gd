class_name ParryWindowFx
extends Sprite3D
## Волны у капота, пока открыто окно парирования (эмоция CarEmoteShow оригинала,
## без звука гудка). Мигает кадрами и тает, затем удаляется.

## Кадры анимации (в оригинале — два).
@export var frames: Array[Texture2D] = []
## Время жизни, с (равно окну парирования).
@export var lifetime: float = 0.4
## Смена кадра, с.
@export var frame_time: float = 0.08

var _age: float = 0.0


func _ready() -> void:
	if not frames.is_empty():
		texture = frames[0]


func _process(delta: float) -> void:
	_age += delta
	if not frames.is_empty():
		texture = frames[int(_age / frame_time) % frames.size()]
	modulate.a = clampf(1.0 - _age / lifetime, 0.0, 1.0)
	if _age >= lifetime:
		queue_free()
