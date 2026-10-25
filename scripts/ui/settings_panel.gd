class_name SettingsPanel
extends PanelContainer
## Панель настроек (меню и пауза): громкость музыки и звуков, полный экран, автогаз.
## Изменения сразу применяются и сохраняются (GameSettings). «НАЗАД» — сигнал closed.

signal closed


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var box := VBoxContainer.new()
	add_child(box)
	var title := Label.new()
	title.text = "НАСТРОЙКИ"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	box.add_child(_slider("музыка", "music_volume"))
	box.add_child(_slider("звуки", "sfx_volume"))
	var fullscreen := CheckBox.new()
	fullscreen.text = "полный экран"
	fullscreen.button_pressed = bool(GameSettings.get_value("fullscreen", GameSettings.default_value("fullscreen")))
	fullscreen.toggled.connect(func(on: bool) -> void: GameSettings.set_value("fullscreen", on))
	box.add_child(fullscreen)
	var autogas := CheckBox.new()
	autogas.text = "автогаз"
	autogas.tooltip_text = "машина едет сама, тормоз — тормоз и задний ход"
	autogas.button_pressed = bool(GameSettings.get_value("autogas", GameSettings.default_value("autogas")))
	autogas.toggled.connect(func(on: bool) -> void: GameSettings.set_value("autogas", on))
	box.add_child(autogas)
	var back := Button.new()
	back.text = "НАЗАД"
	back.pressed.connect(func() -> void: closed.emit())
	box.add_child(back)
	back.grab_focus.call_deferred()


func _slider(caption: String, key: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = caption
	label.custom_minimum_size.x = 64
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.custom_minimum_size.x = 96
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value = float(GameSettings.get_value(key, GameSettings.default_value(key)))
	slider.value_changed.connect(func(value: float) -> void: GameSettings.set_value(key, value))
	row.add_child(slider)
	return row
