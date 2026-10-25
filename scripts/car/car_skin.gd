class_name CarSkin
extends RefCounted
## Скин машины как в оригинале (MenuSkin, SpawnPlayer): цвет кузова — 4 уровня на канал
## (Player.set-default-color(R·85, G·85, B·85)), кузов (3 формы + секретный танк), стёкла (11),
## рисунок (9), колёса (4). Строка скина — как переменная skin оригинала: цифры
## «R G B 0 кузов стёкла рисунок колёса» (четвёртая — 0, у оригинала тоже), напр. «33300000».
##
## Модели — blender/build_car.py: кузов нарисован в серых тонах, рядом .json с буквами атласа
## (какая часть машины в каждом пикселе). paint() собирает из них текстуру скина: кузов умножается
## на цвет, стёкла перекрашиваются в цвета кадра стёкол оригинала, колёса — по кадру колёс (размер
## и цвет). Рисунок оригинала (вид сверху) — объёмный (узел Decal модели): наклейка из пиксельных
## кубиков на крыше, спойлер (кадр 5) — антикрыло за кормой, ушки (кадр 8) — кошачьи ушки на крыше,
## чёлка (кадр 9, от stysan — чёлка его персонажа) — свисает с крыши на лобовое стекло.

const LEVELS := 4
## Обычные кузова (0..2); кузов TANK — секретный танк (в оригинале — если зажать кнопку кузова).
const BASES := 3
const TANK := 3
const GLASSES := 11
const PRINTS := 10
const WHEELS := 4
const DEFAULT_CODE := "33300000"
const MODELS := ["res://assets/models/cars/car_base0", "res://assets/models/cars/car_base1",
		"res://assets/models/cars/car_base2", "res://assets/models/cars/car_tank"]
const SPRITES := "res://assets/original/textures/"
## Скины участников без своего скина (автотесты, заезд из редактора): красная, синяя,
## зелёная, жёлтая — как прежние 4 машины.
const PRESETS := ["30000000", "01300000", "02000000", "33000000"]
## Колёса: масштаб (вдоль оси, радиус) — 0 обычные, 1 широкие, 2 радужные, 3 маленькие.
const WHEEL_SCALE := [Vector2(1.0, 1.0), Vector2(1.6, 1.1), Vector2(1.0, 1.0), Vector2(1.0, 0.72)]
const RAINBOW_WHEELS := 2
## Рисунки, которые в оригинале торчат за кузовом: антикрыло сзади и ушки спереди.
const PRINT_SPOILER := 5
const PRINT_EARS := 8
## Чёлка (свой рисунок, не из оригинала): у носа спрайта — свешивается с крыши на лобовое стекло.
const PRINT_BANGS := 9
## Наклейка на крыше: пиксель рисунка — кубик (в оригинале кузов 22 px = 3 м: 0.135 м),
## на маленькой крыше — мельче, чтобы рисунок целиком лёг на неё; толщина кубиков, м.
const STICKER_PIXEL := 0.135
const STICKER_THICKNESS := 0.05
## Узлы модели (build_car.py): крыша (кабина / башня танка) и кузов (корпус танка).
const ROOF_NODES := ["Cabin", "Turret"]
const BODY_NODES := ["Body", "Hull"]
const ROOF_AREAS := ["roof", "turret"]
const BODY_AREAS := ["body_top", "tank_top"]

var r: int = 3
var g: int = 3
var b: int = 3
var base: int = 0
var glass: int = 0
var decal: int = 0
var wheels: int = 0

## Собранные материалы по строке скина (одинаковые скины — одна текстура).
static var _materials: Dictionary = {}
static var _meta: Dictionary = {}
## Сетки объёмных рисунков по «кузов|рисунок».
static var _decal_meshes: Dictionary = {}


static func from_code(code: String) -> CarSkin:
	var skin := CarSkin.new()
	if code.length() < 8 or not code.is_valid_int():
		code = DEFAULT_CODE
	var digits := PackedInt32Array()
	for i in 8:
		digits.append(int(code[i]))
	skin.r = clampi(digits[0], 0, LEVELS - 1)
	skin.g = clampi(digits[1], 0, LEVELS - 1)
	skin.b = clampi(digits[2], 0, LEVELS - 1)
	skin.base = clampi(digits[4], 0, TANK)
	skin.glass = clampi(digits[5], 0, GLASSES - 1)
	skin.decal = clampi(digits[6], 0, PRINTS - 1)
	skin.wheels = clampi(digits[7], 0, WHEELS - 1)
	return skin


static func preset(index: int) -> CarSkin:
	return from_code(PRESETS[posmod(index, PRESETS.size())])


func to_code() -> String:
	return "%d%d%d0%d%d%d%d" % [r, g, b, base, glass, decal, wheels]


## Цвет кузова: R·85, G·85, B·85 (как в оригинале).
func body_color() -> Color:
	return Color8(r * 85, g * 85, b * 85)


## Цвет иконки игрока: R·64+64… (PlayerCarIcon оригинала — светлее кузова).
func icon_color() -> Color:
	return Color8(r * 64 + 64, g * 64 + 64, b * 64 + 64)


func model_scene() -> PackedScene:
	return load(MODELS[base] + ".glb") as PackedScene


## Скин на модель (экземпляр model_scene()): текстура и колёса.
func paint(model: Node3D) -> void:
	var material := _material_for(model)
	if material != null:
		_apply_material(model, material)
	var scale: Vector2 = WHEEL_SCALE[wheels]
	for wheel in _wheels_of(model):
		var rest := wheel.position
		wheel.scale = Vector3(scale.x, scale.y, scale.y)
		# Колесо стоит на земле (центр — на радиусе), шире — наружу, а не в кузов.
		wheel.position = Vector3(rest.x + signf(rest.x) * 0.13 * (scale.x - 1.0), rest.y * scale.y, rest.z)
	_add_decal(model)


func _material_for(model: Node3D) -> Material:
	var code := to_code()
	if _materials.has(code):
		return _materials[code]
	var source := _first_material(model) as StandardMaterial3D
	var meta := _load_meta(MODELS[base] + ".json")
	if source == null or source.albedo_texture == null or meta.is_empty():
		return null
	var image := source.albedo_texture.get_image()
	if image == null:
		return null
	image = image.duplicate() as Image
	if image.is_compressed():
		image.decompress()
	image.clear_mipmaps()
	image.convert(Image.FORMAT_RGBA8)
	_compose(image, meta)
	image.generate_mipmaps()
	var material := source.duplicate() as StandardMaterial3D
	material.albedo_texture = ImageTexture.create_from_image(image)
	_materials[code] = material
	return material


## Перекраска атласа по буквам (.json build_car.py) и рисунок сверху.
func _compose(image: Image, meta: Dictionary) -> void:
	var letters: Array = meta["letters"]
	var palette := {}
	for key in meta["palette"]:
		palette[key] = Color.html(String(meta["palette"][key]))
	var roles: Dictionary = meta["roles"]
	var tint_letters := String(roles["tint"])
	var glass_roles: Dictionary = roles["glass"]
	var tire_roles: Dictionary = roles["tire"]
	var glass_colors := _glass_colors()
	var tint := body_color()
	var height := mini(letters.size(), image.get_height())
	for y in height:
		var row := String(letters[y])
		for x in mini(row.length(), image.get_width()):
			var ch := row[x]
			if ch == ".":
				continue
			var src := image.get_pixel(x, y)
			# Шум яркости атласа сохраняем: насколько пиксель светлее «чистого» цвета буквы.
			var key: Color = palette.get(ch, src)
			var shade := clampf(src.get_luminance() / maxf(key.get_luminance(), 0.02), 0.7, 1.3)
			if tint_letters.contains(ch):
				image.set_pixel(x, y, Color(src.r * tint.r, src.g * tint.g, src.b * tint.b, src.a))
			elif glass_roles.has(ch):
				var color: Color = glass_colors[(x + y) % glass_colors.size()] if glass_colors.size() > 2 \
						else glass_colors[0 if glass_roles[ch] == "main" else 1]
				image.set_pixel(x, y, Color(color.r * shade, color.g * shade, color.b * shade, src.a))
			elif tire_roles.has(ch) and wheels == RAINBOW_WHEELS:
				var color := Color.from_hsv(fposmod(float(x + y) / 8.0, 1.0), 0.75, 0.95 if tire_roles[ch] == "tread" else 0.8)
				image.set_pixel(x, y, color)


## Объёмный рисунок (узел Decal модели, только вид). Раньше рисунок ложился на текстуру верхних
## граней: рожицы рвались о лобовое стекло (его пиксели пропускались), а спойлер и ушки, которые
## в оригинале торчат за кузовом, расплющивались полосами по багажнику и капоту.
func _add_decal(model: Node3D) -> void:
	if decal <= 0:
		return
	var key := "%d|%d" % [base, decal]
	if not _decal_meshes.has(key):
		_decal_meshes[key] = _build_decal(model, _load_meta(MODELS[base] + ".json"))
	var mesh: ArrayMesh = _decal_meshes[key]
	if mesh == null:
		return
	var instance := MeshInstance3D.new()
	instance.name = "Decal"
	instance.mesh = mesh
	model.add_child(instance)


func _build_decal(model: Node3D, meta: Dictionary) -> ArrayMesh:
	var sprite := _sprite("other/playerskinpart-print", decal)
	var roof := _area(meta, ROOF_AREAS)
	var body := _area(meta, BODY_AREAS)
	var roof_top := _top_of(model, ROOF_NODES)
	var body_top := _top_of(model, BODY_NODES)
	if sprite == null or roof.size == Vector2.ZERO or is_nan(roof_top):
		return null
	sprite.convert(Image.FORMAT_RGBA8)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if decal == PRINT_SPOILER:
		_add_spoiler(st, sprite, roof, roof_top, body, body_top)
	elif decal == PRINT_EARS:
		_add_ears(st, sprite, roof, roof_top)
	elif decal == PRINT_BANGS:
		var cabin := _box_of(model, ROOF_NODES)
		_add_bangs(st, sprite, roof, roof_top, cabin.position.z, body_top if not is_nan(body_top) else cabin.position.y)
	else:
		_add_sticker(st, sprite, roof, roof_top)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.8
	# Нормали заданы явно, а порядок вершин у граней разный — рисуем обе стороны.
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	st.set_material(material)
	return st.commit()


## Наклейка: каждый пиксель рисунка — кубик на крыше. Рисунок по центру крыши, нос спрайта
## (вправо) — вперёд (−Z), низ спрайта — правый бок (+X).
func _add_sticker(st: SurfaceTool, sprite: Image, roof: Rect2, top: float) -> void:
	var used := sprite.get_used_rect()
	var pixel := minf(STICKER_PIXEL, minf(roof.size.y * 0.9 / used.size.x, roof.size.x * 0.9 / used.size.y))
	var center := roof.get_center()
	for sy in range(used.position.y, used.end.y):
		for sx in range(used.position.x, used.end.x):
			if not _solid(sprite, sx, sy):
				continue
			var color := sprite.get_pixel(sx, sy)
			color.a = 1.0
			var forward := (sx - used.position.x + 0.5 - used.size.x * 0.5) * pixel
			var right := (sy - used.position.y + 0.5 - used.size.y * 0.5) * pixel
			var at := Vector3(center.x + right, top + 0.002, center.y - forward)
			# Боковые грани — только там, где соседа нет (внутри наклейки их не видно).
			var open := {
				Vector3.RIGHT: not _solid(sprite, sx, sy + 1), Vector3.LEFT: not _solid(sprite, sx, sy - 1),
				Vector3.FORWARD: not _solid(sprite, sx + 1, sy), Vector3.BACK: not _solid(sprite, sx - 1, sy),
			}
			_box(st, at, Vector3(pixel, STICKER_THICKNESS, pixel), color, open)


## Спойлер: антикрыло на стойках у кормы — на багажнике, а у фургона (крыша до самой кормы) —
## на крыше. Цвета — светлый и тёмный из кадра оригинала.
func _add_spoiler(st: SurfaceTool, sprite: Image, roof: Rect2, roof_top: float, body: Rect2, body_top: float) -> void:
	var light := Color.WHITE
	var dark := Color.BLACK
	var colors := _sprite_colors(sprite)
	if not colors.is_empty():
		light = colors[colors.size() - 1]
		dark = colors[0]
	var rear := body.end.y
	var mount := body_top
	if is_nan(body_top) or rear - roof.end.y < 0.3:
		rear = roof.end.y
		mount = roof_top
	var width := body.size.x + 0.2
	var wing := Vector3(0.0, mount + 0.34, rear - 0.12)
	_box(st, wing, Vector3(width, 0.07, 0.34), light)
	for side in [-1.0, 1.0]:
		_box(st, Vector3(side * width * 0.5, wing.y - 0.1, wing.z), Vector3(0.06, 0.26, 0.42), dark)
		_box(st, Vector3(side * 0.42, mount, wing.z - 0.02), Vector3(0.08, 0.34, 0.12), dark)


## Ушки: два треугольника у передней кромки крыши, спереди — розовые в светлой рамке, сзади
## и по бокам — светлые; наклонены назад, чтобы розовое было видно камере сверху-сзади.
func _add_ears(st: SurfaceTool, sprite: Image, roof: Rect2, top: float) -> void:
	var inner := Color.HOT_PINK
	var outer := Color.WHITE
	var colors := _sprite_colors(sprite)
	if not colors.is_empty():
		outer = colors[colors.size() - 1]
	for color in colors:
		if color.s > 0.4:
			inner = color
	var size := minf(0.46, roof.size.x * 0.4)
	var tilt := Basis(Vector3.RIGHT, deg_to_rad(35.0))
	var half := 0.06
	var left := Vector3(-size * 0.5, 0.0, 0.0)
	var right := Vector3(size * 0.5, 0.0, 0.0)
	var tip := Vector3(0.0, size, 0.0)
	var front := Vector3(0.0, 0.0, -half)
	var back := Vector3(0.0, 0.0, half)
	var corners := [left, right, tip]
	for side in [-1.0, 1.0]:
		var foot := Vector3(roof.get_center().x + side * (roof.size.x * 0.5 - size * 0.6), top, roof.position.y + 0.14)
		var place := Transform3D(tilt, foot)
		_tri(st, place * (left + front), place * (right + front), place * (tip + front), tilt * Vector3.FORWARD, outer)
		# Розовая серединка чуть впереди рамки.
		var lift := tip * 0.12 + front * 1.2
		_tri(st, place * (left * 0.55 + lift), place * (right * 0.55 + lift), place * (tip * 0.8 + front * 1.2),
				tilt * Vector3.FORWARD, inner)
		_tri(st, place * (left + back), place * (tip + back), place * (right + back), tilt * Vector3.BACK, outer)
		for k in 3:
			var a: Vector3 = corners[k]
			var c: Vector3 = corners[(k + 1) % 3]
			var normal: Vector3 = tilt * ((a + c) * 0.5 - Vector3(0.0, size / 3.0, 0.0)).normalized()
			_quad(st, place * (a + front), place * (c + front), place * (c + back), place * (a + back),
					normal, outer.darkened(0.1))


## Чёлка: пиксели-кубики от передней кромки крыши вперёд и вниз по лобовому стеклу (ступеньками
## по профилю кабины: крыша -> скос стекла -> капот), пряди и обводка — как нарисованы.
## Ширина — по крыше; нос спрайта — вперёд, низ спрайта — правый бок.
func _add_bangs(st: SurfaceTool, sprite: Image, roof: Rect2, roof_top: float, cabin_front: float, body_top: float) -> void:
	var used := sprite.get_used_rect()
	var pixel := minf(STICKER_PIXEL, roof.size.x * 0.95 / used.size.y)
	# Профиль верха машины вдоль оси z: крыша, скос стекла до низа кабины, дальше капот.
	var surface := func(z: float) -> float:
		if z >= roof.position.y:
			return roof_top
		if z <= cabin_front:
			return body_top
		return lerpf(body_top, roof_top, inverse_lerp(cabin_front, roof.position.y, z))
	# Задний край чёлки — на крыше, чуть за её передней кромкой.
	var rear_z := roof.position.y + pixel * 1.5
	for sy in range(used.position.y, used.end.y):
		for sx in range(used.position.x, used.end.x):
			if not _solid(sprite, sx, sy):
				continue
			var color := sprite.get_pixel(sx, sy)
			color.a = 1.0
			var z1 := rear_z - (sx - used.position.x) * pixel
			var z0 := z1 - pixel
			var right := roof.get_center().x + (sy - used.position.y + 0.5 - used.size.y * 0.5) * pixel
			# Кубик от нижней точки поверхности под ним до верхней + толщина: на скосе нет щелей.
			var low: float = minf(surface.call(z0), surface.call(z1))
			var high: float = maxf(surface.call(z0), surface.call(z1))
			var open := {
				Vector3.RIGHT: not _solid(sprite, sx, sy + 1), Vector3.LEFT: not _solid(sprite, sx, sy - 1),
				Vector3.FORWARD: true, Vector3.BACK: true,
			}
			_box(st, Vector3(right, low + 0.002, (z0 + z1) * 0.5), Vector3(pixel, high - low + STICKER_THICKNESS * 1.4, pixel),
					color, open)


static func _solid(sprite: Image, x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < sprite.get_width() and y < sprite.get_height() and sprite.get_pixel(x, y).a > 0.5


## Верх крыши или кузова (areas из .json build_car.py: x вправо, y вперёд, м) в осях модели:
## Rect2 по (x, z) — x вправо, z назад.
static func _area(meta: Dictionary, names: Array) -> Rect2:
	var areas: Dictionary = meta.get("areas", {})
	for area_name in names:
		if areas.has(area_name):
			var a: Array = areas[area_name]
			return Rect2(float(a[0]), -float(a[3]), float(a[1]) - float(a[0]), float(a[3]) - float(a[2]))
	return Rect2()


## Высота верха узла модели (по его сетке); узла нет — NAN.
static func _top_of(model: Node3D, names: Array) -> float:
	var box := _box_of(model, names)
	return box.end.y if box.has_volume() else NAN


## Габариты сетки узла модели в осях модели; узла нет — пустой AABB.
static func _box_of(model: Node3D, names: Array) -> AABB:
	for node_name in names:
		var mesh := model.find_child(node_name, true, false) as MeshInstance3D
		if mesh == null or mesh.mesh == null:
			continue
		var xf := Transform3D.IDENTITY
		var node: Node = mesh
		while node != null and node != model:
			if node is Node3D:
				xf = (node as Node3D).transform * xf
			node = node.get_parent()
		return xf * mesh.mesh.get_aabb()
	return AABB()


## Непрозрачные цвета картинки от тёмного к светлому, без повторов.
static func _sprite_colors(sprite: Image) -> Array[Color]:
	var seen := {}
	var colors: Array[Color] = []
	for y in sprite.get_height():
		for x in sprite.get_width():
			var color := sprite.get_pixel(x, y)
			if color.a > 0.5 and not seen.has(color.to_html(false)):
				seen[color.to_html(false)] = true
				colors.append(Color(color, 1.0))
	colors.sort_custom(func(a: Color, c: Color) -> bool: return a.get_luminance() < c.get_luminance())
	return colors


## Кубик: низ по центру в center, size — размеры; open — какие боковые грани рисовать
## (нет в словаре — рисовать); дно не рисуется.
static func _box(st: SurfaceTool, center: Vector3, size: Vector3, color: Color, open: Dictionary = {}) -> void:
	var lo := center - Vector3(size.x * 0.5, 0.0, size.z * 0.5)
	var hi := center + Vector3(size.x * 0.5, size.y, size.z * 0.5)
	_quad(st, Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z),
			Vector3.UP, color)
	var sides := {
		Vector3.RIGHT: [Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(hi.x, hi.y, lo.z)],
		Vector3.LEFT: [Vector3(lo.x, lo.y, hi.z), Vector3(lo.x, lo.y, lo.z), Vector3(lo.x, hi.y, lo.z), Vector3(lo.x, hi.y, hi.z)],
		Vector3.FORWARD: [Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(lo.x, hi.y, lo.z)],
		Vector3.BACK: [Vector3(hi.x, lo.y, hi.z), Vector3(lo.x, lo.y, hi.z), Vector3(lo.x, hi.y, hi.z), Vector3(hi.x, hi.y, hi.z)],
	}
	for normal: Vector3 in sides:
		if open.get(normal, true):
			var q: Array = sides[normal]
			# Бока чуть темнее верха — объём читается и в тени.
			_quad(st, q[0], q[1], q[2], q[3], normal, color.darkened(0.15))


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, color: Color) -> void:
	_tri(st, a, b, c, normal, color)
	_tri(st, a, c, d, normal, color)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3, color: Color) -> void:
	for v in [a, b, c]:
		st.set_color(color)
		st.set_normal(normal)
		st.add_vertex(v)

## Цвета стёкол из кадра оригинала: [основной, блик] или радужный ряд (последний кадр).
func _glass_colors() -> Array[Color]:
	var sprite := _sprite("other/playerskinpart-glass", glass)
	var colors: Array[Color] = []
	if sprite != null:
		for y in sprite.get_height():
			for x in sprite.get_width():
				var color := sprite.get_pixel(x, y)
				if color.a > 0.5:
					colors.append(color)
	if colors.is_empty():
		return [Color.html("#2f6fd6"), Color.html("#8fd0ff")]
	# Много разных оттенков — радужные стёкла: полосы по всем цветам кадра.
	var hues := {}
	for color in colors:
		if color.s > 0.4 and color.v > 0.3:
			hues[floori(color.h * 6.0)] = true
	if hues.size() >= 4:
		colors.sort_custom(func(a: Color, c: Color) -> bool: return a.h < c.h)
		return colors
	colors.sort_custom(func(a: Color, c: Color) -> bool: return a.get_luminance() < c.get_luminance())
	return [colors[int(colors.size() * 0.4)], colors[colors.size() - 1]]


static func _sprite(prefix: String, index: int) -> Image:
	var texture := load("%s%s-%03d.png" % [SPRITES, prefix, index]) as Texture2D
	if texture == null:
		return null
	var image := texture.get_image()
	if image != null and image.is_compressed():
		image.decompress()
	return image


static func _load_meta(path: String) -> Dictionary:
	if not _meta.has(path):
		var json := load(path) as JSON
		_meta[path] = json.data if json != null and json.data is Dictionary else {}
	return _meta[path]


static func _first_material(node: Node) -> Material:
	var mesh := node as MeshInstance3D
	if mesh != null and mesh.mesh != null and mesh.mesh.get_surface_count() > 0:
		return mesh.get_active_material(0)
	for child in node.get_children():
		var found := _first_material(child)
		if found != null:
			return found
	return null


static func _apply_material(node: Node, material: Material) -> void:
	var mesh := node as MeshInstance3D
	if mesh != null and mesh.mesh != null:
		for i in mesh.mesh.get_surface_count():
			mesh.set_surface_override_material(i, material)
	for child in node.get_children():
		_apply_material(child, material)


static func _wheels_of(node: Node) -> Array[Node3D]:
	var result: Array[Node3D] = []
	for child in node.get_children():
		if child is Node3D and String(child.name).begins_with("Wheel_"):
			result.append(child)
		result.append_array(_wheels_of(child))
	return result
