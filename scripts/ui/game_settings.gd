class_name GameSettings
extends RefCounted
## Настройки игрока (user://settings.cfg, там же ник и карта меню): громкость музыки
## и звуков (шины Music и SFX), полный экран, автогаз. apply() — применить сохранённые (при запуске).

const PATH := "user://settings.cfg"
const SECTION := "settings"

## Автогаз: машина едет сама, тормоз — назад (читает PlayerInputSource каждый кадр,
## поэтому значение держится здесь, а не читается из файла).
static var autogas: bool = false


static func get_value(key: String, default: Variant) -> Variant:
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return default
	return config.get_value(SECTION, key, default)


static func set_value(key: String, value: Variant) -> void:
	var config := ConfigFile.new()
	config.load(PATH)
	config.set_value(SECTION, key, value)
	config.save(PATH)
	_apply_one(key, value)


## Применить все сохранённые настройки.
static func apply() -> void:
	for key in ["music_volume", "sfx_volume", "fullscreen", "autogas"]:
		_apply_one(key, get_value(key, default_value(key)))


static func default_value(key: String) -> Variant:
	match key:
		"music_volume":
			return 0.8
		"sfx_volume":
			return 1.0
		"fullscreen":
			return false
		"autogas":
			# На телефоне жать газ пальцем всю гонку неудобно — там включён по умолчанию.
			return OS.has_feature("mobile")
	return null


static func _apply_one(key: String, value: Variant) -> void:
	match key:
		"autogas":
			autogas = bool(value)
		"music_volume":
			_set_bus_volume(&"Music", float(value))
		"sfx_volume":
			_set_bus_volume(&"SFX", float(value))
		"fullscreen":
			if DisplayServer.get_name() == "headless":
				return
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if bool(value)
					else DisplayServer.WINDOW_MODE_WINDOWED)


static func _set_bus_volume(bus_name: StringName, volume: float) -> void:
	var bus := AudioServer.get_bus_index(bus_name)
	if bus < 0:
		return
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(volume, 0.0001)))
	AudioServer.set_bus_mute(bus, volume <= 0.001)
