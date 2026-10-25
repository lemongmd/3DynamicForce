class_name CarSkin
extends RefCounted
## Скин машины как в оригинале (MenuSkin, SpawnPlayer): цвет кузова — 4 уровня на канал
## (Player.set-default-color(R·85, G·85, B·85)), кузов (3 формы + секретный танк), стёкла (11),
## рисунок (9), колёса (4). Строка скина — как переменная skin оригинала: цифры
## «R G B 0 кузов стёкла рисунок колёса» (четвёртая — 0, у оригинала тоже), напр. «33300000».
##
## Модели — blender/build_car.py: кузов нарисован в серых тонах, рядом .json с буквами атласа
## (какая часть машины в каждом пикселе). paint() собирает из них текстуру скина: кузов умножается
## на цвет, стёкла перекрашиваются в цвета кадра стёкол оригинала, рисунок оригинала (вид сверху)
## кладётся на верх кузова и крышу, колёса — по кадру колёс (размер и цвет).

const LEVELS := 4
## Обычные кузова (0..2); кузов TANK — секретный танк (в оригинале — если зажать кнопку кузова).
const BASES := 3
const TANK := 3
const GLASSES := 11
const PRINTS := 9
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
	if decal > 0:
		_paint_decal(image, meta, tint_letters)


## Рисунок оригинала (вид сверху 24×16, нос — вправо) на верхние грани: каждый пиксель грани —
## точка машины в метрах, она же — пиксель спрайта (кузов спрайта player-base-000 = кузов модели).
func _paint_decal(image: Image, meta: Dictionary, tint_letters: String) -> void:
	var sprite := _sprite("other/playerskinpart-print", decal)
	var body_sprite := _sprite("main/player-base", 0)
	if sprite == null or body_sprite == null:
		return
	var body_px := body_sprite.get_used_rect()
	var areas: Dictionary = meta["areas"]
	var extent: Array = areas.values()[0]
	var letters: Array = meta["letters"]
	for area_name in areas:
		var rect: Array = meta["rects"][area_name]
		var area: Array = areas[area_name]
		for py in int(rect[3]):
			for px in int(rect[2]):
				var ax := int(rect[0]) + px
				var ay := int(rect[1]) + py
				if not tint_letters.contains(String(letters[ay])[ax]):
					continue
				# Пиксель грани -> метры (x — вправо, y — вперёд; строка 0 — перед).
				var mx := lerpf(float(area[0]), float(area[1]), (px + 0.5) / float(rect[2]))
				var my := lerpf(float(area[3]), float(area[2]), (py + 0.5) / float(rect[3]))
				# Метры -> пиксель спрайта: нос вправо, правый бок машины — вниз.
				var sx := body_px.position.x + inverse_lerp(float(extent[2]), float(extent[3]), my) * body_px.size.x
				var sy := body_px.position.y + inverse_lerp(float(extent[0]), float(extent[1]), mx) * body_px.size.y
				var spx := clampi(floori(sx), 0, sprite.get_width() - 1)
				var spy := clampi(floori(sy), 0, sprite.get_height() - 1)
				var color := sprite.get_pixel(spx, spy)
				if color.a > 0.5:
					image.set_pixel(ax, ay, Color(color.r, color.g, color.b, 1.0))


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
