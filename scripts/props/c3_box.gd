class_name C3Box
extends RefCounted
## «3D shape» оригинала (Construct 3) из картинок граней. Порядок кадров и имена граней —
## как в оригинале (вид сверху, ось Y картинки уровня = наша ось Z):
##   кадр 0 — back (дно), 1 — front (крышка), 2 — left (−X), 3 — right (+X),
##   4 — top (−Z), 5 — bottom (+Z).
## У объекта оригинала включены не все грани (face-…): краб — одна стоячая картинка,
## забор — решётка на одной грани. shape = box (коробка) или pyramid (пирамида: щебень —
## боковые грани-треугольники к вершине). Каждая грань — своя поверхность с картинкой
## целиком (фильтр Nearest, без зеркалирования снаружи). Начало координат — центр дна.

const PX_PER_M := 8.0
## Грани (биты): как face-back/front/left/right/top/bottom оригинала.
const FACE_BACK := 1
const FACE_FRONT := 2
const FACE_LEFT := 4
const FACE_RIGHT := 8
const FACE_TOP := 16
const FACE_BOTTOM := 32
## Обычная коробка оригинала: всё, кроме дна.
const FACES_DEFAULT := FACE_FRONT | FACE_LEFT | FACE_RIGHT | FACE_TOP | FACE_BOTTOM

static var _materials: Dictionary = {}
static var _meshes: Dictionary = {}


## Сетка size (м: x — ширина, y — высота, z — глубина) с картинками frames (кадры 0..5
## объекта оригинала), гранями faces (биты FACE_*), коробка или пирамида.
## Если видны не все боковые грани (одна картинка — забор, краб), грани двусторонние.
## Одинаковые запросы возвращают одну и ту же сетку.
static func mesh(size: Vector3, frames: Array[Texture2D], alpha: float = 1.0,
		faces: int = FACES_DEFAULT, pyramid: bool = false) -> ArrayMesh:
	var key := "%s|%s|%.2f|%d|%s" % [size, frames.map(func(t: Texture2D) -> String: return t.resource_path if t != null else ""),
			alpha, faces, pyramid]
	if _meshes.has(key):
		return _meshes[key]
	var lid := _frame(frames, 1)
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var h := size.y
	var sides_mask := FACE_LEFT | FACE_RIGHT | FACE_TOP | FACE_BOTTOM
	var double_sided := (faces & sides_mask) != sides_mask
	var result := ArrayMesh.new()
	# Бока: [бит, кадр, низ-лево, низ-право] (если смотреть снаружи).
	var sides := [
		[FACE_LEFT, 2, Vector3(-hx, 0, -hz), Vector3(-hx, 0, hz)],
		[FACE_RIGHT, 3, Vector3(hx, 0, hz), Vector3(hx, 0, -hz)],
		[FACE_TOP, 4, Vector3(hx, 0, -hz), Vector3(-hx, 0, -hz)],
		[FACE_BOTTOM, 5, Vector3(-hx, 0, hz), Vector3(hx, 0, hz)],
	]
	for side in sides:
		if faces & int(side[0]) == 0:
			continue
		var texture := _frame(frames, int(side[1]))
		var a: Vector3 = side[2]
		var b: Vector3 = side[3]
		if pyramid:
			_triangle(result, a, b, Vector3(0, h, 0), texture, alpha, double_sided)
		else:
			_face(result, [a, b, b + Vector3.UP * h, a + Vector3.UP * h], texture, alpha, double_sided)
	if faces & FACE_FRONT != 0 and not pyramid:
		_face(result, [Vector3(-hx, h, hz), Vector3(hx, h, hz), Vector3(hx, h, -hz), Vector3(-hx, h, -hz)], lid, alpha, double_sided)
	if faces & FACE_BACK != 0:
		_face(result, [Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(hx, 0, hz), Vector3(-hx, 0, hz)],
				_frame(frames, 0), alpha, double_sided)
	_meshes[key] = result
	return result


## Плоская картинка, лежащая на земле (спрайт оригинала в 3D-слое): size — x и z, м.
static func flat(size: Vector2, texture: Texture2D, height: float = 0.06) -> ArrayMesh:
	var key := "flat|%s|%s|%.2f" % [size, texture.resource_path if texture != null else "", height]
	if _meshes.has(key):
		return _meshes[key]
	var hx := size.x * 0.5
	var hz := size.y * 0.5
	var result := ArrayMesh.new()
	_face(result, [Vector3(-hx, height, hz), Vector3(hx, height, hz), Vector3(hx, height, -hz), Vector3(-hx, height, -hz)], texture, 1.0)
	_meshes[key] = result
	return result


## Гора из картинки «вид сверху» (камни-горы Снежной: серые склоны, белая шапка в середине):
## сетка size.x × size.y, поднятая к центру до height, картинка ложится сверху.
## Края — на земле (чуть ниже, чтобы не было щели).
static func mountain(size: Vector2, height: float, texture: Texture2D) -> ArrayMesh:
	var key := "mountain|%s|%s|%.2f" % [size, texture.resource_path if texture != null else "", height]
	if _meshes.has(key):
		return _meshes[key]
	const CELLS := 24
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var points: Array[Vector3] = []
	var uvs: Array[Vector2] = []
	for j in CELLS + 1:
		for i in CELLS + 1:
			var u := float(i) / CELLS
			var v := float(j) / CELLS
			# Расстояние до центра — «скруглённый квадрат», чтобы углы картинки были низом склона.
			var dx := absf(u - 0.5) * 2.0
			var dz := absf(v - 0.5) * 2.0
			var r := clampf(pow(pow(dx, 3.0) + pow(dz, 3.0), 1.0 / 3.0), 0.0, 1.0)
			var h := height * pow(1.0 - r, 1.4) - 0.3
			points.append(Vector3((u - 0.5) * size.x, h, (v - 0.5) * size.y))
			uvs.append(Vector2(u, v))
	for j in CELLS:
		for i in CELLS:
			var a := j * (CELLS + 1) + i
			var b := a + 1
			var c := a + CELLS + 1
			var d := c + 1
			# Сверху обход по часовой стрелке (лицевая сторона в Godot).
			for index in [a, b, d, a, d, c]:
				st.set_uv(uvs[index])
				st.add_vertex(points[index])
	st.generate_normals()
	st.set_material(_material(texture, 1.0))
	var result := st.commit()
	_meshes[key] = result
	return result


## Табличка-«домик» (мокрый пол): картинка оригинала — развёртка вида сверху, две створки
## со сгибом посередине. Створки шириной size.x и длиной size.y / 2 сходятся вверху,
## ножки разведены по оси Z. Видна с обеих сторон.
static func a_frame(size: Vector2, texture: Texture2D) -> ArrayMesh:
	var key := "aframe|%s|%s" % [size, texture.resource_path if texture != null else ""]
	if _meshes.has(key):
		return _meshes[key]
	var panel := size.y * 0.5
	var spread := panel * 0.32
	var ridge := sqrt(panel * panel - spread * spread)
	var hx := size.x * 0.5
	var top_l := Vector3(-hx, ridge, 0.0)
	var top_r := Vector3(hx, ridge, 0.0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Створка «вперёд» (−Z) — верхняя половина картинки, «назад» (+Z) — нижняя.
	for side in [-1.0, 1.0]:
		var foot_l := Vector3(-hx, 0.0, side * spread)
		var foot_r := Vector3(hx, 0.0, side * spread)
		var v_foot := 0.0 if side < 0.0 else 1.0
		var quad := [[foot_l, Vector2(0, v_foot)], [foot_r, Vector2(1, v_foot)],
				[top_r, Vector2(1, 0.5)], [top_l, Vector2(0, 0.5)]]
		for index in [0, 1, 2, 0, 2, 3]:
			st.set_uv(quad[index][1])
			st.add_vertex(quad[index][0])
	st.generate_normals()
	var material := (_material(texture, 1.0) as StandardMaterial3D).duplicate() as StandardMaterial3D
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	st.set_material(material)
	var result := st.commit()
	_meshes[key] = result
	return result


## Кадры объекта оригинала: res://assets/original/textures/<папка>/<имя>-000.png…
static func frames_of(folder: String, base_name: String) -> Array[Texture2D]:
	var result: Array[Texture2D] = []
	for k in 6:
		var path := "res://assets/original/textures/%s/%s-%03d.png" % [folder, base_name, k]
		result.append(load(path) as Texture2D if ResourceLoader.exists(path) else null)
	return result


static func _frame(frames: Array[Texture2D], index: int) -> Texture2D:
	return frames[index] if index < frames.size() else null


static func _face(target: ArrayMesh, corners: Array, texture: Texture2D, alpha: float,
		double_sided: bool = false) -> void:
	var a: Vector3 = corners[0]
	var b: Vector3 = corners[1]
	var c: Vector3 = corners[2]
	var d: Vector3 = corners[3]
	var normal := (b - a).cross(d - a).normalized()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(normal)
	# Обход по часовой стрелке, если смотреть снаружи (лицевая сторона в Godot).
	for v in [[a, Vector2(0, 1)], [c, Vector2(1, 0)], [b, Vector2(1, 1)], [a, Vector2(0, 1)], [d, Vector2(0, 0)], [c, Vector2(1, 0)]]:
		st.set_normal(normal)
		st.set_uv(v[1])
		st.add_vertex(v[0])
	st.set_material(_material(texture, alpha, double_sided))
	st.commit(target)


## Треугольная грань пирамиды: низ-лево a, низ-право b (снаружи), вершина apex;
## картинка — треугольник с вершиной посередине верхнего края.
static func _triangle(target: ArrayMesh, a: Vector3, b: Vector3, apex: Vector3, texture: Texture2D,
		alpha: float, double_sided: bool) -> void:
	var normal := (b - a).cross(apex - a).normalized()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in [[a, Vector2(0, 1)], [apex, Vector2(0.5, 0)], [b, Vector2(1, 1)]]:
		st.set_normal(normal)
		st.set_uv(v[1])
		st.add_vertex(v[0])
	st.set_material(_material(texture, alpha, double_sided))
	st.commit(target)


static func _material(texture: Texture2D, alpha: float, double_sided: bool = false) -> StandardMaterial3D:
	var key := "%s|%.2f|%s" % [texture.resource_path if texture != null else "", alpha, double_sided]
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	if alpha < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color.a = alpha
	else:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	if double_sided:
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_materials[key] = material
	return material
