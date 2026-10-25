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
	".": [".", ".", ".", ".", "W"],
}


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_save(_remake_01(), "remake_01")
	quit()


## «Трамплины»: небо с солнцем, эстакада над водой с опорами и перилами, трамплин,
## красная машина в прыжке.
func _remake_01() -> Image:
	var image := Image.create(WIDTH, HEIGHT, false, Image.FORMAT_RGBA8)
	for y in HEIGHT:
		for x in WIDTH:
			var key := "S"
			if y >= 18:
				key = "b" if (x + y * 3) % 7 == 0 else ("n" if y >= 21 and (x + y) % 5 == 0 else "B")
			elif y <= 6 and (x * 7 + y * 3) % 11 == 0:
				key = "s"
			image.set_pixel(x, y, COLORS[key])
	_rect(image, Rect2i(27, 2, 3, 3), "Z")
	# Опоры эстакады в воду.
	for column_x in [4, 11, 18, 25]:
		_rect(image, Rect2i(column_x, 18, 2, 4), "C")
		_rect(image, Rect2i(column_x + 1, 18, 1, 4), "c")
	# Настил: перила, дорога, кромка.
	for x in range(1, WIDTH - 1):
		if x % 3 == 0:
			image.set_pixel(x, 14, COLORS["O"])
		image.set_pixel(x, 15, COLORS["O"])
		image.set_pixel(x, 16, COLORS["D"])
		image.set_pixel(x, 17, COLORS["d"] if x % 4 == 0 else COLORS["D"])
	# Трамплин: клин на дороге, выше к левому краю (машина едет справа налево и улетает).
	for x in range(20, 27):
		var top := 12 + int((x - 20) * 0.6)
		for y in range(top, 16):
			image.set_pixel(x, y, COLORS["r" if y == top else "R"])
	# Машина в прыжке (вид сбоку) над трамплином и след полёта от его края.
	_rect(image, Rect2i(14, 9, 4, 2), "A")
	_rect(image, Rect2i(15, 8, 2, 1), "a")
	image.set_pixel(14, 11, COLORS["T"])
	image.set_pixel(17, 11, COLORS["T"])
	for point in [Vector2i(20, 12), Vector2i(19, 11), Vector2i(18, 11)]:
		image.set_pixelv(point, COLORS["W"])
	# Подпись в одну строку, сокращённо (как «СНЕЖ.» оригинала) — сцена остаётся видна.
	_label(image, ["ТРАМП."])
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
