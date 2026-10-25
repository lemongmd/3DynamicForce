extends SceneTree
## Перенос спрайтовых шрифтов оригинала (Sprite Font, Construct 3) в шрифты Godot (FontFile).
##
## Запуск из корня проекта (после import_original_assets.ps1):
##   godot --headless --path . -s res://scripts/tools/build_sprite_fonts.gd
##
## Шрифты оригинала (параметры — из объектов Text и TimerFont, layouts/Global.json):
##   * Text (ui/text.png 96×48): клетки 6×6 по 16 в ряд, набор символов CHARSET_TEXT,
##     ширина символов — SPACING_TEXT (остальные 6 px); в оригинале весь интерфейс им,
##     в масштабе 2. Буквы нарисованы заглавными: строчные латиница и кириллица — свои
##     клетки, заглавные здесь показываются теми же клетками (в оригинале заглавных
##     A–I в наборе нет: там спрайты особых ников — их не переносим).
##   * TimerFont (ui/timerfont.png 72×45): клетки 9×15 по 8 в ряд, «0-1-2-…-9-:»
##     (каждая цифра через клетку; «:» шириной 4) — сегментный таймер, красный.
## Результат — assets/fonts/df_text.res и df_timer.res: растровые FontFile с fixed_size
## и целочисленным масштабом (font_size 12 у Text = пиксели ×2, как в оригинале).

const TEXT_IMAGE := "res://assets/original/textures/ui/text.png"
const TIMER_IMAGE := "res://assets/original/textures/ui/timerfont.png"
const TEXT_OUT := "res://assets/fonts/df_text.res"
const TIMER_OUT := "res://assets/fonts/df_timer.res"

const CHARSET_TEXT := " !\"#$%&'()*+,-./0123456789:;<=>?@abcdefghijklmnopqrstuvwxyz[\\]^_`{|}~абвгдеёжзийклмнопрстуфхцчшщъыьэюя🖥️👑🍩☺█💩💩💩💩💩ABCDEFGHI"
const SPACING_TEXT := [
	[5, "$@g_~лцъийn"],
	[4, " \"%*-/0123456789<=>?abcdefhijklopqrstuvxyz\\^{}абвгеёзкнопрстухчьэя"],
	[3, "(),;[]`"],
	[2, "!'.:|EI"],
]
## Особые клетки оригинала (спрайты ников «булава» и «lmgd») — не переносим.
const SKIP_TEXT := "ABCDEFGHI"
## Замены: тире, многоточие, кавычки-ёлочки — их нет в наборе оригинала.
const TEXT_ALIASES := {"—": "-", "–": "-", "…": ".", "«": "\"", "»": "\"", "“": "\"", "”": "\"", "№": "#"}
## Вариационный селектор эмодзи (U+FE0F) клетки не занимает.
const VARIATION_SELECTOR := 0xFE0F


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/fonts"))
	var ok := _build_text() and _build_timer()
	print("Спрайтовые шрифты: %s" % ("готово" if ok else "ОШИБКА"))
	quit(0 if ok else 1)


func _build_text() -> bool:
	var image := _load_image(TEXT_IMAGE)
	if image == null:
		return false
	var widths := {}
	for group in SPACING_TEXT:
		for ch in String(group[1]):
			widths[ch.unicode_at(0)] = int(group[0])
	var cells := {}
	var cell := 0
	for ch in CHARSET_TEXT:
		var code := ch.unicode_at(0)
		if code == VARIATION_SELECTOR:
			continue
		if not SKIP_TEXT.contains(ch):
			cells[code] = cell
		cell += 1
	# Ширина из spacing-data оригинала, но не уже рисунка: Mace Dev перерисовал часть знаков
	# (% стал шире, точка и двоеточие сдвинуты на пиксель) — по старой ширине они налезали
	# на соседние буквы.
	for code in cells:
		var drawn := _drawn_width(image, cells[code], 16, Vector2i(6, 6))
		if drawn > int(widths.get(code, 6)):
			widths[code] = drawn
	# Заглавные — теми же клетками, что строчные (буквы шрифта и так «заглавные»).
	for code in range(0x61, 0x7B):
		cells[code - 0x20] = cells[code]
		widths[code - 0x20] = widths.get(code, 6)
	for code in range(0x430, 0x450):
		cells[code - 0x20] = cells[code]
		widths[code - 0x20] = widths.get(code, 6)
	cells[0x401] = cells[0x451]
	widths[0x401] = widths.get(0x451, 6)
	# Типографские знаки, которых в наборе оригинала нет, — похожими символами.
	for alias in TEXT_ALIASES:
		var source: int = String(TEXT_ALIASES[alias]).unicode_at(0)
		cells[String(alias).unicode_at(0)] = cells[source]
		widths[String(alias).unicode_at(0)] = widths.get(source, 6)
	return _save_font(image, Vector2i(6, 6), 16, cells, widths, 6, 1, "DF Text", TEXT_OUT)


func _build_timer() -> bool:
	var image := _load_image(TIMER_IMAGE)
	if image == null:
		return false
	var cells := {}
	var widths := {}
	for digit in 10:
		cells[0x30 + digit] = digit * 2
		widths[0x30 + digit] = 9
	cells[0x3A] = 20
	widths[0x3A] = 4
	return _save_font(image, Vector2i(9, 15), 8, cells, widths, 9, 0, "DF Timer", TIMER_OUT)


## Ширина рисунка в клетке: правый занятый столбец + 1 (0 — пустая клетка).
func _drawn_width(image: Image, index: int, columns: int, cell_size: Vector2i) -> int:
	var origin := Vector2i((index % columns) * cell_size.x, (index / columns) * cell_size.y)
	for x in range(cell_size.x - 1, -1, -1):
		for y in cell_size.y:
			if image.get_pixel(origin.x + x, origin.y + y).a > 0.5:
				return x + 1
	return 0


## Растровый FontFile: глиф = клетка картинки целиком, сдвиг вперёд — ширина символа.
func _save_font(image: Image, cell_size: Vector2i, columns: int, cells: Dictionary, widths: Dictionary,
		default_width: int, descent: int, font_name: String, path: String) -> bool:
	var font := FontFile.new()
	font.font_name = font_name
	font.fixed_size = cell_size.y
	font.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_INTEGER_ONLY
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	font.generate_mipmaps = false
	font.allow_system_fallback = false
	var size := Vector2i(cell_size.y, 0)
	font.set_texture_image(0, size, 0, image)
	font.set_cache_ascent(0, cell_size.y, cell_size.y)
	font.set_cache_descent(0, cell_size.y, descent)
	for code in cells:
		var index: int = cells[code]
		var uv := Rect2(Vector2((index % columns) * cell_size.x, (index / columns) * cell_size.y), Vector2(cell_size))
		font.set_glyph_texture_idx(0, size, code, 0)
		font.set_glyph_uv_rect(0, size, code, uv)
		font.set_glyph_size(0, size, code, Vector2(cell_size))
		font.set_glyph_offset(0, size, code, Vector2(0, -cell_size.y))
		font.set_glyph_advance(0, cell_size.y, code, Vector2(int(widths.get(code, default_width)), 0))
	var err := ResourceSaver.save(font, path)
	if err != OK:
		push_error("Не удалось сохранить %s: %s" % [path, error_string(err)])
		return false
	print("%s: %d символов -> %s" % [font_name, cells.size(), path])
	return true


func _load_image(path: String) -> Image:
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	if image == null:
		push_error("Нет картинки %s" % path)
	return image
