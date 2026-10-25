extends SceneTree
## Пиксельная тема интерфейса -> ui/main_theme.tres (значки — пиксельные картинки внутри темы).
##
## Стандартная тема Godot рисует скруглённые сглаженные углы и векторные значки (галочки,
## кружки переключателей, ползунки) — на экране 384×216, растянутом без сглаживания, они
## выглядят «мыльными». Здесь всё прямоугольное, без сглаживания, значки — пиксельные,
## цвета — как у логотипа (жёлтый/оранжевый на тёмно-синем).
##
## Запуск: godot --headless --path . -s res://scripts/tools/build_ui_theme.gd

const THEME_PATH := "res://ui/main_theme.tres"
const FONT := preload("res://assets/fonts/df_text.res")

const INK := Color(0.06, 0.06, 0.11)
const PANEL := Color(0.08, 0.08, 0.15, 0.94)
const BUTTON := Color(0.15, 0.16, 0.27)
const BUTTON_HOVER := Color(0.23, 0.25, 0.40)
const YELLOW := Color(1.0, 0.82, 0.1)
const ORANGE := Color(1.0, 0.5, 0.05)
const GREY := Color(0.45, 0.47, 0.58)
const DARK_GREY := Color(0.12, 0.12, 0.17)
const WHITE := Color(1.0, 1.0, 1.0)


func _initialize() -> void:
	var theme := Theme.new()
	theme.default_font = FONT
	theme.default_font_size = 12

	# Кнопки (и OptionButton — наследник Button).
	for type in ["Button", "OptionButton"]:
		theme.set_stylebox("normal", type, _box(BUTTON, YELLOW, 1, 5, 2))
		theme.set_stylebox("hover", type, _box(BUTTON_HOVER, YELLOW, 1, 5, 2))
		theme.set_stylebox("pressed", type, _box(ORANGE, YELLOW, 1, 5, 2))
		theme.set_stylebox("hover_pressed", type, _box(ORANGE, YELLOW, 1, 5, 2))
		theme.set_stylebox("disabled", type, _box(DARK_GREY, GREY, 1, 5, 2))
		theme.set_stylebox("focus", type, _box(Color(0, 0, 0, 0), WHITE, 1, 5, 2))
		theme.set_color("font_color", type, WHITE)
		theme.set_color("font_hover_color", type, YELLOW)
		theme.set_color("font_focus_color", type, WHITE)
		theme.set_color("font_pressed_color", type, INK)
		theme.set_color("font_hover_pressed_color", type, INK)
		theme.set_color("font_disabled_color", type, GREY)
	theme.set_icon("arrow", "OptionButton", _icon("arrow", [
		"#######",
		".#####.",
		"..###..",
		"...#...",
	], {"#": WHITE}))
	theme.set_constant("arrow_margin", "OptionButton", 4)

	# Выпадающий список.
	theme.set_stylebox("panel", "PopupMenu", _box(PANEL, YELLOW, 1, 3, 3))
	theme.set_stylebox("hover", "PopupMenu", _box(ORANGE, ORANGE, 0, 2, 0))
	theme.set_color("font_color", "PopupMenu", WHITE)
	theme.set_color("font_hover_color", "PopupMenu", INK)
	theme.set_color("font_disabled_color", "PopupMenu", GREY)
	theme.set_constant("v_separation", "PopupMenu", 4)
	var radio_off := _icon("radio_off", [
		".####.",
		"#....#",
		"#....#",
		"#....#",
		"#....#",
		".####.",
	], {"#": GREY})
	var radio_on := _icon("radio_on", [
		".####.",
		"#....#",
		"#.##.#",
		"#.##.#",
		"#....#",
		".####.",
	], {"#": YELLOW})
	var check_off := _icon("check_off", [
		"#######",
		"#.....#",
		"#.....#",
		"#.....#",
		"#.....#",
		"#.....#",
		"#######",
	], {"#": GREY})
	var check_on := _icon("check_on", [
		"#######",
		"#.....#",
		"#.###.#",
		"#.###.#",
		"#.###.#",
		"#.....#",
		"#######",
	], {"#": YELLOW})
	for type in ["PopupMenu", "CheckBox"]:
		theme.set_icon("radio_unchecked", type, radio_off)
		theme.set_icon("radio_checked", type, radio_on)
		theme.set_icon("radio_unchecked_disabled", type, radio_off)
		theme.set_icon("radio_checked_disabled", type, radio_on)
		theme.set_icon("unchecked", type, check_off)
		theme.set_icon("checked", type, check_on)
		theme.set_icon("unchecked_disabled", type, check_off)
		theme.set_icon("checked_disabled", type, check_on)
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		theme.set_stylebox(state, "CheckBox", _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 2, 1))
	theme.set_color("font_hover_color", "CheckBox", YELLOW)

	# Поля ввода.
	theme.set_stylebox("normal", "LineEdit", _box(INK, GREY, 1, 4, 2))
	theme.set_stylebox("focus", "LineEdit", _box(Color(0, 0, 0, 0), YELLOW, 1, 4, 2))
	theme.set_stylebox("read_only", "LineEdit", _box(DARK_GREY, GREY, 1, 4, 2))
	theme.set_color("font_color", "LineEdit", WHITE)
	theme.set_color("font_placeholder_color", "LineEdit", GREY)
	theme.set_color("caret_color", "LineEdit", YELLOW)
	theme.set_color("selection_color", "LineEdit", Color(ORANGE, 0.6))

	# Ползунки (громкость).
	theme.set_stylebox("slider", "HSlider", _box(INK, GREY, 1, 0, 2))
	theme.set_stylebox("grabber_area", "HSlider", _box(ORANGE, ORANGE, 0, 0, 2))
	theme.set_stylebox("grabber_area_highlight", "HSlider", _box(YELLOW, YELLOW, 0, 0, 2))
	var grabber := _icon("grabber", [
		"######",
		"#yyyy#",
		"#yyyy#",
		"#yyyy#",
		"#yyyy#",
		"#yyyy#",
		"#yyyy#",
		"######",
	], {"#": INK, "y": YELLOW})
	theme.set_icon("grabber", "HSlider", grabber)
	theme.set_icon("grabber_highlight", "HSlider", grabber)
	theme.set_icon("grabber_disabled", "HSlider", grabber)

	# Панели.
	for type in ["Panel", "PanelContainer"]:
		theme.set_stylebox("panel", type, _box(PANEL, YELLOW, 1, 4, 4))
	theme.set_stylebox("panel", "TooltipPanel", _box(PANEL, YELLOW, 1, 3, 2))

	var err := ResourceSaver.save(theme, THEME_PATH)
	print("тема -> %s: %s" % [THEME_PATH, error_string(err)])
	quit(0 if err == OK else 1)


## Прямоугольник без скруглений и сглаживания; margin_x/margin_y — поля внутри, px.
func _box(bg: Color, border: Color, border_width: int, margin_x: int, margin_y: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(0)
	box.anti_aliasing = false
	box.content_margin_left = margin_x
	box.content_margin_right = margin_x
	box.content_margin_top = margin_y
	box.content_margin_bottom = margin_y
	return box


## Пиксельный значок из строк («.» — прозрачно); icon_name — для читаемости вызова.
func _icon(_icon_name: String, rows: Array, palette: Dictionary) -> Texture2D:
	var image := Image.create(rows[0].length(), rows.size(), false, Image.FORMAT_RGBA8)
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			var ch := row[x]
			image.set_pixel(x, y, palette.get(ch, Color(0, 0, 0, 0)))
	return ImageTexture.create_from_image(image)
