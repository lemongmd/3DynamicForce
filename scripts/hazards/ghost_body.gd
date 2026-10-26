@tool
extends MeshInstance3D
## Тело призрака «Хэллоуина» по референсам автора ремейка: «простыня» — купол, книзу шире,
## подол волнами, снизу открыт. Рожица — одна из трёх картинок (ghost_body_N.png из
## build_halloween_textures.gd), выбор — от места, чтобы призраки карты были разные.
## Перед (рожица) смотрит в +Z узла — навстречу машинам.

const SEGMENTS := 24
const DOME_RADIUS := 0.85
const DOME_CENTER := 1.45
const HEM_Y := 0.15
const HEM_RADIUS := 1.08
const HEM_WAVES := 6
const HEM_WAVE := 0.14
const FACES: Array[Texture2D] = [
	preload("res://assets/textures/halloween/ghost_body_0.png"),
	preload("res://assets/textures/halloween/ghost_body_1.png"),
	preload("res://assets/textures/halloween/ghost_body_2.png"),
]
const SHADER := preload("res://assets/shaders/glow_mask.gdshader")

static var _mesh: ArrayMesh
static var _materials: Dictionary = {}

## Номер рожицы; −1 — от места.
@export var face: int = -1


func _ready() -> void:
	mesh = body_mesh()
	var index := face
	if index < 0:
		index = absi(hash(Vector2i(roundi(global_position.x), roundi(global_position.z)))) % FACES.size()
	material_override = _material(index)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func _material(index: int) -> ShaderMaterial:
	if not _materials.has(index):
		var material := ShaderMaterial.new()
		material.shader = SHADER
		material.set_shader_parameter(&"albedo_texture", FACES[index])
		# Светится сама картинка: белое тело чуть горит голубым, чёрная рожица — нет.
		material.set_shader_parameter(&"glow_texture", FACES[index])
		material.set_shader_parameter(&"glow_color", Color(0.55, 0.66, 1.0))
		material.set_shader_parameter(&"glow_energy", 0.45)
		material.set_shader_parameter(&"roughness_value", 0.6)
		material.set_shader_parameter(&"inside_shade", 0.35)
		_materials[index] = material
	return _materials[index]


## Профиль (радиус, высота) сверху вниз: четверть круга купола, потом расширение к подолу.
static func _profile() -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 9:
		var a := float(i) / 8.0 * PI * 0.5
		points.append(Vector2(DOME_RADIUS * sin(a), DOME_CENTER + DOME_RADIUS * cos(a)))
	for i in range(1, 7):
		var s := float(i) / 6.0
		points.append(Vector2(lerpf(DOME_RADIUS, HEM_RADIUS, s * s), lerpf(DOME_CENTER, HEM_Y, s)))
	return points


static func body_mesh() -> ArrayMesh:
	if _mesh != null:
		return _mesh
	var profile := _profile()
	# v — по длине профиля (пиксели картинки почти квадратные).
	var arc := PackedFloat32Array([0.0])
	for i in range(1, profile.size()):
		arc.append(arc[i - 1] + profile[i].distance_to(profile[i - 1]))
	var total := arc[arc.size() - 1]
	var last := profile.size() - 1
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in profile.size():
		# Нормаль профиля — по соседним точкам (поверхность вращения, без шва на стыке развёртки).
		var tangent := profile[mini(i + 1, last)] - profile[maxi(i - 1, 0)]
		var normal := Vector2(-tangent.y, tangent.x).normalized()
		# Волны — только у подола.
		var wave_weight := 1.0 if i == last else (0.35 if i == last - 1 else 0.0)
		for j in SEGMENTS + 1:
			var u := float(j) / SEGMENTS
			var angle := (u - 0.5) * TAU
			var y := profile[i].y + HEM_WAVE * cos(HEM_WAVES * angle) * wave_weight
			tool.set_uv(Vector2(u, arc[i] / total))
			tool.set_normal(Vector3(normal.x * sin(angle), normal.y, normal.x * cos(angle)))
			tool.add_vertex(Vector3(profile[i].x * sin(angle), y, profile[i].x * cos(angle)))
	var row := SEGMENTS + 1
	for i in last:
		for j in SEGMENTS:
			var a := i * row + j
			var b := a + row
			tool.add_index(a)
			tool.add_index(a + 1)
			tool.add_index(b)
			tool.add_index(a + 1)
			tool.add_index(b + 1)
			tool.add_index(b)
	_mesh = tool.commit()
	return _mesh
