extends SceneTree
## Пиксельные картинки хэллоуинского меню (HalloweenBackground) -> res://assets/textures/menu_halloween/:
##   moon.png 64×64 — полная луна с кратерами; moon_glow.png 128×128 — ореол (белый, ступенями);
##   tree_0..2.png — голые корявые деревья-силуэты с лунной каймой справа;
##   hills.png 256×64 — дальние холмы и ближняя земля (бесшовно по ширине);
##   cliff.png 96×80 — скала справа, на ней дерево на фоне луны;
##   coffin_box.png, coffin_lid.png 16×32 — гроб стоймя: короб с тёмным нутром и крышка с крестом;
##   tomb_0..2.png 14×18 — надгробия (полукруглое, крест, покосившаяся плита);
##   pumpkin.png 14×12 — тыква-фонарь; bat_0.png, bat_1.png 11×6 — летучая мышь, два взмаха;
##   cloud.png 112×24 — облако, подсвеченное луной сверху; fog.png 128×24 — туман (бесшовно);
##   slime.png 28×6 — лужа гнили (светится зелёным);
##   logo.png 160×48 — логотип (assets/image.png) в тыквенных цветах, буквы «плавятся» потёками;
##   menustartbutton-000..009.png, settings_button.png — кнопки-кресты меню: фиолетовые
##     с тыквенными уголками и значками (перекраска кадров оригинала и кнопки Mace Dev).
## Всё рисуется кодом (многоугольники, круги, линии); перерисованные вручную картинки
## (assets/hand_drawn.txt) не перезаписываются.
##
## Запуск (из корня проекта):
##   godot --headless --path . -s res://scripts/tools/build_halloween_menu.gd

const HandDrawn := preload("res://scripts/tools/hand_drawn.gd")
const OUT_DIR := "res://assets/textures/menu_halloween/"

## Силуэты (почти чёрный фиолетовый) и лунная кайма.
const INK := Color8(11, 4, 16)
const RIM := Color8(52, 28, 70)
const FAR_HILL := Color8(31, 11, 43)
const FAR_RIM := Color8(58, 26, 74)
const MOON := Color8(246, 241, 199)
const MOON_MID := Color8(226, 217, 160)
const MOON_DARK := Color8(200, 187, 124)
const MOON_DEEP := Color8(179, 164, 106)
const WOOD := Color8(74, 42, 42)
const WOOD_DARK := Color8(36, 16, 20)
const WOOD_LIGHT := Color8(110, 66, 56)
const BRASS := Color8(176, 140, 90)
const STONE := Color8(59, 51, 72)
const STONE_LIGHT := Color8(93, 84, 112)
const STONE_DARK := Color8(34, 28, 44)
const MOSS := Color8(52, 96, 40)
const ORANGE := Color8(242, 122, 26)
const ORANGE_LIGHT := Color8(255, 168, 60)
const ORANGE_DARK := Color8(160, 62, 18)
const STEM := Color8(70, 96, 30)
const GLOW := Color8(255, 226, 92)
const SLIME := Color8(124, 255, 74)
const SLIME_MID := Color8(63, 174, 42)
const SLIME_DARK := Color8(29, 90, 26)
const CLOUD := Color8(44, 18, 62)
const CLOUD_LIT := Color8(92, 52, 112)
const FOG := Color8(150, 120, 176)

## Перекраска кнопок-крестов: красное -> фиолетовое, жёлтое и оранжевое -> тыквенное.
const BUTTON_COLORS := {"a00121": Color8(61, 18, 87), "f70f07": Color8(123, 47, 168), "f07039": Color8(176, 106, 216),
		"ffff00": Color8(255, 181, 46), "ff9f00": Color8(232, 96, 28)}
## Логотип: чёрное -> чёрно-фиолетовое, жёлтое и оранжевое -> тыквенное.
const LOGO_COLORS := {"000000": Color8(18, 3, 28), "ffff00": Color8(255, 196, 72), "ff7f00": Color8(240, 100, 20)}

var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	_rng.seed = 1031
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_save(_moon(), "moon")
	_save(_glow(128), "moon_glow")
	_save(_tree(Vector2i(100, 112), 7.0, 34.0, 4, 11), "tree_0")
	_save(_tree(Vector2i(76, 84), 5.0, 26.0, 4, 23), "tree_1")
	_save(_tree(Vector2i(124, 128), 8.0, 40.0, 5, 47), "tree_2")
	_save(_hills(), "hills")
	_save(_cliff(), "cliff")
	_save(_coffin_box(), "coffin_box")
	_save(_coffin_lid(), "coffin_lid")
	for kind in 3:
		_save(_tomb(kind), "tomb_%d" % kind)
	_save(_pumpkin(), "pumpkin")
	_save(_bat(false), "bat_0")
	_save(_bat(true), "bat_1")
	_save(_cloud(), "cloud")
	_save(_fog(), "fog")
	_save(_slime(), "slime")
	_save(_logo(), "logo")
	for frame in 10:
		var file := "menustartbutton-%03d" % frame
		_save(_recolor("res://assets/original/textures/menu/%s.png" % file, BUTTON_COLORS), file)
	_save(_recolor("res://assets/textures/ui/settings_button.png", BUTTON_COLORS), "settings_button")
	quit()


func _save(image: Image, file_name: String) -> void:
	HandDrawn.save_png(image, "%s%s.png" % [OUT_DIR, file_name])


# --------------------------------------------------------------------------
# Простые фигуры
# --------------------------------------------------------------------------

static func _new(w: int, h: int) -> Image:
	return Image.create(w, h, false, Image.FORMAT_RGBA8)


static func _put(image: Image, x: int, y: int, color: Color) -> void:
	if x >= 0 and y >= 0 and x < image.get_width() and y < image.get_height():
		image.set_pixel(x, y, color)


## Закрашивает многоугольник (центры пикселей внутри).
static func _poly(image: Image, points: Array, color: Color) -> void:
	var polygon := PackedVector2Array(points)
	var box := Rect2(polygon[0], Vector2.ZERO)
	for p in polygon:
		box = box.expand(p)
	for y in range(floori(box.position.y), ceili(box.end.y) + 1):
		for x in range(floori(box.position.x), ceili(box.end.x) + 1):
			if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), polygon):
				_put(image, x, y, color)


static func _disc(image: Image, center: Vector2, radius: float, color: Color) -> void:
	for y in range(floori(center.y - radius), ceili(center.y + radius) + 1):
		for x in range(floori(center.x - radius), ceili(center.x + radius) + 1):
			if Vector2(x + 0.5, y + 0.5).distance_to(center) <= radius:
				_put(image, x, y, color)


## Толстая линия: круги вдоль отрезка, толщина плавно меняется от w0 до w1.
static func _line(image: Image, a: Vector2, b: Vector2, w0: float, w1: float, color: Color) -> void:
	var steps := maxi(ceili(a.distance_to(b) * 2.0), 1)
	for i in steps + 1:
		var t := float(i) / steps
		_disc(image, a.lerp(b, t), maxf(lerpf(w0, w1, t) * 0.5, 0.5), color)


## Лунная кайма: пиксели фигуры цвета body, у которых сосед в стороне луны пуст, а с другой
## стороны — тоже фигура (тонкие веточки в 1 px каймой не светятся целиком).
static func _rim(image: Image, body: Color, rim: Color, toward: Array) -> void:
	var marks: Array[Vector2i] = []
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y) != body:
				continue
			for d: Vector2i in toward:
				var n := Vector2i(x, y) + d
				var back := Vector2i(x, y) - d
				var outside := n.x < 0 or n.y < 0 or n.x >= image.get_width() or n.y >= image.get_height()
				var thick := back.x >= 0 and back.y >= 0 and back.x < image.get_width() and back.y < image.get_height() \
						and image.get_pixel(back.x, back.y).a > 0.5
				if thick and (outside or image.get_pixel(n.x, n.y).a < 0.5):
					marks.append(Vector2i(x, y))
					break
	for m in marks:
		image.set_pixel(m.x, m.y, rim)


# --------------------------------------------------------------------------
# Картинки
# --------------------------------------------------------------------------

func _moon() -> Image:
	var size := 64
	var image := _new(size, size)
	var c := Vector2(32, 32)
	_disc(image, c, 30.0, MOON)
	# Тень терминатора снизу слева: две ступени.
	for y in size:
		for x in size:
			var p := Vector2(x + 0.5, y + 0.5)
			if p.distance_to(c) > 30.0:
				continue
			if p.distance_to(c + Vector2(7, -7)) > 31.0:
				image.set_pixel(x, y, MOON_DARK)
			elif p.distance_to(c + Vector2(4, -4)) > 30.0:
				image.set_pixel(x, y, MOON_MID)
	# «Моря» и кратеры.
	for spot in [[Vector2(22, 24), 7.0], [Vector2(38, 18), 5.0], [Vector2(42, 38), 8.0], [Vector2(24, 44), 4.0]]:
		_disc(image, spot[0], spot[1], MOON_MID)
	for crater in [[Vector2(20, 22), 3.0], [Vector2(44, 40), 3.5], [Vector2(36, 14), 2.0], [Vector2(28, 50), 2.5],
			[Vector2(50, 26), 2.0], [Vector2(14, 36), 2.0]]:
		_disc(image, crater[0], crater[1], MOON_DEEP)
		_disc(image, crater[0] + Vector2(0.8, 0.8), crater[1] - 1.0, MOON_DARK)
	return image


## Ореол: белый круг ступенями прозрачности (цвет и сложение — у узла).
func _glow(size: int) -> Image:
	var image := _new(size, size)
	var c := Vector2(size, size) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c) / (size * 0.5)
			if d < 1.0:
				var a := snappedf(pow(1.0 - d, 2.0), 0.125)
				image.set_pixel(x, y, Color(1, 1, 1, a))
	return image


## Голое корявое дерево: ствол с корнями, ветки ветвятся, на концах — крючья-сучки.
func _tree(size: Vector2i, trunk: float, height: float, depth: int, seed_value: int) -> Image:
	_rng.seed = seed_value
	var image := _new(size.x, size.y)
	var base := Vector2(size.x * 0.5, size.y - 1.0)
	# Корни.
	_poly(image, [base + Vector2(-trunk * 1.6, 1), base + Vector2(-trunk * 0.5, -trunk * 1.2),
			base + Vector2(trunk * 0.5, -trunk * 1.2), base + Vector2(trunk * 1.7, 1)], INK)
	_branch(image, base, -PI * 0.5 + _rng.randf_range(-0.12, 0.12), height, trunk, depth)
	_rim(image, INK, RIM, [Vector2i(1, 0), Vector2i(1, -1)])
	return image


func _branch(image: Image, from: Vector2, angle: float, length: float, width: float, depth: int) -> void:
	# Ветка слегка изгибается: две половины с разным углом.
	var bend := _rng.randf_range(-0.35, 0.35)
	var mid := from + Vector2.from_angle(angle) * length * 0.5
	var to := mid + Vector2.from_angle(angle + bend) * length * 0.5
	_line(image, from, mid, width, width * 0.85, INK)
	_line(image, mid, to, width * 0.85, width * 0.7, INK)
	if depth <= 0 or width < 1.0:
		# Сучок-крючок на конце.
		_line(image, to, to + Vector2.from_angle(angle + bend + _rng.randf_range(0.8, 1.4) * signf(bend + 0.01)) * 3.0,
				1.0, 1.0, INK)
		return
	var count := 3 if depth >= 3 and _rng.randf() < 0.5 else 2
	for i in count:
		var spread := _rng.randf_range(0.35, 0.8) * (1.0 if i % 2 == 0 else -1.0)
		var child := clampf(angle + bend + spread, -PI + 0.2, -0.2)
		var start := mid.lerp(to, _rng.randf_range(0.4, 1.0)) if i > 0 else to
		_branch(image, start, child, length * _rng.randf_range(0.62, 0.78), width * 0.72, depth - 1)


## Дальние холмы (выше, светлее) и ближняя земля с травинками; бесшовно по ширине.
func _hills() -> Image:
	var w := 256
	var h := 64
	var image := _new(w, h)
	for x in w:
		var t := TAU * x / w
		var far := 20.0 + 7.0 * sin(t + 0.6) + 4.0 * sin(3.0 * t + 1.3) + 2.0 * sin(7.0 * t)
		var near := 46.0 + 2.0 * sin(5.0 * t + 0.4) + 1.2 * sin(11.0 * t + 2.0)
		for y in h:
			if y >= near:
				image.set_pixel(x, y, INK)
			elif y >= far:
				image.set_pixel(x, y, FAR_RIM if y < far + 1.0 else FAR_HILL)
	# Травинки и кресты далёкого кладбища на ближней земле.
	_rng.seed = 7
	for x in w:
		var t := TAU * x / w
		var near := ceili(46.0 + 2.0 * sin(5.0 * t + 0.4) + 1.2 * sin(11.0 * t + 2.0))
		if _rng.randf() < 0.35:
			for k in _rng.randi_range(1, 3):
				_put(image, x, near - 1 - k, INK)
	for x: int in [40, 46, 150, 214]:
		var t := TAU * x / w
		var far := ceili(20.0 + 7.0 * sin(t + 0.6) + 4.0 * sin(3.0 * t + 1.3) + 2.0 * sin(7.0 * t))
		for k in 5:
			_put(image, x, far - k, FAR_HILL)
		_put(image, x - 1, far - 3, FAR_HILL)
		_put(image, x + 1, far - 3, FAR_HILL)
	return image


## Скала: зубчатый каменный выступ, наверху площадка под дерево (x ≈ 36..56, y ≈ 20).
func _cliff() -> Image:
	var image := _new(96, 80)
	_poly(image, [Vector2(0, 80), Vector2(4, 64), Vector2(12, 56), Vector2(16, 44), Vector2(24, 36),
			Vector2(28, 26), Vector2(36, 21), Vector2(56, 20), Vector2(62, 25), Vector2(66, 34),
			Vector2(74, 40), Vector2(80, 52), Vector2(88, 60), Vector2(96, 66), Vector2(96, 80)], INK)
	# Трещины.
	_line(image, Vector2(44, 30), Vector2(40, 44), 1.0, 1.0, RIM)
	_line(image, Vector2(60, 46), Vector2(66, 58), 1.0, 1.0, RIM)
	_rim(image, INK, RIM, [Vector2i(0, -1), Vector2i(1, -1)])
	return image


const COFFIN := [Vector2(5, 0), Vector2(11, 0), Vector2(16, 8), Vector2(12, 32), Vector2(4, 32), Vector2(0, 8)]


## Короб гроба стоймя: доски по краю, внутри темнота (в ней светятся глаза — HalloweenBackground).
func _coffin_box() -> Image:
	var image := _new(16, 32)
	_poly(image, COFFIN, WOOD_DARK)
	var inner := []
	for p: Vector2 in COFFIN:
		inner.append(p.lerp(Vector2(8, 15), 0.22))
	_poly(image, inner, Color8(6, 2, 8))
	return image


func _coffin_lid() -> Image:
	var image := _new(16, 32)
	_poly(image, COFFIN, WOOD)
	# Доски: тёмные швы; кайма слева-сверху; крест.
	for y in [10, 21]:
		for x in 16:
			if image.get_pixel(x, y) == WOOD:
				image.set_pixel(x, y, WOOD_DARK)
	_rim(image, WOOD, WOOD_LIGHT, [Vector2i(1, 0), Vector2i(0, -1)])
	for y in range(6, 19):
		_put(image, 8, y, BRASS)
	for x in range(5, 12):
		_put(image, x, 10, BRASS)
	_put(image, 8, 18, WOOD_DARK)
	return image


func _tomb(kind: int) -> Image:
	var image := _new(14, 18)
	match kind:
		0:
			_poly(image, [Vector2(2, 18), Vector2(2, 6), Vector2(12, 6), Vector2(12, 18)], STONE)
			_disc(image, Vector2(7, 6.5), 5.0, STONE)
			# «RIP» — три чёрточки.
			for x in [4, 6, 8]:
				_put(image, x, 8, STONE_DARK)
				_put(image, x, 9, STONE_DARK)
		1:
			_poly(image, [Vector2(5, 18), Vector2(5, 0), Vector2(9, 0), Vector2(9, 18)], STONE)
			_poly(image, [Vector2(1, 4), Vector2(13, 4), Vector2(13, 8), Vector2(1, 8)], STONE)
		_:
			_poly(image, [Vector2(1, 18), Vector2(4, 3), Vector2(13, 5), Vector2(11, 18)], STONE)
			_line(image, Vector2(7, 7), Vector2(6, 12), 1.0, 1.0, STONE_DARK)
	_rim(image, STONE, STONE_LIGHT, [Vector2i(1, 0), Vector2i(0, -1)])
	# Мох у земли.
	for x in 14:
		if image.get_pixel(x, 17).a > 0.5 and (x * 7) % 3 != 0:
			image.set_pixel(x, 17, MOSS)
	return image


func _pumpkin() -> Image:
	var image := _new(14, 12)
	for spot in [[Vector2(4, 7.5), 3.6], [Vector2(10, 7.5), 3.6], [Vector2(7, 7.5), 4.2]]:
		_disc(image, spot[0], spot[1], ORANGE)
	for y in range(4, 12):
		for x in [5, 9]:
			if image.get_pixel(x, y).a > 0.5:
				image.set_pixel(x, y, ORANGE_DARK)
	_rim(image, ORANGE, ORANGE_LIGHT, [Vector2i(1, 0), Vector2i(0, -1)])
	_poly(image, [Vector2(6, 4), Vector2(7, 0), Vector2(9, 0), Vector2(8, 4)], STEM)
	# Рожица светится.
	for p in [Vector2i(4, 6), Vector2i(5, 6), Vector2i(9, 6), Vector2i(10, 6), Vector2i(5, 7), Vector2i(9, 7),
			Vector2i(4, 9), Vector2i(5, 10), Vector2i(6, 9), Vector2i(7, 10), Vector2i(8, 9), Vector2i(9, 10), Vector2i(10, 9)]:
		_put(image, p.x, p.y, GLOW)
	return image


func _bat(down: bool) -> Image:
	var rows := [
		"X.........X",
		"XX.......XX",
		".XXX.X.XXX.",
		"...XXXXX...",
		".....X.....",
		"...........",
	] if not down else [
		"...........",
		".....X.....",
		"...XXXXX...",
		".XXXXXXXXX.",
		"XX..X.X..XX",
		"X.........X",
	]
	var image := _new(11, 6)
	for y in rows.size():
		for x in rows[y].length():
			if rows[y][x] == "X":
				image.set_pixel(x, y, INK)
	return image


func _cloud() -> Image:
	var image := _new(112, 24)
	_rng.seed = 5
	for i in 14:
		var c := Vector2(_rng.randf_range(12, 100), _rng.randf_range(12, 17))
		_disc(image, c, _rng.randf_range(4.0, 8.5) * (1.0 - absf(c.x - 56.0) / 90.0), CLOUD)
	_rim(image, CLOUD, CLOUD_LIT, [Vector2i(0, -1), Vector2i(0, -2)])
	return image


## Туман: размытые полосы ступенчатой прозрачности, бесшовно по ширине.
func _fog() -> Image:
	var w := 128
	var h := 24
	var image := _new(w, h)
	for y in h:
		for x in w:
			var t := TAU * x / w
			var band := 0.5 + 0.25 * sin(2.0 * t + y * 0.4) + 0.25 * sin(5.0 * t - y * 0.25 + 1.0)
			var fade := sin(PI * float(y) / h)
			var a := snappedf(clampf(band * fade * 0.55, 0.0, 1.0), 0.125)
			if a > 0.0:
				image.set_pixel(x, y, Color(FOG, a))
	return image


func _slime() -> Image:
	var image := _new(28, 6)
	_poly(image, [Vector2(2, 6), Vector2(4, 2), Vector2(12, 0), Vector2(22, 1), Vector2(27, 4), Vector2(26, 6)], SLIME_MID)
	_rim(image, SLIME_MID, SLIME, [Vector2i(0, -1)])
	for x in [6, 7, 16, 21]:
		_put(image, x, 3, SLIME)
	for x in 28:
		if image.get_pixel(x, 5).a > 0.5:
			image.set_pixel(x, 5, SLIME_DARK)
	return image


## Картинка с заменой цветов (ключ — «rrggbb» без альфы); прозрачность сохраняется.
static func _recolor(res_path: String, colors: Dictionary) -> Image:
	var image := Image.load_from_file(ProjectSettings.globalize_path(res_path))
	image.convert(Image.FORMAT_RGBA8)
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			var key := c.to_html(false)
			if c.a > 0.0 and colors.has(key):
				var to: Color = colors[key]
				image.set_pixel(x, y, Color(to, c.a))
	return image


## Логотип в тыквенных цветах; снизу у букв — потёки с каплями (холст выше на 8 px).
func _logo() -> Image:
	var src := _recolor("res://assets/image.png", LOGO_COLORS)
	var image := _new(src.get_width(), src.get_height() + 8)
	image.blit_rect(src, Rect2i(Vector2i.ZERO, src.get_size()), Vector2i.ZERO)
	var outline: Color = LOGO_COLORS["000000"]
	var goo: Color = LOGO_COLORS["ff7f00"]
	_rng.seed = 31
	var x := 6
	while x < image.get_width() - 4:
		# Низ буквы в этом столбце: последний пиксель заливки (не обводки).
		var bottom := -1
		for y in src.get_height():
			var c := src.get_pixel(x, y)
			if c.a > 0.5 and c != outline:
				bottom = y
		if bottom >= 0 and _rng.randf() < 0.55:
			var length := _rng.randi_range(2, 7)
			for y in range(bottom, bottom + length):
				for dx in [-1, 2]:
					if image.get_pixel(x + dx, y).a < 0.5:
						image.set_pixel(x + dx, y, outline)
				image.set_pixel(x, y, goo)
				image.set_pixel(x + 1, y, goo)
			var tip := Vector2(x + 1, bottom + length + 0.5)
			_disc(image, tip, 2.0, outline)
			_disc(image, tip, 1.2, goo)
			x += _rng.randi_range(9, 16)
		else:
			x += 3
	return image
