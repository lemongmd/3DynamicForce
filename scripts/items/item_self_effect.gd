class_name ItemSelfEffect
extends Item
## Предмет, который действует на свою машину: эффект в стеке CarEffects
## на duration секунд. Так устроены Nitro, NoDrift, Dash и Stop оригинала:
##   * Nitro — 1 с: max-speed ×1.5, acceleration ×4;
##   * NoDrift — 4 с: drift-recover ×16, friction ÷1.5, acceleration и deceleration ×2;
##   * Dash — рывок вперёд на 80 px (10 м) за 1/3 с: в оригинале 20 раз по 4 px
##     через кадр (move-forward); здесь — толчок 30 м/с по носу на 1/3 с;
##   * Stop (вантуз) — Car.stop + на 1/4 с drift-recover и acceleration ×255;
##   * Vodka — 2.5 с: max-speed ×1.25, drift-recover ÷2 и «пьяный» экран (Drunk).

## Длительность эффекта, с.
@export var duration: float = 1.0
## {параметр: множитель}, параметры — CarEffects.FIELDS.
@export var multipliers: Dictionary = {}
## Толчок по носу машины, пока действует эффект, м/с.
@export var forward_push: float = 0.0
## Сначала мгновенно остановить машину (Car.stop).
@export var stop_car: bool = false
## Эффект экрана на время действия (водка — &"drunk", эффект Drunk оригинала). Пусто — нет.
@export var screen_effect: StringName = &""
## Эффект машины при применении (CarFx.play_item_fx; рывок — &"dash"). Пусто — нет.
@export var use_fx: StringName = &""


func use(car: CarController) -> void:
	if stop_car:
		car.stop()
	var effects := CarEffects.of(car)
	if effects == null:
		push_warning("ItemSelfEffect: у машины нет узла Effects.")
		return
	effects.add(id, duration, multipliers.duplicate(), forward_push)
	if use_fx != &"":
		var fx := car.get_node_or_null(^"Fx") as CarFx
		if fx != null:
			fx.play_item_fx(use_fx, duration)
	if screen_effect == &"drunk":
		for node in car.get_tree().get_nodes_in_group(ScreenEffects.GROUP):
			(node as ScreenEffects).drunk(car, duration)


func get_duration() -> float:
	return duration
