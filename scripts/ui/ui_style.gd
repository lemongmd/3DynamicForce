class_name UiStyle
extends RefCounted
## Общий вид окон интерфейса — как окно лобби оригинала (тема ui/main_theme.tres, собирает
## build_ui_theme.gd): панель menupanelbg, малиновый заголовок, наложенный на верхнюю рамку,
## белый текст с тенью, синие кнопки-«клавиши». Все окна (лобби, результаты, пауза, настройки)
## собираются отсюда — одинаковые поля и отступы:
##   * поля панели 12 × 10 px (с заголовком сверху — больше, под его нижнюю половину);
##   * между блоками окна — GAP, между строками блока и кнопками — GAP_SMALL;
##   * кнопки столбиком — одной ширины BUTTON_WIDTH.

## Синяя кнопка — главное действие, серо-синяя — остальные, маленькие — текст 6.
enum Kind { PRIMARY, SECONDARY, SMALL, SMALL_SECONDARY }

## Поля внутри окна, px (по бокам, сверху/снизу).
const PADDING := Vector2(12, 10)
## Заголовок наложен на верхнюю рамку на столько px (половина строки ×3).
const TITLE_OVERLAP := 10
## Сколько добавить к верхнему полю панели под заголовком (его нижняя половина — внутри).
const TITLE_TOP_EXTRA := 8.0
const GAP := 8
const GAP_SMALL := 4
## Ширина кнопок окна, px.
const BUTTON_WIDTH := 120.0
const TITLE_COLOR := Color("f50142")
const OUTLINE := Color(0.0, 0.0, 0.0)
## Свой ник — зелёный, как в оригинале (#0f3).
const OWN_COLOR := Color(0.0, 1.0, 0.2)
## «Скопировано!»: кнопка вспыхивает зелёным и за секунду синеет (InviteButton оригинала).
const FLASH_COLOR := Color8(0, 235, 27)
const FLASH_TIME := 1.0
const FLASH_TEXT_TIME := 0.9
const BLUE := Color(0.14, 0.43, 1.0)
const HINT_COLOR := Color(0.62, 0.65, 0.78)

const VARIATIONS := {Kind.PRIMARY: &"", Kind.SECONDARY: &"ButtonSecondary",
		Kind.SMALL: &"ButtonSmall", Kind.SMALL_SECONDARY: &"ButtonSmallSecondary"}


## Стиль панели (как у темы) с полями padding; для окон с заголовком — top больше.
static func panel_style(top_extra: float = 0.0, padding: Vector2 = PADDING) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = preload("res://assets/original/textures/menu/menupanelbg.png")
	style.set_texture_margin_all(2)
	style.content_margin_left = padding.x
	style.content_margin_right = padding.x
	style.content_margin_top = padding.y + top_extra
	style.content_margin_bottom = padding.y
	return style


## Окно-панель по центру экрана (якорь — центр, растёт во все стороны).
static func panel() -> PanelContainer:
	var container := PanelContainer.new()
	container.add_theme_stylebox_override(&"panel", panel_style())
	_center(container)
	return container


## Окно с заголовком на верхней рамке (как «Лобби» оригинала): заголовок — текст или картинка
## (title_texture), content — содержимое панели. Возвращает узел окна (по центру экрана);
## панель внутри — window.get_meta(&"panel").
static func window(title_text: String, content: Control, title_texture: Texture2D = null,
		padding: Vector2 = PADDING) -> VBoxContainer:
	var root := VBoxContainer.new()
	root.name = "Window"
	var overlap := TITLE_OVERLAP
	var heading: Control
	if title_texture != null:
		# Картинка с пустыми полями (спрайт «Лобби» 80×40): на рамку ложится половина букв.
		var used := title_texture.get_image().get_used_rect()
		overlap = title_texture.get_height() - used.end.y + used.size.y / 2
		var picture := TextureRect.new()
		picture.texture = title_texture
		picture.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		heading = picture
	else:
		heading = title(title_text)
	root.add_theme_constant_override(&"separation", -overlap)
	heading.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	# Заголовок рисуется поверх рамки панели.
	heading.z_index = 1
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(heading)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override(&"panel", panel_style(TITLE_TOP_EXTRA, padding))
	frame.add_child(content)
	root.add_child(frame)
	root.set_meta(&"panel", frame)
	_center(root)
	return root


## Столбик содержимого окна с отступом separation между строками.
static func column(separation: int = GAP) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override(&"separation", separation)
	return box


## Строка по центру (кнопки рядом, «ID + пригласить»).
static func row(separation: int = GAP_SMALL) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override(&"separation", separation)
	return box


## Заголовок окна: малиновый ×3 с тенью.
static func title(value: String) -> Label:
	return _label(value, &"TitleLabel")


## Подзаголовок ×2 (название карты, «в комнате нет людей!»).
static func heading(value: String, color: Color = Color.WHITE) -> Label:
	var label := _label(value, &"HeadingLabel")
	if color != Color.WHITE:
		label.add_theme_color_override(&"font_color", color)
	return label


## Основной текст ×1.
static func text(value: String, color: Color = Color.WHITE) -> Label:
	var label := _label(value, &"BodyLabel")
	if color != Color.WHITE:
		label.add_theme_color_override(&"font_color", color)
	return label


## Подсказка ×1, бледная (клавиши, состояние сети).
static func hint(value: String) -> Label:
	return _label(value, &"HintLabel")


## Кнопка окна. PRIMARY/SECONDARY — одной ширины, по центру; SMALL — по тексту.
## focusable = false — без фокуса с клавиатуры: пробел (парирование) и Enter в гонке не нажмут
## её случайно.
static func button(label: String, callback: Callable, focusable: bool = true, kind: Kind = Kind.PRIMARY) -> Button:
	var result := Button.new()
	result.text = label
	result.theme_type_variation = VARIATIONS[kind]
	if kind == Kind.PRIMARY or kind == Kind.SECONDARY:
		result.custom_minimum_size = Vector2(BUTTON_WIDTH, 0)
	result.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	result.pressed.connect(callback)
	if not focusable:
		result.focus_mode = Control.FOCUS_NONE
	return result


## «Получилось» (скопировано): кнопка вспыхивает зелёным и синеет за FLASH_TIME, текст на
## FLASH_TEXT_TIME сменяется на done_text — как InviteButton оригинала.
static func flash(target: Button, done_text: String) -> void:
	var original_text := target.text
	if target.has_meta(&"flash_text"):
		original_text = String(target.get_meta(&"flash_text"))
	target.set_meta(&"flash_text", original_text)
	var normal := target.get_theme_stylebox(&"normal").duplicate() as StyleBoxTexture
	if normal != null:
		var base := normal.modulate_color
		normal.modulate_color = FLASH_COLOR
		target.add_theme_stylebox_override(&"normal", normal)
		target.add_theme_stylebox_override(&"hover", normal)
		var tween := target.create_tween()
		tween.tween_property(normal, ^"modulate_color", base, FLASH_TIME) \
				.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
		tween.tween_callback(func() -> void:
			target.remove_theme_stylebox_override(&"normal")
			target.remove_theme_stylebox_override(&"hover"))
	target.text = done_text
	target.get_tree().create_timer(FLASH_TEXT_TIME).timeout.connect(func() -> void:
		if is_instance_valid(target):
			target.text = original_text
			target.remove_meta(&"flash_text"))


static func _label(value: String, variation: StringName) -> Label:
	var label := Label.new()
	label.text = value
	label.theme_type_variation = variation
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


## По центру экрана, ровно по содержимому: прямоугольник нулевого размера в точке привязки
## растёт во все стороны до минимального размера (иначе оставались старые отступы — окно
## бывало шире содержимого).
static func _center(control: Control) -> void:
	anchor_at(control, Control.PRESET_CENTER, Control.GROW_DIRECTION_BOTH)


## Привязать окно к точке экрана preset (центр, середина верха…) без лишних отступов.
static func anchor_at(control: Control, preset: Control.LayoutPreset, grow_vertical: Control.GrowDirection,
		offset: Vector2 = Vector2.ZERO) -> void:
	control.set_anchors_preset(preset)
	control.grow_horizontal = Control.GROW_DIRECTION_BOTH
	control.grow_vertical = grow_vertical
	control.offset_left = offset.x
	control.offset_right = offset.x
	control.offset_top = offset.y
	control.offset_bottom = offset.y
