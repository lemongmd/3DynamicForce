extends SceneTree
## Пиксельная тема интерфейса -> ui/main_theme.tres (значки и кнопки — пиксельные картинки внутри темы).
##
## Стандартная тема Godot рисует скруглённые сглаженные углы и векторные значки — на экране
## 384×216, растянутом без сглаживания, они «мылятся». Здесь — набор окна лобби оригинала:
##   * панель — menupanelbg: 50 % чёрного, белая рамка 1 px со срезанными уголками;
##   * кнопка — «клавиша» InviteButton: белая с чёрной обводкой и выступом снизу, перекрашена
##     (синяя — главное действие, серо-синяя — остальные), нажатая утапливается на пиксель;
##   * текст — белый с тенью, заголовки — малиновые (#f50142, как спрайт «Лобби»).
## Варианты (theme_type_variation): ButtonSecondary, ButtonSmall, ButtonSmallSecondary,
## TitleLabel, HeadingLabel, BodyLabel, HintLabel, InsetPanel — их раздаёт UiStyle.
##
## Запуск: godot --headless --path . -s res://scripts/tools/build_ui_theme.gd

const THEME_PATH := "res://ui/main_theme.tres"
const FONT := preload("res://assets/fonts/df_text.res")
const KEY_SOURCE := "res://assets/original/textures/ui/invitebutton-000.png"
const PANEL_TEXTURE := preload("res://assets/original/textures/menu/menupanelbg.png")

const INK := Color(0.06, 0.06, 0.11)
const PANEL := Color(0.0, 0.0, 0.0, 0.8)
const WHITE := Color(1.0, 1.0, 1.0)
const GREY := Color(0.62, 0.65, 0.78)
## Синяя кнопка оригинала (InviteButton: rgb 36, 109, 255) и её состояния.
const BLUE := Color(0.14, 0.43, 1.0)
const BLUE_HOVER := Color(0.32, 0.58, 1.0)
const BLUE_PRESSED := Color(0.1, 0.32, 0.82)
const SLATE := Color(0.34, 0.36, 0.5)
const SLATE_HOVER := Color(0.46, 0.49, 0.66)
const SLATE_PRESSED := Color(0.27, 0.29, 0.41)
const DISABLED := Color(0.26, 0.26, 0.31)
const CRIMSON := Color("f50142")
const SHADOW := Color(0.0, 0.0, 0.0, 0.75)
## Поля внутри кнопки, px: по бокам, сверху, снизу (снизу — выступ клавиши).
const KEY_PAD := Vector3(8, 2, 4)
const SMALL_PAD := Vector3(7, 2, 4)


func _initialize() -> void:
	var theme := Theme.new()
	theme.default_font = FONT
	theme.default_font_size = 12

	# Кнопки (и OptionButton — наследник Button): «клавиша» InviteButton оригинала.
	var key := _key_textures()
	for type in ["Button", "OptionButton"]:
		_set_key(theme, type, key, BLUE, BLUE_HOVER, BLUE_PRESSED, KEY_PAD)
		# Фокус с клавиатуры/геймпада — белая рамка вокруг клавиши.
		var focus := _box(Color(0, 0, 0, 0), WHITE, 1, 0, 0)
		focus.draw_center = false
		focus.set_expand_margin_all(1)
		theme.set_stylebox("focus", type, focus)
		for state in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color",
				"font_hover_pressed_color"]:
			theme.set_color(state, type, WHITE)
		theme.set_color("font_disabled_color", type, Color(0.7, 0.7, 0.76))
		theme.set_constant("h_separation", type, 4)
	# Остальные действия (назад, выйти, настройки) — серо-синие.
	theme.set_type_variation("ButtonSecondary", "Button")
	_set_key(theme, "ButtonSecondary", key, SLATE, SLATE_HOVER, SLATE_PRESSED, KEY_PAD)
	# Маленькие кнопки (пригласить, копировать, стрелки карты, войти): текст 6, ниже.
	theme.set_type_variation("ButtonSmall", "Button")
	_set_key(theme, "ButtonSmall", key, BLUE, BLUE_HOVER, BLUE_PRESSED, SMALL_PAD)
	theme.set_font_size("font_size", "ButtonSmall", 6)
	theme.set_type_variation("ButtonSmallSecondary", "Button")
	_set_key(theme, "ButtonSmallSecondary", key, SLATE, SLATE_HOVER, SLATE_PRESSED, SMALL_PAD)
	theme.set_font_size("font_size", "ButtonSmallSecondary", 6)

	theme.set_icon("arrow", "OptionButton", _icon("arrow", [
		"#######",
		".#####.",
		"..###..",
		"...#...",
	], {"#": WHITE}))
	theme.set_constant("arrow_margin", "OptionButton", 4)

	# Надписи: белые с тенью (как текст окна лобби оригинала).
	theme.set_color("font_shadow_color", "Label", SHADOW)
	theme.set_constant("shadow_offset_x", "Label", 1)
	theme.set_constant("shadow_offset_y", "Label", 1)
	theme.set_constant("shadow_outline_size", "Label", 0)
	theme.set_constant("line_spacing", "Label", 2)
	# Заголовок окна — малиновый ×3 с чёрной тенью (спрайт «Лобби» оригинала).
	theme.set_type_variation("TitleLabel", "Label")
	theme.set_font_size("font_size", "TitleLabel", 18)
	theme.set_color("font_color", "TitleLabel", CRIMSON)
	theme.set_color("font_shadow_color", "TitleLabel", Color.BLACK)
	theme.set_constant("shadow_outline_size", "TitleLabel", 1)
	# Подзаголовок (×2) и основной текст (×1), подсказки — бледнее.
	theme.set_type_variation("HeadingLabel", "Label")
	theme.set_font_size("font_size", "HeadingLabel", 12)
	theme.set_type_variation("BodyLabel", "Label")
	theme.set_font_size("font_size", "BodyLabel", 6)
	theme.set_type_variation("HintLabel", "Label")
	theme.set_font_size("font_size", "HintLabel", 6)
	theme.set_color("font_color", "HintLabel", GREY)

	# Выпадающий список.
	theme.set_stylebox("panel", "PopupMenu", _box(PANEL, WHITE, 1, 3, 3))
	theme.set_stylebox("hover", "PopupMenu", _box(BLUE, BLUE, 0, 2, 0))
	theme.set_color("font_color", "PopupMenu", WHITE)
	theme.set_color("font_hover_color", "PopupMenu", WHITE)
	theme.set_color("font_disabled_color", "PopupMenu", GREY)
	theme.set_constant("v_separation", "PopupMenu", 4)
	var radio_off := _icon("radio_off", [
		".####.",
		"#kkkk#",
		"#kkkk#",
		"#kkkk#",
		"#kkkk#",
		".####.",
	], {"#": WHITE, "k": Color(0, 0, 0, 0.5)})
	var radio_on := _icon("radio_on", [
		".####.",
		"#oooo#",
		"#owwo#",
		"#owwo#",
		"#oooo#",
		".####.",
	], {"#": WHITE, "o": BLUE, "w": WHITE})
	# Флажок — квадрат в белой рамке на тёмном; включён — синий с белой галочкой.
	var check_off := _icon("check_off", [
		"#######",
		"#kkkkk#",
		"#kkkkk#",
		"#kkkkk#",
		"#kkkkk#",
		"#kkkkk#",
		"#######",
	], {"#": WHITE, "k": Color(0, 0, 0, 0.5)})
	var check_on := _icon("check_on", [
		"#######",
		"#ooooo#",
		"#oooow#",
		"#wooww#",
		"#owwwo#",
		"#oowoo#",
		"#######",
	], {"#": WHITE, "o": BLUE, "w": WHITE})
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
	var check_focus := _box(Color(0, 0, 0, 0), WHITE, 1, 2, 1)
	check_focus.draw_center = false
	theme.set_stylebox("focus", "CheckBox", check_focus)
	for state in ["font_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		theme.set_color(state, "CheckBox", WHITE)
	theme.set_color("font_hover_color", "CheckBox", BLUE_HOVER)
	theme.set_constant("h_separation", "CheckBox", 5)

	# Поле ввода — как панель (тёмное в белой рамке), в фокусе рамка синяя.
	theme.set_stylebox("normal", "LineEdit", _box(PANEL, Color(1, 1, 1, 0.8), 1, 5, 3))
	var field_focus := _box(Color(0, 0, 0, 0), BLUE_HOVER, 1, 5, 3)
	field_focus.draw_center = false
	theme.set_stylebox("focus", "LineEdit", field_focus)
	theme.set_stylebox("read_only", "LineEdit", _box(Color(0, 0, 0, 0.4), GREY, 1, 5, 3))
	theme.set_color("font_color", "LineEdit", WHITE)
	theme.set_color("font_placeholder_color", "LineEdit", Color(GREY, 0.8))
	theme.set_color("caret_color", "LineEdit", WHITE)
	theme.set_color("selection_color", "LineEdit", Color(BLUE, 0.7))

	# Ползунки (громкость): синяя заливка, ручка — маленькая белая «клавиша».
	theme.set_stylebox("slider", "HSlider", _box(PANEL, Color(1, 1, 1, 0.8), 1, 0, 2))
	theme.set_stylebox("grabber_area", "HSlider", _box(BLUE, BLUE, 0, 0, 2))
	theme.set_stylebox("grabber_area_highlight", "HSlider", _box(BLUE_HOVER, BLUE_HOVER, 0, 0, 2))
	var grabber := _icon("grabber", [
		".####.",
		"#wwww#",
		"#wwww#",
		"#wwww#",
		"#wwww#",
		"#wwww#",
		"######",
		"#gggg#",
		".####.",
	], {"#": INK, "w": WHITE, "g": Color(0.46, 0.46, 0.65)})
	theme.set_icon("grabber", "HSlider", grabber)
	theme.set_icon("grabber_highlight", "HSlider", grabber)
	theme.set_icon("grabber_disabled", "HSlider", grabber)

	# Панели — menupanelbg оригинала (9-patch), поля 12 × 10 px.
	for type in ["Panel", "PanelContainer"]:
		theme.set_stylebox("panel", type, _panel_box(Vector2(12, 10)))
	theme.set_stylebox("panel", "TooltipPanel", _box(PANEL, WHITE, 1, 4, 2))
	theme.set_font_size("font_size", "TooltipLabel", 6)
	# Вложенная плашка (ID игры, список игр): темнее, тонкая бледная рамка.
	theme.set_type_variation("InsetPanel", "PanelContainer")
	theme.set_stylebox("panel", "InsetPanel", _box(Color(0, 0, 0, 0.4), Color(1, 1, 1, 0.18), 1, 8, 5))

	var err := ResourceSaver.save(theme, THEME_PATH)
	print("тема -> %s: %s" % [THEME_PATH, error_string(err)])
	quit(0 if err == OK else 1)


## Клавиша InviteButton оригинала без значка: [обычная, нажатая] 16×16. Обычная — белое поле,
## чёрная обводка, снизу чёрная черта и выступ (#7575a5); нажатая — поле на пиксель ниже,
## выступа нет. Цвет даёт modulate_color стиля.
func _key_textures() -> Array[Texture2D]:
	var source := (load(KEY_SOURCE) as Texture2D).get_image()
	source.convert(Image.FORMAT_RGBA8)
	var normal := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			# Края — из краёв оригинала, середина — из чистого места правее значка.
			var sx := x if x < 2 else (source.get_width() - 16 + x if x >= 14 else 30)
			normal.set_pixel(x, y, source.get_pixel(sx, y))
	var pressed := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			var from := y
			if y >= 2 and y <= 13:
				from = y - 1
			elif y == 14:
				from = 13
			pressed.set_pixel(x, y, normal.get_pixel(x, from))
	return [ImageTexture.create_from_image(normal), ImageTexture.create_from_image(pressed)]


## Стили клавиши (normal/hover/pressed/disabled) типа type цветами color/hover/down.
func _set_key(theme: Theme, type: String, key: Array[Texture2D], color: Color, hover: Color, down: Color,
		pad: Vector3) -> void:
	theme.set_stylebox("normal", type, _key_box(key[0], color, pad, 0))
	theme.set_stylebox("hover", type, _key_box(key[0], hover, pad, 0))
	theme.set_stylebox("pressed", type, _key_box(key[1], down, pad, 1))
	theme.set_stylebox("hover_pressed", type, _key_box(key[1], down, pad, 1))
	theme.set_stylebox("disabled", type, _key_box(key[0], DISABLED, pad, 0))


## Клавиша: 9-patch (уголки 2 px, снизу 3 px — черта и выступ не тянутся); sink — на сколько
## опущен текст (нажатая).
func _key_box(texture: Texture2D, color: Color, pad: Vector3, sink: int) -> StyleBoxTexture:
	var box := StyleBoxTexture.new()
	box.texture = texture
	box.modulate_color = color
	box.texture_margin_left = 2
	box.texture_margin_right = 2
	box.texture_margin_top = 2
	box.texture_margin_bottom = 3
	box.content_margin_left = pad.x
	box.content_margin_right = pad.x
	box.content_margin_top = pad.y + sink
	box.content_margin_bottom = pad.z - sink
	return box


## Панель menupanelbg (9-patch, уголки 2 px) с полями margin.
func _panel_box(margin: Vector2) -> StyleBoxTexture:
	var box := StyleBoxTexture.new()
	box.texture = PANEL_TEXTURE
	box.set_texture_margin_all(2)
	box.content_margin_left = margin.x
	box.content_margin_right = margin.x
	box.content_margin_top = margin.y
	box.content_margin_bottom = margin.y
	return box


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
