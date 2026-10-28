class_name Season
extends RefCounted
## Сезонное оформление меню. Хэллоуин — с 15 октября по 10 ноября (по часам компьютера):
## фон HalloweenBackground и ремикс Spark Main Theme вместо Menu_loop.
## Проверка вне сезона: «-- --halloween», выключить в сезон: «-- --no-halloween».

const HALLOWEEN_FROM := Vector2i(10, 15) # месяц, день
const HALLOWEEN_TO := Vector2i(11, 10)


static func is_halloween() -> bool:
	var args := OS.get_cmdline_user_args()
	if args.has("--halloween"):
		return true
	if args.has("--no-halloween"):
		return false
	var date := Time.get_date_dict_from_system()
	var today := Vector2i(date["month"], date["day"])
	return _not_before(today, HALLOWEEN_FROM) and _not_before(HALLOWEEN_TO, today)


static func _not_before(a: Vector2i, b: Vector2i) -> bool:
	return a.x > b.x or (a.x == b.x and a.y >= b.y)
