extends SceneTree
## Пиксельные картинки карты «Хэллоуин» -> res://assets/textures/halloween/:
##   pumpkin.png 64×32 — развёртка тыквы (шар, UV SphereMesh: u — по кругу, v — сверху вниз):
##     8 долек (светлые середины, тёмные борозды), тёмная макушка у хвостика; на передней
##     стороне (u = FACE_U) — вырезанная рожица: глаза-треугольники и рот с зубцами;
##   pumpkin_glow.png — та же развёртка, светится только рожица (маска свечения);
##   ghost_body_0..2.png 96×40 — развёртка призрака-«простыни» (ghost_body.gd), три рожицы
##     по референсам автора ремейка: «ох», злая ухмылка, рот с клыками и языком (как Boo);
##   mud.png 32×32 — раскисшая земля мини-кладбища (зона MUD: машина буксует);
##   leaves_orange/red/yellow.png 32×32 — листва осенних деревьев (крупные пятна, блики);
##   bark.png 16×32 — кора; stone.png 16×16 — камень надгробий; grave_front.png 24×32 —
##     лицевая сторона надгробия (крест и «RIP», выбоины, мох);
##   ground.png 64×64 — ночная трава с опавшими листьями (фон карты плиткой);
##   leaf.png 8×8 — белый лист (частицы падающих листьев, цвет задаёт частица);
##   glow_pool.png 32×32 — пятно света на земле под тыквой (белое, ступенями к краю; цвет и
##     сложение — у материала): свет «нарисован», настоящие лампы на длинной сетке дороги
##     в Compatibility ограничены 8 штуками на объект.
##
## Запуск (из корня проекта):
##   godot --headless --path . -s res://scripts/tools/build_halloween_textures.gd

const HandDrawn := preload("res://scripts/tools/hand_drawn.gd")
const OUT_DIR := "res://assets/textures/halloween/"
## Где на развёртке тыквы рожица (доля окружности). SphereMesh начинает u с −Z… на снимке
## проверено: рожица смотрит в +Z узла (к машинам, едущим навстречу по −Z).
const FACE_U := 0.25

const INK := Color8(26, 10, 14)
const ORANGE := Color8(242, 122, 26)
const ORANGE_LIGHT := Color8(255, 168, 60)
const ORANGE_DARK := Color8(178, 72, 20)
const ORANGE_DEEP := Color8(120, 42, 18)
const GLOW := Color8(255, 226, 92)
const GLOW_DEEP := Color8(255, 150, 30)
const GHOST := Color8(238, 244, 255)
const GHOST_SHADE := Color8(176, 200, 236)
const GHOST_DEEP := Color8(130, 156, 210)
## Рожицы призрака: K — чернота, R — рот, W — клыки, T — язык. Верхний ряд — строка развёртки
## GHOST_FACE_TOP (верх купола: камера смотрит сверху).
const GHOST_FACE_TOP := 11
const GHOST_FACES := [
	[
		".KK.......KK.",
		"KKKK.....KKKK",
		"KKKK.....KKKK",
		"KKKK.....KKKK",
		".KK.......KK.",
		".............",
		".....KKK.....",
		"....KKKKK....",
		"....KKKKK....",
		".....KKK.....",
	],
	[
		"KK.........KK",
		".KKK.....KKK.",
		"..KKK...KKK..",
		"..KK.....KK..",
		".............",
		"K...........K",
		".KK.......KK.",
		"..KKKKKKKKK..",
		"...KKKKKKK...",
	],
	[
		"..K.........K..",
		".KKK.......KKK.",
		".KKK.......KKK.",
		"..K.........K..",
		"...............",
		"KKKKKKKKKKKKKKK",
		"KWRWRWRWRWRWRWK",
		".KRRRRRRRRRRRK.",
		"..KRRRTTTRRRK..",
		"...KKKTTTKKK...",
		"......TTT......",
		".......T.......",
	],
]

var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	_rng.seed = 31
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_save(_pumpkin(false), "pumpkin")
	_save(_pumpkin(true), "pumpkin_glow")
	for face in GHOST_FACES.size():
		_save(_ghost_body(face), "ghost_body_%d" % face)
	_save(_leaves([Color8(120, 40, 14), Color8(196, 74, 20), Color8(240, 128, 30), Color8(255, 190, 70)]), "leaves_orange")
	_save(_leaves([Color8(84, 16, 22), Color8(150, 30, 30), Color8(206, 56, 40), Color8(246, 112, 70)]), "leaves_red")
	_save(_leaves([Color8(130, 92, 20), Color8(196, 150, 30), Color8(236, 200, 60), Color8(255, 236, 130)]), "leaves_yellow")
	_save(_bark(), "bark")
	_save(_stone(), "stone")
	_save(_grave_front(), "grave_front")
	_save(_ground(), "ground")
	_save(_leaf(), "leaf")
	_save(_glow_pool(), "glow_pool")
	_save(_mud(), "mud")
	quit()


func _save(image: Image, file_name: String) -> void:
	HandDrawn.save_png(image, OUT_DIR + file_name + ".png")


## Тыква: 8 долек по кругу; glow_only — только рожица (маска свечения), остальное чёрное.
func _pumpkin(glow_only: bool) -> Image:
	var w := 64
	var h := 32
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var rib := fposmod(float(x) / w * 8.0, 1.0)
			# Середина дольки светлее, борозды тёмные.
			var bulge := 1.0 - absf(rib - 0.5) * 2.0
			var color := ORANGE_DARK
			if bulge > 0.75:
				color = ORANGE_LIGHT
			elif bulge > 0.3:
				color = ORANGE
			elif bulge < 0.12:
				color = ORANGE_DEEP
			# Макушка (у хвостика) и низ темнее.
			if y < 3 or y > h - 3:
				color = ORANGE_DEEP if bulge < 0.5 else ORANGE_DARK
			elif y < 5 or y > h - 6:
				color = color.darkened(0.18)
			image.set_pixel(x, y, Color.BLACK if glow_only else color)
	# Рожица спереди: глаза-треугольники, нос, рот с двумя зубцами.
	var cx := int(FACE_U * w)
	var face := func(x: int, y: int, inner: bool) -> void:
		var px := posmod(cx + x, w)
		image.set_pixel(px, y, GLOW if inner else GLOW_DEEP)
	for row in 4:
		for dx in range(-row, row + 1):
			face.call(-6 + dx, 9 + row, absf(dx) < row)
			face.call(6 + dx, 9 + row, absf(dx) < row)
	face.call(0, 15, false)
	face.call(-1, 16, false)
	face.call(0, 16, true)
	face.call(1, 16, false)
	for dx in range(-8, 9):
		var top := 19
		var bottom := 22
		# Края рта загнуты вверх, два зубца сверху и один снизу.
		if absf(dx) >= 7:
			top = 18
			bottom = 20
		for y in range(top, bottom + 1):
			if (dx == -3 or dx == 4) and y == top:
				continue
			if dx == 0 and y == bottom:
				continue
			face.call(dx, y, y > top and y < bottom)
	if glow_only:
		for y in h:
			for x in w:
				if image.get_pixel(x, y) != GLOW and image.get_pixel(x, y) != GLOW_DEEP:
					image.set_pixel(x, y, Color.BLACK)
	return image


## Тело призрака (развёртка ghost_body.gd: u — по кругу, перед в u = 0.5; v — по профилю сверху
## вниз): белое, к бокам и книзу голубая тень, на макушке блик; рожица — FACES[face].
func _ghost_body(face: int) -> Image:
	var w := 96
	var h := 40
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var side := absf(float(x) / w - 0.5) * 2.0
			var shade := side * 0.8 + maxf(float(y) / h - 0.55, 0.0) * 1.4
			var color := GHOST
			if shade > 0.55:
				color = GHOST_SHADE
			if shade > 0.85:
				color = GHOST_DEEP
			if y < 6 and side < 0.35:
				color = Color.WHITE
			image.set_pixel(x, y, color)
	var colors := {"K": INK, "R": Color8(150, 22, 40), "W": Color.WHITE, "T": Color8(244, 116, 150)}
	var rows: Array = GHOST_FACES[face]
	var left := w / 2 - String(rows[0]).length() / 2
	for gy in rows.size():
		var row := String(rows[gy])
		for gx in row.length():
			if colors.has(row[gx]):
				image.set_pixel(left + gx, GHOST_FACE_TOP + gy, colors[row[gx]])
	return image


## Раскисшая земля кладбища (зона MUD, плитка без шва): бурая, мокрые тёмные пятна с бликами,
## комья и камешки.
func _mud() -> Image:
	var size := 32
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var soil := [Color8(44, 28, 22), Color8(62, 40, 28), Color8(82, 54, 34), Color8(104, 72, 44)]
	var noise := FastNoiseLite.new()
	noise.seed = 13
	noise.frequency = 0.2
	for y in size:
		for x in size:
			var a := float(x) / size * TAU
			var b := float(y) / size * TAU
			var n := noise.get_noise_3d(cos(a) * 5.0, sin(a) * 5.0, cos(b) * 5.0 + sin(b) * 3.0)
			var color: Color = soil[clampi(int((n + 0.55) * 2.6), 0, 3)]
			if n < -0.32:
				# Лужица: тёмная вода с бликом сверху.
				color = Color8(30, 26, 34)
				if noise.get_noise_3d(cos(a) * 5.0, sin(a) * 5.0, cos(b - 0.2) * 5.0 + sin(b - 0.2) * 3.0) > -0.32:
					color = Color8(96, 92, 120)
			elif _rng.randf() < 0.04:
				color = soil[3].lightened(0.15)
			image.set_pixel(x, y, color)
	for i in 7:
		var x := _rng.randi_range(0, size - 2)
		var y := _rng.randi_range(0, size - 2)
		image.set_pixel(x, y, Color8(120, 116, 112))
		image.set_pixel(x + 1, y, Color8(84, 80, 80))
	return image



## Листва: крупные пятна 4 тонов (ramp — от тёмного к светлому), сверху светлее.
func _leaves(ramp: Array) -> Image:
	var size := 32
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = _rng.randi()
	noise.frequency = 0.18
	for y in size:
		for x in size:
			# Плитка без шва: шум по тору.
			var a := float(x) / size * TAU
			var b := float(y) / size * TAU
			var n := noise.get_noise_3d(cos(a) * 5.0, sin(a) * 5.0, cos(b) * 5.0 + sin(b) * 3.0)
			n += (1.0 - float(y) / size) * 0.25
			var index := clampi(int((n + 0.6) * 2.6), 0, ramp.size() - 1)
			image.set_pixel(x, y, ramp[index])
	# Отдельные светлые листочки.
	for i in 18:
		var x := _rng.randi_range(0, size - 2)
		var y := _rng.randi_range(0, size - 2)
		image.set_pixel(x, y, ramp[ramp.size() - 1])
		image.set_pixel(x + 1, y, ramp[ramp.size() - 2])
	return image


func _bark() -> Image:
	var image := Image.create(16, 32, false, Image.FORMAT_RGBA8)
	var colors := [Color8(46, 28, 22), Color8(70, 44, 32), Color8(94, 62, 44)]
	for x in 16:
		var stripe: Color = colors[(x * 7 + 3) % 3]
		for y in 32:
			var color: Color = stripe
			if _rng.randf() < 0.12:
				color = colors[0]
			image.set_pixel(x, y, color)
	return image


func _stone() -> Image:
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var colors := [Color8(78, 82, 96), Color8(104, 108, 122), Color8(128, 132, 146)]
	for y in 16:
		for x in 16:
			var r := _rng.randf()
			image.set_pixel(x, y, colors[0] if r < 0.2 else (colors[2] if r > 0.85 else colors[1]))
	return image


## Лицо надгробия: светлый камень, сверху скругление (прозрачные углы), крест и «RIP», мох снизу.
func _grave_front() -> Image:
	var w := 24
	var h := 32
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var light := Color8(140, 144, 160)
	var mid := Color8(112, 116, 132)
	var dark := Color8(70, 72, 88)
	var moss := Color8(70, 110, 60)
	for y in h:
		for x in w:
			# Скруглённый верх: окружность радиуса w/2.
			var dx := x - w * 0.5 + 0.5
			if y < w * 0.5 and dx * dx + (y - w * 0.5) * (y - w * 0.5) > w * w * 0.25:
				continue
			var color := mid if _rng.randf() > 0.25 else light
			if x == 0 or x == w - 1 or y == h - 1:
				color = dark
			if y > h - 6 and _rng.randf() < 0.5:
				color = moss
			image.set_pixel(x, y, color)
	# Крест.
	for y in range(5, 15):
		image.set_pixel(11, y, dark)
		image.set_pixel(12, y, dark)
	for x in range(8, 16):
		image.set_pixel(x, 8, dark)
	# «RIP» пикселями 3×5.
	var glyphs := {
		"R": ["##.", "#.#", "##.", "#.#", "#.#"],
		"I": ["###", ".#.", ".#.", ".#.", "###"],
		"P": ["##.", "#.#", "##.", "#..", "#.."],
	}
	var left := 6
	for ch in ["R", "I", "P"]:
		var rows: Array = glyphs[ch]
		for gy in 5:
			for gx in 3:
				if String(rows[gy])[gx] == "#":
					image.set_pixel(left + gx, 18 + gy, dark)
		left += 4
	# Выбоины.
	for i in 6:
		image.set_pixel(_rng.randi_range(2, w - 3), _rng.randi_range(14, h - 8), dark)
	return image


## Ночная трава с опавшими листьями (плитка без шва).
func _ground() -> Image:
	var size := 64
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var grass := [Color8(28, 40, 38), Color8(36, 52, 46), Color8(46, 64, 52)]
	var leaves := [Color8(150, 66, 24), Color8(190, 96, 30), Color8(120, 34, 30), Color8(176, 140, 40)]
	var noise := FastNoiseLite.new()
	noise.seed = 77
	noise.frequency = 0.12
	for y in size:
		for x in size:
			var a := float(x) / size * TAU
			var b := float(y) / size * TAU
			var n := noise.get_noise_3d(cos(a) * 8.0, sin(a) * 8.0, cos(b) * 8.0 + sin(b) * 4.0)
			var color: Color = grass[clampi(int((n + 0.5) * 2.2), 0, 2)]
			if _rng.randf() < 0.05:
				color = grass[2].lightened(0.1)
			image.set_pixel(x, y, color)
	# Листья — пятнышки 2×1 и 1×2.
	for i in 90:
		var x := _rng.randi_range(0, size - 1)
		var y := _rng.randi_range(0, size - 1)
		var leaf: Color = leaves[_rng.randi_range(0, leaves.size() - 1)]
		image.set_pixel(x, y, leaf)
		if _rng.randf() < 0.5:
			image.set_pixel((x + 1) % size, y, leaf.darkened(0.2))
		else:
			image.set_pixel(x, (y + 1) % size, leaf.darkened(0.2))
	return image


## Лист 8×8 (белый с тенью): цвет даёт частица.
func _leaf() -> Image:
	var rows := [
		"........",
		"....##..",
		"..####..",
		".#####s.",
		".####s..",
		"..##s...",
		".#s.....",
		"#.......",
	]
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	for y in 8:
		for x in 8:
			match rows[y][x]:
				"#":
					image.set_pixel(x, y, Color.WHITE)
				"s":
					image.set_pixel(x, y, Color(0.7, 0.7, 0.7))
	return image


## Пятно света: круг, прозрачность ступенями (пиксельно, без плавного градиента).
func _glow_pool() -> Image:
	var size := 32
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var steps := [0.55, 0.38, 0.24, 0.12]
	for y in size:
		for x in size:
			var r := Vector2(x - size * 0.5 + 0.5, y - size * 0.5 + 0.5).length() / (size * 0.5)
			if r >= 1.0:
				continue
			image.set_pixel(x, y, Color(1, 1, 1, steps[mini(int(r * steps.size()), steps.size() - 1)]))
	return image
