extends SceneTree
## Подсказки клавиш в стиле оригинала (gamelogo-desktophint: клавиша 5×7 — «E», пробел 26×7):
## та же «клавиша», другая буква -> res://assets/textures/ui/key_<буква>.png.
## Цвета берутся из клавиши «E» оригинала.
##
## Запуск (из корня проекта):
##   godot --headless --path . -s res://scripts/tools/build_key_hints.gd

const HandDrawn := preload("res://scripts/tools/hand_drawn.gd")
const SOURCE := "res://assets/original/textures/menu/gamelogo-desktophint-001.png"
const OUT_DIR := "res://assets/textures/ui/"
## Буквы внутри клавиши 3×5 (# — светлая, остальное — фон клавиши).
const LETTERS := {
	"q": ["###", "#.#", "#.#", "###", "..#"],
}


func _initialize() -> void:
	var source := (load(SOURCE) as Texture2D).get_image()
	if source.is_compressed():
		source.decompress()
	source.convert(Image.FORMAT_RGBA8)
	# Светлый цвет — буква «E», тёмный — фон клавиши (пиксель рядом с буквой).
	var light := source.get_pixel(1, 1)
	var dark := source.get_pixel(2, 2)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	for letter in LETTERS:
		var image := source.duplicate() as Image
		var rows: Array = LETTERS[letter]
		for y in rows.size():
			var row: String = rows[y]
			for x in row.length():
				image.set_pixel(1 + x, 1 + y, light if row[x] == "#" else dark)
		HandDrawn.save_png(image, OUT_DIR + "key_%s.png" % letter)
	quit()
