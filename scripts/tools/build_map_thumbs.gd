extends SceneTree
## Картинки наших карт для меню в стиле menuselectmap оригинала (32×24: чёрная рамка со
## скруглёнными углами, сцена карты, подпись белыми буквами на чёрной плашке в две строки)
## -> res://assets/textures/maps/<карта>.png. Меню берёт её вместо «абстракции» оригинала.
##
## Запуск (из корня проекта):
##   godot --headless --path . -s res://scripts/tools/build_map_thumbs.gd

const HandDrawn := preload("res://scripts/tools/hand_drawn.gd")
const OUT_DIR := "res://assets/textures/maps/"
const WIDTH := 32
const HEIGHT := 24

const COLORS := {
	"K": Color8(0, 0, 0), "W": Color8(255, 255, 255),
	"S": Color8(127, 214, 255), "s": Color8(184, 236, 255), "Z": Color8(255, 226, 74),
	"B": Color8(47, 111, 224), "b": Color8(95, 168, 255), "n": Color8(30, 70, 170),
	"D": Color8(58, 58, 72), "d": Color8(90, 90, 106), "O": Color8(255, 154, 31),
	"C": Color8(154, 154, 168), "c": Color8(110, 110, 124),
	"R": Color8(192, 80, 58), "r": Color8(224, 112, 80), "G": Color8(80, 220, 60),
	"A": Color8(224, 48, 48), "a": Color8(255, 120, 100), "T": Color8(30, 30, 36),
	# «Хэллоуин»: ночь, луна, тыква, призрак.
	"N": Color8(26, 20, 52), "n2": Color8(44, 30, 78), "M": Color8(255, 244, 196), "m": Color8(214, 200, 150),
	"g": Color8(26, 44, 36), "h": Color8(38, 60, 46), "P": Color8(242, 122, 26), "p": Color8(178, 72, 20),
	"Y": Color8(255, 226, 92), "w": Color8(214, 228, 255), "e": Color8(70, 72, 92),
	# «Ралли»: тёмная трава.
	"q": Color8(52, 160, 48),
}

## Буквы подписи (белые на чёрной плашке, как у карт оригинала).
const GLYPHS := {
	"Т": ["WWW", ".W.", ".W.", ".W.", ".W."],
	"Р": ["WWW", "W.W", "WWW", "W..", "W.."],
	"А": [".W.", "W.W", "WWW", "W.W", "W.W"],
	"М": ["W...W", "WW.WW", "W.W.W", "W...W", "W...W"],
	"-": ["...", "...", "WWW", "...", "..."],
	"П": ["WWW", "W.W", "W.W", "W.W", "W.W"],
	"Л": [".WW", "W.W", "W.W", "W.W", "W.W"],
	"И": ["W..W", "W..W", "W.WW", "WW.W", "W..W"],
	"Н": ["W.W", "W.W", "WWW", "W.W", "W.W"],
	"Ы": ["W...W", "W...W", "WW..W", "W.W.W", "WW..W"],
	"Х": ["W.W", "W.W", ".W.", "W.W", "W.W"],
	"Э": ["WW.", "..W", ".WW", "..W", "WW."],
	".": [".", ".", ".", ".", "W"],
}


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_save(_remake_01(), "remake_01")
	_save(_halloween(), "halloween")
	quit()


## «Хэллоуин»: ночное небо со звёздами и луной, кладбище на холме, тыква-фонарь и призрак.
func _halloween() -> Image:
	var image := Image.create(WIDTH, HEIGHT, false, Image.FORMAT_RGBA8)
	for y in HEIGHT:
		for x in WIDTH:
			var key := "N" if y < 9 else "n2"
			if y < 15 and (x * 13 + y * 7) % 23 == 0:
				key = "w"
			if y >= 17 - int(sin(x * 0.35) * 1.5):
				key = "h" if (x + y) % 6 == 0 else "g"
			image.set_pixel(x, y, COLORS[key])
	# Луна с кратером.
	for y in range(2, 11):
		for x in range(21, 30):
			if Vector2(x - 25, y - 6).length() <= 4.2:
				image.set_pixel(x, y, COLORS["M"])
	image.set_pixel(26, 5, COLORS["m"])
	image.set_pixel(24, 8, COLORS["m"])
	# Надгробия на холме.
	for grave_x in [3, 15, 27]:
		_rect(image, Rect2i(grave_x, 14, 2, 3), "e")
		image.set_pixel(grave_x, 13, COLORS["e"])
	# Призрак: купол, подол волной, глаза.
	_rect(image, Rect2i(18, 10, 5, 4), "w")
	_rect(image, Rect2i(19, 9, 3, 1), "w")
	image.set_pixel(18, 14, COLORS["w"])
	image.set_pixel(20, 14, COLORS["w"])
	image.set_pixel(22, 14, COLORS["w"])
	image.set_pixel(19, 11, COLORS["K"])
	image.set_pixel(21, 11, COLORS["K"])
	# Тыква-фонарь: дольки, хвостик, светящаяся рожица.
	_rect(image, Rect2i(6, 16, 8, 5), "P")
	_rect(image, Rect2i(7, 15, 6, 1), "P")
	_rect(image, Rect2i(7, 21, 6, 1), "p")
	for rib_x in [8, 11]:
		_rect(image, Rect2i(rib_x, 16, 1, 5), "p")
	image.set_pixel(10, 14, COLORS["g"])
	image.set_pixel(8, 17, COLORS["Y"])
	image.set_pixel(12, 17, COLORS["Y"])
	_rect(image, Rect2i(8, 19, 5, 1), "Y")
	_label(image, ["ХЭЛЛ."])
	_frame(image)
	return image


## «Ралли»: небо с солнцем, травяные холмы, асфальт с красно-белым бордюром наискосок,
## красная машина на трассе и клетчатый флаг у обочины.
func _remake_01() -> Image:
	var image := Image.create(WIDTH, HEIGHT, false, Image.FORMAT_RGBA8)
	for y in HEIGHT:
		for x in WIDTH:
			var key := "S"
			if y >= 10 - int(sin(x * 0.3) * 1.5):
				key = "q" if (x * 5 + y * 3) % 9 == 0 else "G"
			elif y <= 6 and (x * 7 + y * 3) % 11 == 0:
				key = "s"
			image.set_pixel(x, y, COLORS[key])
	_rect(image, Rect2i(27, 2, 3, 3), "Z")
	# Дорога наискосок вверх вправо: асфальт 5 px, по краям бордюр — красный и белый через 2 px.
	for x in WIDTH:
		var top := 15 - int(x * 0.22)
		for y in range(top, top + 7):
			if y >= HEIGHT:
				continue
			var edge := y == top or y == top + 6
			var kerb := "A" if (x / 2) % 2 == 0 else "W"
			image.set_pixel(x, y, COLORS[kerb] if edge else COLORS["d" if (x + y) % 5 == 0 else "D"])
	# Машина (вид сверху-сбоку) на дороге.
	_rect(image, Rect2i(10, 15, 5, 2), "A")
	_rect(image, Rect2i(11, 14, 3, 1), "a")
	image.set_pixel(10, 17, COLORS["T"])
	image.set_pixel(14, 17, COLORS["T"])
	# Клетчатый флаг на столбике у обочины.
	_rect(image, Rect2i(26, 6, 1, 6), "c")
	for fy in 2:
		for fx in 3:
			image.set_pixel(27 + fx, 6 + fy, COLORS["K" if (fx + fy) % 2 == 0 else "W"])
	_label(image, ["РАЛЛИ"])
	_frame(image)
	return image


func _rect(image: Image, rect: Rect2i, key: String) -> void:
	image.fill_rect(rect, COLORS[key])


## Подпись: строки по 5 px на чёрной плашке (отступ 1 px), как у карт оригинала.
func _label(image: Image, lines: Array) -> void:
	var y := 2
	for line: String in lines:
		var width := 0
		for ch in line:
			width += (GLYPHS[ch][0] as String).length() + 1
		_rect(image, Rect2i(1, y - 1, width + 2, 7), "K")
		var x := 2
		for ch in line:
			var glyph: Array = GLYPHS[ch]
			for gy in glyph.size():
				var row: String = glyph[gy]
				for gx in row.length():
					if row[gx] == "W":
						image.set_pixel(x + gx, y + gy, COLORS["W"])
			x += (glyph[0] as String).length() + 1
		y += 6


## Чёрная рамка со скруглёнными углами (угловые пиксели прозрачные).
func _frame(image: Image) -> void:
	for x in WIDTH:
		image.set_pixel(x, 0, COLORS["K"])
		image.set_pixel(x, HEIGHT - 1, COLORS["K"])
	for y in HEIGHT:
		image.set_pixel(0, y, COLORS["K"])
		image.set_pixel(WIDTH - 1, y, COLORS["K"])
	for corner in [Vector2i(0, 0), Vector2i(WIDTH - 1, 0), Vector2i(0, HEIGHT - 1), Vector2i(WIDTH - 1, HEIGHT - 1)]:
		image.set_pixelv(corner, Color(0, 0, 0, 0))


func _save(image: Image, map: String) -> void:
	HandDrawn.save_png(image, OUT_DIR + map + ".png")
