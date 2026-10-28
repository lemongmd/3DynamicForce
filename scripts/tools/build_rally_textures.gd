extends SceneTree
## Пиксельные картинки карты «Ралли» -> res://assets/textures/rally/ (8 px = 1 м, бесшовные):
##   asphalt.png 32×32 — асфальт: тёмно-серый, зерно в три тона, редкие светлые камешки, трещинки;
##   kerb.png 8×16 — бордюр: красный и белый блоки по 1 м вдоль трассы, скругление сверху (светлая
##     кромка) и тень у стыка;
##   grass.png 32×32 — трава в два зелёных с травинками и редкими жёлтыми цветками.
## Перерисованные вручную картинки (assets/hand_drawn.txt) не перезаписываются.
##
## Запуск (из корня проекта):
##   godot --headless --path . -s res://scripts/tools/build_rally_textures.gd

const HandDrawn := preload("res://scripts/tools/hand_drawn.gd")
const OUT_DIR := "res://assets/textures/rally/"

const ASPHALT := [Color8(58, 60, 68), Color8(66, 68, 77), Color8(50, 52, 60)]
const ASPHALT_STONE := Color8(96, 98, 108)
const ASPHALT_CRACK := Color8(38, 39, 46)
const KERB_RED := Color8(208, 40, 42)
const KERB_RED_LIGHT := Color8(236, 84, 74)
const KERB_RED_DARK := Color8(150, 24, 30)
const KERB_WHITE := Color8(238, 238, 236)
const KERB_WHITE_SHADE := Color8(196, 198, 204)
const GRASS := Color8(92, 168, 64)
const GRASS_DARK := Color8(66, 138, 52)
const GRASS_LIGHT := Color8(126, 196, 80)
const FLOWER := Color8(246, 222, 90)

var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_save(_asphalt(), "asphalt")
	_save(_kerb(), "kerb")
	_save(_grass(), "grass")
	quit()


func _save(image: Image, file_name: String) -> void:
	HandDrawn.save_png(image, "%s%s.png" % [OUT_DIR, file_name])


func _asphalt() -> Image:
	_rng.seed = 404
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var roll := _rng.randf()
			image.set_pixel(x, y, ASPHALT[0] if roll < 0.6 else (ASPHALT[1] if roll < 0.82 else ASPHALT[2]))
	for i in 7:
		image.set_pixel(_rng.randi_range(0, 31), _rng.randi_range(0, 31), ASPHALT_STONE)
	# Трещинка: ломаная в несколько пикселей.
	var p := Vector2i(_rng.randi_range(4, 27), _rng.randi_range(4, 27))
	for i in 6:
		image.set_pixel(posmod(p.x, 32), posmod(p.y, 32), ASPHALT_CRACK)
		p += Vector2i(1, _rng.randi_range(-1, 1))
	return image


## Бордюр: вдоль трассы (по y картинки) красный блок 8 px и белый 8 px. Поперёк (x) —
## скругление: светлая кромка у одного края, тень у другого.
func _kerb() -> Image:
	var image := Image.create(8, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		var red := y < 8
		for x in 8:
			var color: Color = KERB_RED if red else KERB_WHITE
			if x == 0:
				color = KERB_RED_LIGHT if red else Color.WHITE
			elif x == 7:
				color = KERB_RED_DARK if red else KERB_WHITE_SHADE
			image.set_pixel(x, y, color)
		# Стык блоков — тёмная черта.
		if y == 7 or y == 15:
			for x in 8:
				image.set_pixel(x, y, KERB_RED_DARK if red else KERB_WHITE_SHADE)
	return image


func _grass() -> Image:
	_rng.seed = 77
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			# Крупные пятна двух оттенков (по синусам — бесшовно).
			var t := sin(TAU * x / 32.0 * 2.0 + 1.0) + sin(TAU * y / 32.0 * 2.0) + sin(TAU * (x + y) / 32.0)
			image.set_pixel(x, y, GRASS if t > -0.4 else GRASS_DARK)
	# Травинки «V» и редкие цветки.
	for i in 14:
		var x := _rng.randi_range(0, 31)
		var y := _rng.randi_range(0, 31)
		var light := image.get_pixel(x, y) == GRASS
		var blade := GRASS_LIGHT if light else GRASS
		image.set_pixel(x, y, blade)
		image.set_pixel(posmod(x + 2, 32), y, blade)
		image.set_pixel(posmod(x + 1, 32), posmod(y + 1, 32), blade)
	for i in 3:
		image.set_pixel(_rng.randi_range(0, 31), _rng.randi_range(0, 31), FLOWER)
	return image
