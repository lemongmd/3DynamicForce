class_name SettingsPanel
extends VBoxContainer
## Содержимое окна настроек (меню и пауза): громкость музыки и звуков, полный экран, автогаз.
## Заголовок и рамку даёт окно вокруг (UiStyle.window в паузе, страница меню). Изменения сразу
## применяются и сохраняются (GameSettings). «НАЗАД» — сигнал closed.

signal closed

## Ширина ползунка громкости, px.
const SLIDER_WIDTH := 96.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override(&"separation", UiStyle.GAP)
	# Громкость: подпись | ползунок | проценты — колонками, ровно друг под другом.
	var volumes := GridContainer.new()
	volumes.columns = 3
	volumes.add_theme_constant_override(&"h_separation", 8)
	volumes.add_theme_constant_override(&"v_separation", 6)
	volumes.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	add_child(volumes)
	var first := _slider(volumes, "музыка", "music_volume")
	_slider(volumes, "звуки", "sfx_volume")
	var checks := VBoxContainer.new()
	checks.add_theme_constant_override(&"separation", UiStyle.GAP_SMALL)
	checks.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	add_child(checks)
	checks.add_child(_check("полный экран", "fullscreen", ""))
	checks.add_child(_check("автогаз", "autogas", "машина газует сама, а тормоз работает и как задний ход"))
	add_child(UiStyle.button("НАЗАД", func() -> void: closed.emit(), true, UiStyle.Kind.SECONDARY))
	first.grab_focus.call_deferred()


func _slider(grid: GridContainer, caption: String, key: String) -> HSlider:
	var label := UiStyle.heading(caption)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	grid.add_child(label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.custom_minimum_size.x = SLIDER_WIDTH
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value = float(GameSettings.get_value(key, GameSettings.default_value(key)))
	grid.add_child(slider)
	var percent := UiStyle.hint("")
	percent.custom_minimum_size.x = 20
	percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	grid.add_child(percent)
	var show := func(value: float) -> void: percent.text = "%d%%" % roundi(value * 100.0)
	show.call(slider.value)
	slider.value_changed.connect(func(value: float) -> void:
		GameSettings.set_value(key, value)
		show.call(value))
	return slider


func _check(caption: String, key: String, tip: String) -> CheckBox:
	var check := CheckBox.new()
	check.text = caption
	check.tooltip_text = tip
	check.button_pressed = bool(GameSettings.get_value(key, GameSettings.default_value(key)))
	check.toggled.connect(func(on: bool) -> void: GameSettings.set_value(key, on))
	return check
