class_name DebugHud
extends CanvasLayer
## Отладочная панель для тестовых сцен: скорость, дрифт, ввод.
## Позволяет проверить, что клавиатура, геймпад и сенсор дают одинаковый ввод.

## Машина, состояние которой показывается.
@export var car: CarController

## Сколько секунд показывать «нажато» для разовых кнопок.
const FLASH_TIME := 0.4

var _parry_flash: float = 0.0
var _item_flash: float = 0.0

@onready var _label: Label = $Margin/Label


func _ready() -> void:
	if car != null:
		car.parry_requested.connect(func() -> void: _parry_flash = FLASH_TIME)
		car.item_requested.connect(func() -> void: _item_flash = FLASH_TIME)


func _process(delta: float) -> void:
	_parry_flash = maxf(_parry_flash - delta, 0.0)
	_item_flash = maxf(_item_flash - delta, 0.0)
	if car == null:
		_label.text = "DebugHud: машина не назначена"
		return
	var input := car.current_input
	var drift_text := "нет"
	if car.is_drifting:
		drift_text = "вправо" if car.drift_direction > 0 else "влево"
	var lines := PackedStringArray([
		"FPS: %d" % Engine.get_frames_per_second(),
		"Скорость: %.1f м/с (%.0f%%)" % [car.forward_speed, car.get_speed_ratio() * 100.0],
		"Дрифт: %s  занос: %.0f°" % [drift_text, rad_to_deg(car.get_slide_angle())],
		"Руль %+.2f  Газ %+.2f  Дрифт %s" % [input.steer, input.throttle, "да" if input.drift else "нет"],
		"Парир: %s  Предмет: %s" % ["ДА" if _parry_flash > 0.0 else "-", "ДА" if _item_flash > 0.0 else "-"],
		"WASD, Shift дрифт, E парир, пробел предмет",
		"R сброс, F1 сенсор",
	])
	_label.text = "\n".join(lines)
