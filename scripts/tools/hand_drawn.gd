extends RefCounted
## Картинки, перерисованные вручную (список assets/hand_drawn.txt): генераторы
## build_*.gd их не перезаписывают. Подключать через preload (в -s скриптах нет class_name-кэша).

const LIST := "res://assets/hand_drawn.txt"


static func is_hand_drawn(res_path: String) -> bool:
	var file := FileAccess.open(LIST, FileAccess.READ)
	if file == null:
		return false
	var relative := res_path.trim_prefix("res://")
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line == relative:
			return true
	return false


## Сохраняет картинку, если её не перерисовали вручную. true — сохранена.
static func save_png(image: Image, res_path: String) -> bool:
	if is_hand_drawn(res_path):
		print("пропущено (нарисовано вручную, assets/hand_drawn.txt): ", res_path)
		return false
	image.save_png(ProjectSettings.globalize_path(res_path))
	print("saved: ", res_path)
	return true
