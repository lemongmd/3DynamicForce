class_name PauseMenu
extends CanvasLayer
## Пауза (Esc / Start / кнопка «II» на сенсоре). Одиночная игра — игра на паузе:
## «ПРОДОЛЖИТЬ», «ЗАНОВО», «НАСТРОЙКИ», «В МЕНЮ». Сетевая — игра идёт дальше (остальные
## не ждут): «ПРОДОЛЖИТЬ», «НАСТРОЙКИ», «ВЫЙТИ».

var _panel: PanelContainer
var _settings: SettingsPanel
var _shade: ColorRect


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(GameActions.PAUSE):
		toggle()
		get_viewport().set_input_as_handled()


func is_open() -> bool:
	return visible


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	if visible:
		return
	visible = true
	if not Network.session().is_online():
		get_tree().paused = true
	_build()


func close() -> void:
	visible = false
	get_tree().paused = false
	for child in get_children():
		child.queue_free()
	_panel = null
	_settings = null


func _build() -> void:
	_shade = ColorRect.new()
	_shade.color = Color(0.0, 0.0, 0.0, 0.5)
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_shade)
	# Окно в общем стиле (UiStyle, как панель меню оригинала).
	_panel = UiStyle.panel()
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 4)
	_panel.add_child(box)
	box.add_child(UiStyle.title("ПАУЗА" if not Network.session().is_online() else "МЕНЮ"))
	var resume := _button(box, "ПРОДОЛЖИТЬ", close)
	if not Network.session().is_online():
		_button(box, "ЗАНОВО", func() -> void:
			close()
			get_tree().reload_current_scene())
	_button(box, "НАСТРОЙКИ", _open_settings)
	_button(box, "ВЫЙТИ" if Network.session().is_online() else "В МЕНЮ", func() -> void:
		close()
		Network.session().leave_to_menu())
	resume.grab_focus.call_deferred()


func _button(box: VBoxContainer, text: String, callback: Callable) -> Button:
	var button := UiStyle.button(text, callback)
	box.add_child(button)
	return button


func _open_settings() -> void:
	_panel.visible = false
	_settings = SettingsPanel.new()
	_settings.add_theme_stylebox_override(&"panel", UiStyle.panel_style())
	_settings.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_settings.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_settings.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_settings)
	_settings.closed.connect(func() -> void:
		_settings.queue_free()
		_settings = null
		_panel.visible = true)
