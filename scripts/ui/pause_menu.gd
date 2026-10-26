class_name PauseMenu
extends CanvasLayer
## Пауза (Esc / Start / кнопка «II» на сенсоре). Одиночная игра — игра на паузе:
## «ПРОДОЛЖИТЬ», «ЗАНОВО», «НАСТРОЙКИ», «В МЕНЮ». Сетевая — игра идёт дальше (остальные
## не ждут): «ПРОДОЛЖИТЬ», «НАСТРОЙКИ», «ВЫЙТИ».

var _panel: Control
var _settings: SettingsPanel
var _settings_window: Control
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
	_settings_window = null


func _build() -> void:
	_shade = ColorRect.new()
	_shade.color = Color(0.0, 0.0, 0.0, 0.5)
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_shade)
	# Окно в общем стиле (UiStyle): главное действие — синее, остальные — серо-синие.
	var online := Network.session().is_online()
	var box := UiStyle.column(UiStyle.GAP_SMALL)
	var resume := UiStyle.button("ПРОДОЛЖИТЬ", close)
	box.add_child(resume)
	if not online:
		box.add_child(UiStyle.button("ЗАНОВО", func() -> void:
			close()
			get_tree().reload_current_scene(), true, UiStyle.Kind.SECONDARY))
	box.add_child(UiStyle.button("НАСТРОЙКИ", _open_settings, true, UiStyle.Kind.SECONDARY))
	box.add_child(UiStyle.button("ВЫЙТИ" if online else "В МЕНЮ", func() -> void:
		close()
		Network.session().leave_to_menu(), true, UiStyle.Kind.SECONDARY))
	box.add_child(UiStyle.hint("Esc: продолжить"))
	_panel = UiStyle.window("МЕНЮ" if online else "ПАУЗА", box)
	add_child(_panel)
	resume.grab_focus.call_deferred()


func _open_settings() -> void:
	_panel.visible = false
	_settings = SettingsPanel.new()
	_settings_window = UiStyle.window("НАСТРОЙКИ", _settings)
	add_child(_settings_window)
	_settings.closed.connect(func() -> void:
		_settings_window.queue_free()
		_settings_window = null
		_settings = null
		_panel.visible = true)
