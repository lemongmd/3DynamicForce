extends SceneTree
## Картинки нашего предмета «Помидор» (бросок на расстояние) в стиле предметов оригинала
## -> res://assets/textures/items/:
##   curitem_tomato.png 20×16 — иконка в слоте (как curitem-* оригинала: контур, блик);
##   tomato_splat.png 32×32 — клякса на дороге для остальных: с розовой обводкой «опасно,
##     парируй», как у чужих бананов оригинала (цвет обводки берётся из droppedbanana-000);
##   tomato_splat_own.png — та же клякса без обводки (свою видит хозяин);
##   tomato_ball.png 40×20 — развёртка летящего помидора (шар, UV SphereMesh: u — по кругу,
##     v — сверху вниз): неглубокие бороздки у хвостика, тёмный низ, сверху крупная звёздочка
##     чашелистиков (блик даёт глянцевый материал, не картинка);
##   spine_needle.png 96×6 — след «Шипов» шилом: цвета рядов — из spinetrail-000 оригинала
##     (1×6, в оригинале растянута на 320 px без кончика — шило выглядело обрезанным), спереди
##     острый кончик на 14 px, сзади — рукоять с тёмными кольцами.
##
## Запуск (из корня проекта):
##   godot --headless --path . -s res://scripts/tools/build_item_textures.gd

const HandDrawn := preload("res://scripts/tools/hand_drawn.gd")
const OUT_DIR := "res://assets/textures/items/"
const BANANA := "res://assets/original/textures/other/droppedbanana-000.png"
const SPINE_TRAIL := "res://assets/original/textures/other/spinetrail-000.png"
const OUTLINE := Color8(20, 6, 12)
const RED := Color8(228, 36, 40)
const RED_DARK := Color8(160, 18, 30)
const RED_LIGHT := Color8(255, 120, 100)
const GREEN := Color8(60, 190, 60)
const GREEN_DARK := Color8(24, 110, 40)
const SEED := Color8(255, 210, 90)


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_save(_icon(), "curitem_tomato")
	var pink := _banana_pink()
	_save(_splat(pink), "tomato_splat")
	_save(_splat(Color(0, 0, 0, 0)), "tomato_splat_own")
	_save(_ball(), "tomato_ball")
	_save(_spine_needle(), "spine_needle")
	quit()


## Шило 96×6 (x = 0 — сзади, 95 — кончик): ряды цветами оригинала, кончик сужается до точки,
## кромка кончика — тёмная, по середине — светлая грань; сзади — рукоять.
func _spine_needle() -> Image:
	var source := (load(SPINE_TRAIL) as Texture2D).get_image()
	if source.is_compressed():
		source.decompress()
	var width := 96
	var height := source.get_height()
	var tip := 14
	var handle := 10
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	var inside := func(x: int, y: int) -> bool:
		if x < 0 or x >= width or y < 0 or y >= height:
			return false
		var half := height * 0.5
		if x >= width - tip:
			half *= float(width - x) / tip
		elif x < 2:
			half -= 1.0
		return absf(y + 0.5 - height * 0.5) < half
	var dark := source.get_pixel(0, 3)
	var light := source.get_pixel(0, 2)
	for y in height:
		for x in width:
			if not inside.call(x, y):
				continue
			var color := source.get_pixel(0, y)
			if x >= width - tip:
				# Кончик: кромка тёмная, середина — светлая грань (блестит).
				if not inside.call(x, y - 1) or not inside.call(x, y + 1):
					color = dark
				elif y == height / 2 - 1:
					color = light
			elif x < handle:
				# Рукоять: темнее, два кольца.
				color = color.darkened(0.35)
				if x == 3 or x == handle - 1:
					color = dark.darkened(0.3)
			image.set_pixel(x, y, color)
	return image


## Палитра иконки Mace Dev.
const BALL_RED := Color8(229, 55, 64)
const BALL_RED_DARK := Color8(190, 35, 51)
const BALL_RED_DEEP := Color8(143, 24, 45)
const BALL_GREEN := Color8(106, 199, 80)
const BALL_GREEN_DARK := Color8(51, 152, 75)
const BALL_GREEN_DEEP := Color8(19, 76, 76)
const BALL_GREEN_LIGHT := Color8(215, 246, 114)
const BALL_LOBES := 6
const BALL_SEPALS := 5


## Развёртка шара 40×20: бороздки у хвостика, низ, звёздочка сверху.
func _ball() -> Image:
	var width := 40
	var height := 20
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	var sepal := func(x: int, y: int) -> bool:
		var u := (float(posmod(x, width)) + 0.5) / width
		var v := (float(y) + 0.5) / height
		var phase := fposmod(u * BALL_SEPALS + 0.1, 1.0)
		var tip := 1.0 - absf(phase - 0.5) * 2.0
		return v < 0.05 + 0.42 * pow(tip, 1.3)
	for y in height:
		var v := (y + 0.5) / height
		for x in width:
			var color := BALL_RED
			# Бороздки между дольками — только у хвостика (у настоящего помидора ниже он гладкий).
			var groove := int(x * BALL_LOBES / width) != int(posmod(x - 1, width) * BALL_LOBES / width)
			if groove and v < 0.42:
				color = BALL_RED_DEEP if v < 0.25 else BALL_RED_DARK
			elif v > 0.8:
				color = BALL_RED_DARK
			if v > 0.92:
				color = BALL_RED_DEEP
			if sepal.call(x, y):
				color = BALL_GREEN
				if not sepal.call(x, y + 1) or not sepal.call(x - 1, y) or not sepal.call(x + 1, y):
					color = BALL_GREEN_DARK
				if y == 0:
					color = BALL_GREEN_DEEP
				elif y == 1 and not sepal.call(x, y + 2):
					color = BALL_GREEN_DARK
				if y == 2 and sepal.call(x, y + 3) and sepal.call(x - 1, y) and sepal.call(x + 1, y):
					color = BALL_GREEN_LIGHT
			image.set_pixel(x, y, color)
	return image


## Иконка: круглый помидор с бликом, сверху — зелёная звёздочка листьев.
func _icon() -> Image:
	var image := Image.create(20, 16, false, Image.FORMAT_RGBA8)
	var center := Vector2(10.0, 9.5)
	for y in 16:
		for x in 20:
			var d := Vector2(x + 0.5, y + 0.5) - center
			var r := Vector2(d.x / 6.5, d.y / 5.5).length()
			if r > 1.0:
				continue
			var color := RED
			if r > 0.82:
				color = OUTLINE
			elif d.x + d.y > 4.0:
				color = RED_DARK
			elif Vector2(x, y).distance_to(Vector2(7, 7)) < 1.6:
				color = RED_LIGHT
			image.set_pixel(x, y, color)
	var leaves := [Vector2i(9, 3), Vector2i(10, 3), Vector2i(8, 4), Vector2i(9, 4), Vector2i(10, 4),
			Vector2i(11, 4), Vector2i(7, 5), Vector2i(12, 5), Vector2i(10, 2)]
	for point: Vector2i in leaves:
		image.set_pixelv(point, GREEN if point.y < 5 else GREEN_DARK)
	image.set_pixel(10, 1, GREEN_DARK)
	return image


## Клякса: неровное красное пятно с брызгами и семечками; outline — обводка (прозрачная — нет).
func _splat(outline: Color) -> Image:
	var size := 32
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var blobs := [Vector3(16, 16, 9), Vector3(10, 12, 5), Vector3(22, 11, 5), Vector3(21, 22, 6),
			Vector3(9, 21, 4), Vector3(4, 9, 2), Vector3(28, 18, 2), Vector3(15, 4, 2)]
	var inside := func(x: int, y: int) -> bool:
		for blob: Vector3 in blobs:
			if Vector2(x + 0.5 - blob.x, y + 0.5 - blob.y).length() < blob.z:
				return true
		return false
	for y in size:
		for x in size:
			if inside.call(x, y):
				var color := RED
				if not inside.call(x + 1, y + 1):
					color = RED_DARK
				elif not inside.call(x - 1, y - 1):
					color = RED_LIGHT
				image.set_pixel(x, y, color)
			elif outline.a > 0.0 and _near(inside, x, y, 2):
				image.set_pixel(x, y, outline)
	for seed: Vector2i in [Vector2i(14, 14), Vector2i(18, 17), Vector2i(12, 19), Vector2i(20, 12), Vector2i(16, 21)]:
		image.set_pixelv(seed, SEED)
	return image


## Есть ли пятно ближе radius клеток (обводка толщиной radius, как у объектов оригинала — 2 px).
func _near(inside: Callable, x: int, y: int, radius: int) -> bool:
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if absi(dx) + absi(dy) <= radius and inside.call(x + dx, y + dy):
				return true
	return false


## Розовый обводки чужих объектов оригинала: самый частый «розовый» пиксель банана.
func _banana_pink() -> Color:
	var image := (load(BANANA) as Texture2D).get_image()
	if image.is_compressed():
		image.decompress()
	var counts := {}
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			if c.a > 0.5 and c.r > 0.7 and c.b > 0.45 and c.g < 0.6:
				counts[c.to_html()] = int(counts.get(c.to_html(), 0)) + 1
	var best := "ff4fd8"
	var most := 0
	for key in counts:
		if counts[key] > most:
			most = counts[key]
			best = key
	return Color.html(best)


func _save(image: Image, file_name: String) -> void:
	HandDrawn.save_png(image, OUT_DIR + file_name + ".png")
