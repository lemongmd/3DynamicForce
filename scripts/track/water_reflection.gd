class_name WaterReflection
extends Node
## Отражения в жидком фоне (вода, масло): вторая камера, зеркальная текущей относительно
## плоскости фона, рисует мир в SubViewport (половина разрешения экрана); шейдер жидкости
## (liquid.gdshader) берёт оттуда картинку по положению пикселя на экране, с рябью волн.
## Сама вода — на своём визуальном слое (LAYER), зеркальная камера её не видит.
## Только в игре (в редакторе Track не создаёт этот узел). Включается Track.background_reflection
## (автор ремейка про воду «Трамплинов»: «пластиковый материал, сделай отражения как у воды»).

## Визуальный слой воды (20-й, последний): его не видит зеркальная камера.
const LAYER := 1 << 19
## Разрешение отражения — доля экрана (384×216 -> 192×108): дёшево и пиксельно, как всё.
const RESOLUTION_SCALE := 0.5

## Материал воды (ShaderMaterial с liquid.gdshader) и высота её плоскости в мире.
var material: ShaderMaterial
var water_height: float = 0.0

var _viewport: SubViewport
var _camera: Camera3D


func _ready() -> void:
	# Камера двигается в _process по уже сглаженному положению основной — своя интерполяция
	# физики ей не нужна (и ругается, если двигать не в физическом кадре).
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_viewport = SubViewport.new()
	_viewport.name = "ReflectionViewport"
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	_camera = Camera3D.new()
	_camera.name = "ReflectionCamera"
	_camera.cull_mask = 0xFFFFF & ~LAYER
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_viewport.add_child(_camera)
	_camera.current = true
	if material != null:
		material.set_shader_parameter(&"reflection_texture", _viewport.get_texture())
		material.set_shader_parameter(&"reflection_strength", 1.0)


func _process(_delta: float) -> void:
	var source := get_viewport().get_camera_3d()
	if source == null or source == _camera:
		return
	var screen := get_viewport().get_visible_rect().size
	var wanted := Vector2i(maxi(roundi(screen.x * RESOLUTION_SCALE), 16), maxi(roundi(screen.y * RESOLUTION_SCALE), 16))
	if _viewport.size != wanted:
		_viewport.size = wanted
	_camera.fov = source.fov
	_camera.near = source.near
	_camera.far = source.far
	_camera.keep_aspect = source.keep_aspect
	_camera.global_transform = mirrored(source.get_global_transform_interpolated(), water_height)


## Камера, зеркальная transform относительно плоскости y = height. Настоящее зеркало —
## левый базис; у нас ось X перевёрнута обратно (правый базис), поэтому картинка выходит
## отражённой по горизонтали — шейдер берёт её с 1 − x.
static func mirrored(transform: Transform3D, height: float) -> Transform3D:
	var flip := func(v: Vector3) -> Vector3: return Vector3(v.x, -v.y, v.z)
	var basis := Basis(-flip.call(transform.basis.x), flip.call(transform.basis.y), flip.call(transform.basis.z))
	var origin := transform.origin
	origin.y = 2.0 * height - origin.y
	return Transform3D(basis, origin)
