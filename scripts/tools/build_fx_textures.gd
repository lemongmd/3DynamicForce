extends SceneTree
## Текстуры эффектов в 4 раза детальнее прежних 8/16 px (просьба автора оригинала: эффект
## приземления «сильно пиксельный») -> res://assets/textures/fx/*_hd.png:
##   fx_puff_hd 32×32 — клуб пыли (несколько кругов, свет сверху-слева, тень снизу-справа);
##   fx_ring_hd 64×64 — кольцо ударной волны (светлая кромка, к центру прозрачнее);
##   fx_spark_hd 16×16 — искра-звёздочка.
## Белые с серыми тенями: цвет даёт эффект (Fx). Пиксели чёткие (без сглаживания), как у всех
## картинок игры, просто их больше.
##
## Запуск (из корня проекта):
##   godot --headless --path . -s res://scripts/tools/build_fx_textures.gd

const HandDrawn := preload("res://scripts/tools/hand_drawn.gd")
const OUT_DIR := "res://assets/textures/fx/"
const LIGHT := Color(1.0, 1.0, 1.0)
const MID := Color(0.86, 0.86, 0.9)
const SHADE := Color(0.68, 0.68, 0.76)


func _initialize() -> void:
	_save(_puff(), "fx_puff_hd")
	_save(_ring(), "fx_ring_hd")
	_save(_spark(), "fx_spark_hd")
	quit()


## Клуб: объединение кругов; свет как в пиксель-арте — там, где сверху-слева от пикселя уже
## пусто, светлая кромка, где снизу-справа — тень, внутри — средний тон.
func _puff() -> Image:
	var size := 32
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var blobs := [Vector3(16, 18, 10), Vector3(10, 14, 7), Vector3(22, 13, 7), Vector3(15, 9, 6), Vector3(23, 21, 6)]
	var inside := func(x: int, y: int) -> bool:
		for blob: Vector3 in blobs:
			if Vector2(x + 0.5 - blob.x, y + 0.5 - blob.y).length() < blob.z:
				return true
		return false
	for y in size:
		for x in size:
			if not inside.call(x, y):
				continue
			var color := MID
			if not inside.call(x - 2, y - 2) or not inside.call(x - 1, y - 3):
				color = LIGHT
			elif not inside.call(x + 2, y + 2) or not inside.call(x + 3, y + 1):
				color = SHADE
			image.set_pixel(x, y, color)
	return image


## Кольцо: полоса шириной ~6 px по краю, внешняя кромка светлее, внутренняя — тень.
func _ring() -> Image:
	var size := 64
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size, size) * 0.5
	for y in size:
		for x in size:
			var r := Vector2(x + 0.5, y + 0.5).distance_to(center)
			if r > 31.0 or r < 25.0:
				continue
			var color := MID
			if r > 29.5:
				color = LIGHT
			elif r < 26.5:
				color = Color(SHADE, 0.7)
			image.set_pixel(x, y, color)
	return image


## Искра: четырёхлучевая звёздочка со светлым центром.
func _spark() -> Image:
	var size := 16
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(7.5, 7.5)
	for y in size:
		for x in size:
			var d := Vector2(x, y) - center
			var along := minf(absf(d.x), absf(d.y))
			var reach := maxf(absf(d.x), absf(d.y))
			# Лучи по осям сужаются к концам; в середине — ромб.
			var on_ray := along <= maxf(1.6 - reach * 0.18, 0.0) and reach <= 7.5
			var core := absf(d.x) + absf(d.y) <= 3.5
			if core:
				image.set_pixel(x, y, LIGHT)
			elif on_ray:
				image.set_pixel(x, y, MID if reach > 4.5 else LIGHT)
	return image


func _save(image: Image, file_name: String) -> void:
	HandDrawn.save_png(image, OUT_DIR + file_name + ".png")
