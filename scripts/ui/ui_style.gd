class_name UiStyle
extends RefCounted
## Общий вид окон интерфейса (лобби, результаты, пауза, настройки в паузе), как панель меню
## оригинала (menupanelbg: белая рамка, тёмное полупрозрачное поле): одинаковые отступы,
## заголовки 12, текст 6, кнопки одной ширины. Раньше у каждого окна был свой размер шрифта
## и свои поля — смотрелось криво.

const PANEL_TEXTURE := preload("res://assets/original/textures/menu/menupanelbg.png")
## Поля внутри окна, px.
const PADDING := Vector2(12, 10)
## Ширина кнопок окна, px.
const BUTTON_WIDTH := 112.0
const OUTLINE := Color(0.12, 0.05, 0.1)
const TITLE_COLOR := Color(1.0, 0.85, 0.3)
## Свой ник — зелёный, как в оригинале (#0f3).
const OWN_COLOR := Color(0.0, 1.0, 0.2)


static func panel_style() -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = PANEL_TEXTURE
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_texture_margin(side, 3.0)
	style.content_margin_left = PADDING.x
	style.content_margin_right = PADDING.x
	style.content_margin_top = PADDING.y
	style.content_margin_bottom = PADDING.y
	return style


## Окно-панель по центру экрана (якорь — центр, растёт во все стороны).
static func panel() -> PanelContainer:
	var container := PanelContainer.new()
	container.add_theme_stylebox_override(&"panel", panel_style())
	container.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	container.grow_horizontal = Control.GROW_DIRECTION_BOTH
	container.grow_vertical = Control.GROW_DIRECTION_BOTH
	return container


static func title(value: String) -> Label:
	var label := Label.new()
	label.text = value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override(&"font_color", TITLE_COLOR)
	label.add_theme_color_override(&"font_outline_color", OUTLINE)
	label.add_theme_constant_override(&"outline_size", 3)
	return label


static func text(value: String, color: Color = Color.WHITE) -> Label:
	var label := Label.new()
	label.text = value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override(&"font_size", 6)
	label.add_theme_color_override(&"font_color", color)
	return label


## Кнопка окна: одной ширины, по центру. Без фокуса с клавиатуры (focusable = false) —
## чтобы пробел/Enter в гонке не нажимали её случайно (пробел — парирование).
static func button(label: String, callback: Callable, focusable: bool = true) -> Button:
	var result := Button.new()
	result.text = label
	result.custom_minimum_size = Vector2(BUTTON_WIDTH, 0)
	result.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	result.pressed.connect(callback)
	if not focusable:
		result.focus_mode = Control.FOCUS_NONE
	return result
