@tool
class_name C3BoxVisual
extends MeshInstance3D
## Видимая коробка «3D shape» оригинала: грани — кадры <folder>/<base_name>-00N.png
## (см. C3Box). Сетка строится при загрузке и не сохраняется в сцену; одинаковые коробки
## делят одну сетку. flat = true — плоская картинка на земле (спрайт оригинала, кадр frame).

@export var size: Vector3 = Vector3(2.0, 2.0, 2.0):
	set(value):
		size = value
		_rebuild()
@export var folder: String = "levelobj":
	set(value):
		folder = value
		_rebuild()
@export var base_name: String = "":
	set(value):
		base_name = value
		_rebuild()
@export var flat: bool = false:
	set(value):
		flat = value
		_rebuild()
## Кадр плоской картинки (flat).
@export var frame: int = 0:
	set(value):
		frame = value
		_rebuild()
## Видимые грани (биты C3Box.FACE_*, как face-… оригинала) и форма (пирамида — щебень).
@export_flags("back (дно)", "front (крышка)", "left (−X)", "right (+X)", "top (−Z)", "bottom (+Z)")
var faces: int = C3Box.FACES_DEFAULT:
	set(value):
		faces = value
		_rebuild()
@export var pyramid: bool = false:
	set(value):
		pyramid = value
		_rebuild()
## Плоская картинка — вид горы сверху: поднять её горой такой высоты, м (0 — плоская).
@export var peak: float = 0.0:
	set(value):
		peak = value
		_rebuild()
## Плоская картинка — развёртка таблички-«домика» (две створки): поставить её.
@export var standing_sign: bool = false:
	set(value):
		standing_sign = value
		_rebuild()
@export_range(0.0, 1.0) var alpha: float = 1.0:
	set(value):
		alpha = value
		_rebuild()


func _ready() -> void:
	_rebuild()


## Сетка строится из картинок — в сцену её не сохраняем.
func _validate_property(property: Dictionary) -> void:
	if property["name"] == "mesh":
		property["usage"] = property["usage"] & ~PROPERTY_USAGE_STORAGE


func _rebuild() -> void:
	if not is_inside_tree() or base_name.is_empty():
		return
	var frames := C3Box.frames_of(folder, base_name)
	if flat:
		var texture: Texture2D = frames[frame] if frame < frames.size() else null
		if texture == null:
			var single := "res://assets/original/textures/%s/%s.png" % [folder, base_name]
			texture = load(single) as Texture2D if ResourceLoader.exists(single) else null
		if standing_sign:
			mesh = C3Box.a_frame(Vector2(size.x, size.z), texture)
		elif peak > 0.0:
			mesh = C3Box.mountain(Vector2(size.x, size.z), peak, texture)
		else:
			mesh = C3Box.flat(Vector2(size.x, size.z), texture)
	else:
		mesh = C3Box.mesh(size, frames, alpha, faces, pyramid)
