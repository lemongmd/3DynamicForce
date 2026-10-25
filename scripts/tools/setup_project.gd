extends SceneTree
## Записывает в project.godot карту ввода (InputMap) и настройки импорта по умолчанию.
##
## Запуск из корня проекта:
##   godot --headless --path . -s res://scripts/tools/setup_project.gd
##
## ВНИМАНИЕ: перезаписывает действия, перечисленные ниже. Если меняешь привязки
## в редакторе, либо правь и этот файл, либо больше его не запускай.

const Actions := preload("res://scripts/input/game_actions.gd")

## Мёртвая зона для аналоговых осей (стики, курки).
const ANALOG_DEADZONE := 0.2


func _init() -> void:
	_set_action(Actions.STEER_LEFT, ANALOG_DEADZONE, [
		_key(KEY_A), _key(KEY_LEFT),
		_joy_axis(JOY_AXIS_LEFT_X, -1.0), _joy_button(JOY_BUTTON_DPAD_LEFT),
	])
	_set_action(Actions.STEER_RIGHT, ANALOG_DEADZONE, [
		_key(KEY_D), _key(KEY_RIGHT),
		_joy_axis(JOY_AXIS_LEFT_X, 1.0), _joy_button(JOY_BUTTON_DPAD_RIGHT),
	])
	_set_action(Actions.ACCELERATE, ANALOG_DEADZONE, [
		_key(KEY_W), _key(KEY_UP),
		_joy_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0), _joy_button(JOY_BUTTON_A),
	])
	_set_action(Actions.BRAKE, ANALOG_DEADZONE, [
		_key(KEY_S), _key(KEY_DOWN),
		_joy_axis(JOY_AXIS_TRIGGER_LEFT, 1.0), _joy_button(JOY_BUTTON_B),
	])
	# Клавиатура (просьба автора оригинала: «до E тянуться не кайф»): пробел — парирование
	# (большой палец, нужен точный момент), Q — предмет, Shift — дрифт (наш).
	# Геймпад (наше решение): газ/тормоз на курках или A/B, парирование — X (большой палец
	# свободен, если газ на курке), предмет — Y или LB, дрифт — RB.
	_set_action(Actions.DRIFT, 0.5, [
		_key(KEY_SHIFT), _joy_button(JOY_BUTTON_RIGHT_SHOULDER),
	])
	_set_action(Actions.PARRY, 0.5, [
		_key(KEY_SPACE), _joy_button(JOY_BUTTON_X),
	])
	_set_action(Actions.USE_ITEM, 0.5, [
		_key(KEY_Q), _joy_button(JOY_BUTTON_LEFT_SHOULDER), _joy_button(JOY_BUTTON_Y),
	])
	_set_action(Actions.PAUSE, 0.5, [
		_key(KEY_ESCAPE), _joy_button(JOY_BUTTON_START),
	])
	# Общая громкость, как в оригинале: держать − / + (= и цифровой блок).
	_set_action(Actions.VOLUME_DOWN, 0.5, [
		_key(KEY_MINUS), _key(KEY_KP_SUBTRACT),
	])
	_set_action(Actions.VOLUME_UP, 0.5, [
		_key(KEY_EQUAL), _key(KEY_KP_ADD),
	])
	# «Принять» в интерфейсе — без пробела: пробел теперь парирование, и в гонке он не должен
	# нажимать кнопки окон (лобби, результаты). Enter и A геймпада — как обычно.
	_set_action(&"ui_accept", 0.5, [
		_key(KEY_ENTER), _key(KEY_KP_ENTER), _joy_button(JOY_BUTTON_A),
	])
	_set_action(Actions.DEBUG_RESET, 0.5, [
		_key(KEY_R), _joy_button(JOY_BUTTON_BACK),
	])
	_set_action(Actions.DEBUG_TOUCH_CONTROLS, 0.5, [
		_key(KEY_F1),
	])

	# Пиксельные текстуры: без VRAM-сжатия (оно размывает пиксели блоками 4x4),
	# мипмапы нужны, чтобы мелкий узор не «рябил» сверху.
	ProjectSettings.set_setting("importer_defaults/texture", {
		"compress/mode": 0,
		"detect_3d/compress_to": 0,
		"mipmaps/generate": true,
	})

	# Пиксельные шрифты (как в оригинале): без сглаживания, хинтинга и субпикселей.
	ProjectSettings.set_setting("importer_defaults/font_data_dynamic", {
		"antialiasing": 0,
		"hinting": 0,
		"subpixel_positioning": 0,
	})

	# Сеть (этап 6): автозагрузка Net (scripts/net/net.gd, класс Network, на аддоне Tube).
	ProjectSettings.set_setting("autoload/Net", "*res://scripts/net/net.gd")
	ProjectSettings.set_setting("autoload/Music", "*res://scripts/audio/game_music.gd")
	ProjectSettings.set_setting("autoload/PixelUi", "*res://scripts/ui/pixel_ui.gd")
	ProjectSettings.set_setting("autoload/Volume", "*res://scripts/ui/master_volume.gd")

	# Редактор карт (панель «Трасса», addons/track_editor).
	ProjectSettings.set_setting("editor_plugins/enabled",
			PackedStringArray(["res://addons/track_editor/plugin.cfg", "res://addons/tube/plugin.cfg"]))

	var err := ProjectSettings.save()
	if err != OK:
		push_error("Не удалось сохранить project.godot: %s" % error_string(err))
		quit(1)
		return
	print("project.godot обновлён: InputMap и настройки импорта записаны.")
	quit(0)


func _set_action(action: StringName, deadzone: float, events: Array) -> void:
	ProjectSettings.set_setting("input/" + String(action), {
		"deadzone": deadzone,
		"events": events,
	})


## Клавиша по физическому положению: WASD работает и в русской раскладке.
func _key(physical: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.device = -1
	event.physical_keycode = physical
	return event


func _joy_button(button: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.device = -1
	event.button_index = button
	return event


func _joy_axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.device = -1
	event.axis = axis
	event.axis_value = value
	return event
