class_name TouchControls
extends CanvasLayer
## Слой сенсорного управления.
##
## Как в оригинале: только кнопки, автогаза нет. Руль, газ и тормоз — стрелки
## оригинала (слева ◀ ▶, справа ▲ ▼), рядом круглые дрифт/парирование/предмет.
##
## Видимость: на мобильных — сразу; на ПК — после первого настоящего касания
## экрана (не эмулированного мышью), клавишей F1 (действие debug_touch_controls)
## или с аргументом запуска `-- --touch`. Мышь в проекте эмулирует касания
## (input_devices/pointing/emulate_touch_from_mouse), поэтому показанные кнопки
## нажимаются и мышкой.

## Сколько места снизу занимают кнопки руля (для раскладки HUD), px.
const BOTTOM_INSET := 56.0


func _ready() -> void:
	visible = OS.has_feature("mobile") or "--touch" in OS.get_cmdline_user_args()


func _input(event: InputEvent) -> void:
	if not visible and event is InputEventScreenTouch \
			and event.device != InputEvent.DEVICE_ID_EMULATION:
		visible = true


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(GameActions.DEBUG_TOUCH_CONTROLS):
		visible = not visible
		get_viewport().set_input_as_handled()
