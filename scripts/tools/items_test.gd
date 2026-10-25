extends SceneTree
## Автоматическая проверка этапов 4 и 5: стек эффектов (CarEffects), все 12 предметов,
## коробка предметов (ItemBox) и слот предмета в HUD гонки.
## Этап 5 — две машины: A (хозяин предмета, «свой» игрок) и B (соперник): попадания,
## парирование, хозяина не задевает, время жизни объектов, вспышка и «пьяный» экран.
##
## Запуск (из корня проекта):
##   godot --headless --path . -s res://scripts/tools/items_test.gd
## Код возврата 0 — всё прошло, 1 — есть ошибки.

const LEVEL_PATH := "res://scenes/levels/test_level.tscn"
const RACE_PATH := "res://scenes/race/race.tscn"
const ITEM_BOX_PATH := "res://scenes/objects/item_box.tscn"
const TRACK_PATH := "res://scenes/tracks/remake_01.tscn"
## Пустой угол тестовой площадки (как в smoke_test).
const TEST_SPOT := Vector3(60.0, 0.05, 70.0)
## Свободная полоса площадки для двух машин (едут к −Z).
const DUEL_SPOT := Vector3(90.0, 0.05, 160.0)
const CAR_PATH := "res://scenes/car/car.tscn"
const SCREEN_EFFECTS_PATH := "res://scenes/fx/screen_effects.tscn"


## Управление соперником в тестах: газ и разовое парирование.
class ScriptedInput extends CarInputSource:
	var throttle: float = 0.0
	var parry_once: bool = false

	func read_input(out: CarInput) -> void:
		out.clear()
		out.throttle = throttle
		out.parry_pressed = parry_once
		parry_once = false

var _failures: PackedStringArray = []
var _level: Node
var _car: CarController
var _effects: CarEffects
var _items: CarItems


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_level = (load(LEVEL_PATH) as PackedScene).instantiate()
	root.add_child(_level)
	_car = _level.get_node("Car") as CarController
	_effects = CarEffects.of(_car)
	_items = CarItems.of(_car)
	await _frames(10)
	_check(_effects != null and _items != null, "у машины есть узлы Effects и Items")
	_check(ItemCatalog.all().size() == 13, "в каталоге 12 предметов оригинала + помидор (%d)" % ItemCatalog.all().size())

	_test_place_items()
	await _test_effect_stack()
	await _test_nitro()
	await _test_nodrift()
	await _test_dash()
	await _test_stop()
	await _test_item_box()
	_release_all()
	await _test_stage5_items()
	_level.queue_free()
	await _frames(10)
	await _test_race_boxes_and_hud()

	if _failures.is_empty():
		print("ITEMS TEST: ВСЁ ПРОШЛО")
		quit(0)
	else:
		print("ITEMS TEST: ОШИБКИ (%d)" % _failures.size())
		for failure in _failures:
			print("  - ", failure)
		quit(1)


## Записи стека перемножаются и снимаются каждая в свой срок (как ×k / wait / ÷k оригинала).
func _test_effect_stack() -> void:
	await _place(TEST_SPOT)
	_effects.add(&"test", 0.5, {&"max_speed": 1.5})
	_effects.add(&"test", 1.0, {&"max_speed": 1.5})
	_check(is_equal_approx(_car.max_speed_multiplier, 2.25),
			"два эффекта ×1.5 складываются в ×2.25 (%.3f)" % _car.max_speed_multiplier)
	await _frames(40)
	_check(is_equal_approx(_car.max_speed_multiplier, 1.5),
			"первый эффект кончился через 0.5 с, второй держится (%.3f)" % _car.max_speed_multiplier)
	await _frames(30)
	_check(is_equal_approx(_car.max_speed_multiplier, 1.0) and _effects.get_effects().is_empty(),
			"второй кончился через 1 с, множитель вернулся к 1")


func _test_nitro() -> void:
	await _place(TEST_SPOT)
	_items.give(ItemCatalog.by_id(&"nitro"))
	_check(_items.current != null and _items.current.id == &"nitro", "нитро в слоте")
	Input.action_press(GameActions.ACCELERATE)
	await _frames(5)
	await _press_item()
	_check(_items.current == null, "после применения слот пуст")
	_check(_effects.has_effect(&"nitro"), "нитро действует")
	_check(is_equal_approx(_car.get_max_speed(), _car.max_speed * 1.5),
			"нитро: предел скорости ×1.5 (%.1f м/с)" % _car.get_max_speed())
	_check(is_equal_approx(_car.acceleration_multiplier, 4.0), "нитро: разгон ×4")
	await _frames(50)
	_check(_car.forward_speed > _car.max_speed + 1.0,
			"под нитро машина быстрее обычного предела (%.1f м/с)" % _car.forward_speed)
	await _frames(15)
	_check(not _effects.has_effect(&"nitro"), "нитро кончилось через 1 с")
	_check(_car.forward_speed <= _car.max_speed + 0.01,
			"после нитро скорость снова не выше предела (%.1f м/с)" % _car.forward_speed)
	_release_all()


func _test_nodrift() -> void:
	await _place(TEST_SPOT)
	_items.give(ItemCatalog.by_id(&"nodrift"))
	await _press_item()
	# Как в оригинале + руль ×1.3 (предмет — про управление, скорость не трогает).
	_check(is_equal_approx(_car.drift_recover_multiplier, 16.0)
			and is_equal_approx(_car.acceleration_multiplier, 2.0)
			and is_equal_approx(_car.deceleration_multiplier, 2.0)
			and is_equal_approx(_car.steering_multiplier, 1.3)
			and is_equal_approx(_car.max_speed_multiplier, 1.0)
			and is_equal_approx(_car.wall_friction_multiplier, 0.666667),
			"липкая резина: сцепление ×16, разгон и торможение ×2, руль ×1.3, предел без изменений")
	await _frames(4 * 60 + 5)
	_check(not _effects.has_effect(&"nodrift") and is_equal_approx(_car.drift_recover_multiplier, 1.0),
			"липкая резина кончилась через 4 с")


## Предметы по месту: у лидера реже догоняющие (нитро, рывок), у последнего — чаще;
## без места (лобби, одиночный заезд) — все равновероятно.
func _test_place_items() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var catch_up := [&"nitro", &"dash", &"bullet", &"flash"]
	var counts := {0.0: 0, 1.0: 0}
	for share in [0.0, 1.0]:
		for i in 3000:
			if ItemCatalog.item_for_place(share, rng).id in catch_up:
				counts[share] += 1
	_check(counts[1.0] > counts[0.0] * 2,
			"предметы по месту: у последнего догоняющих (нитро/рывок/лазер/флешка) больше, чем у первого (%d против %d из 3000)"
			% [counts[1.0], counts[0.0]])
	var seen := {}
	for i in 600:
		seen[ItemCatalog.item_for_place(-1.0, rng).id] = true
	_check(seen.size() == ItemCatalog.all().size(), "без места — все %d предметов (%d)" % [ItemCatalog.all().size(), seen.size()])
	for item in ItemCatalog.all():
		_check(ItemCatalog.PLACE_WEIGHTS.has(item.id), "вес по месту задан для «%s»" % item.id)


## Рывок: 10 м вперёд за 1/3 с (в оригинале 20 раз по 4 px).
func _test_dash() -> void:
	await _place(TEST_SPOT)
	_items.give(ItemCatalog.by_id(&"dash"))
	var start := _car.global_position
	await _press_item()
	await _frames(30)
	var moved := _car.global_position - start
	_check(-moved.z > 8.5 and -moved.z < 11.5 and absf(moved.x) < 0.5,
			"рывок: машина сместилась вперёд на ~10 м (%.2f м)" % -moved.z)
	_check(absf(_car.forward_speed) < 0.5, "рывок не меняет скорость машины (%.2f)" % _car.forward_speed)


## Вантуз: мгновенная остановка и 1/4 с огромное сцепление.
func _test_stop() -> void:
	await _place(TEST_SPOT)
	Input.action_press(GameActions.ACCELERATE)
	await _frames(60)
	Input.action_release(GameActions.ACCELERATE)
	var before := _car.forward_speed
	_items.give(ItemCatalog.by_id(&"stop"))
	await _press_item()
	_check(before > 10.0 and absf(_car.forward_speed) < 0.5,
			"вантуз останавливает машину (%.1f -> %.1f м/с)" % [before, _car.forward_speed])
	_check(is_equal_approx(_car.acceleration_multiplier, 255.0) and is_equal_approx(_car.drift_recover_multiplier, 255.0),
			"вантуз: разгон и drift-recover ×255")
	await _frames(20)
	_check(is_equal_approx(_car.acceleration_multiplier, 1.0), "сцепление вантуза кончилось через 1/4 с")


func _test_item_box() -> void:
	var box := (load(ITEM_BOX_PATH) as PackedScene).instantiate() as ItemBox
	_level.add_child(box)
	box.global_position = TEST_SPOT + Vector3(0.0, -0.05, -10.0)
	var picked := {"count": 0}
	box.picked.connect(func(_c: CarController, _i: Item) -> void: picked["count"] += 1)
	_items.clear()
	await _place(TEST_SPOT)
	Input.action_press(GameActions.ACCELERATE)
	await _frames(80)
	Input.action_release(GameActions.ACCELERATE)
	_check(picked["count"] == 1 and _items.current != null, "проехал коробку — предмет в слоте (%s)" % [
			_items.current.id if _items.current != null else "пусто"])
	_check(not box.usable, "коробка исчезла")
	await _frames(15)
	var model := box.get_node("Model") as Node3D
	_check(model.scale.x < 0.05, "коробка сжалась за 0.2 с (масштаб %.2f)" % model.scale.x)

	# Пока коробки нет, второй проезд ничего не даёт.
	_items.clear()
	await _place(TEST_SPOT)
	Input.action_press(GameActions.ACCELERATE)
	await _frames(80)
	Input.action_release(GameActions.ACCELERATE)
	_check(_items.current == null and picked["count"] == 1, "исчезнувшую коробку взять нельзя")
	await _place(TEST_SPOT)
	# От взятия прошло ~120 кадров; всего ждём больше RESPAWN_TIME + SCALE_TIME.
	await _frames(150)
	_check(box.usable and model.scale.x > 0.95, "через 4 с коробка снова на месте (масштаб %.2f)" % model.scale.x)
	box.queue_free()


## Этап 5: восемь предметов, которые действуют на соперников, и водка.
func _test_stage5_items() -> void:
	var other := (load(CAR_PATH) as PackedScene).instantiate() as CarController
	var input := ScriptedInput.new()
	other.add_child(input)
	other.input_source = input
	other.name = "Rival"
	_level.add_child(other)
	var screen := (load(SCREEN_EFFECTS_PATH) as PackedScene).instantiate() as ScreenEffects
	_level.add_child(screen)
	screen.viewer = _car
	_car.add_to_group(ItemObject.LOCAL_PLAYER_GROUP)
	var duel := {"a": _car, "b": other, "input": input, "screen": screen}
	# Эмоции на иконках (HUD): какие просили машины.
	var emotes := {"a": [], "b": []}
	_car.emote_requested.connect(func(e: StringName, _s: float) -> void: emotes["a"].append(e))
	other.emote_requested.connect(func(e: StringName, _s: float) -> void: emotes["b"].append(e))
	await _frames(5)

	await _test_laser(duel)
	await _test_spine(duel)
	await _test_banana(duel)
	await _test_boomerang(duel)
	await _test_bomb(duel)
	await _test_flash(duel)
	await _test_icecream(duel)
	await _test_vodka(duel)
	await _test_tomato(duel)
	_check(&"angry" in emotes["b"] and &"parry" in emotes["b"] and &"rage" in emotes["b"] and &"unsee" in emotes["b"],
			"эмоции соперника: злость, парирование, ярость, «ослеп» (%s)" % [emotes["b"]])
	_check(&"item" in emotes["a"] and &"hehe" in emotes["a"] and &"vodka" in emotes["a"],
			"эмоции хозяина: предмет, «хе-хе» от флешки, водка (%s)" % [emotes["a"]])
	_car.remove_from_group(ItemObject.LOCAL_PLAYER_GROUP)
	other.queue_free()
	screen.queue_free()
	await _frames(3)


## Обе машины носом к −Z: A в точке a_at, B на b_ahead метров впереди; всё прочее убрано.
func _place_duel(duel: Dictionary, b_ahead: float, a_at: Vector3 = DUEL_SPOT) -> void:
	_release_all()
	for node in _level.get_children():
		if node is ItemObject:
			node.queue_free()
	var a: CarController = duel["a"]
	var b: CarController = duel["b"]
	(duel["input"] as ScriptedInput).throttle = 0.0
	for car in [a, b]:
		CarEffects.of(car).clear()
		CarItems.of(car).clear()
	a.teleport(Transform3D(Basis.IDENTITY, a_at))
	b.teleport(Transform3D(Basis.IDENTITY, a_at + Vector3(0.0, 0.0, -b_ahead)))
	await _frames(3)


## Помидор (наш предмет): автонаводка — летит в ближайшую машину впереди (доворачивает
## за ней), на излёте сбивает, лежит кляксой; сзади цели не ищет.
func _test_tomato(duel: Dictionary) -> void:
	await _place_duel(duel, 36.0)
	var a: CarController = duel["a"]
	var b: CarController = duel["b"]
	# Соперник впереди и чуть сбоку — помидор должен попасть, хотя летит не прямо по носу.
	b.teleport(Transform3D(Basis.IDENTITY, DUEL_SPOT + Vector3(6.0, 0.0, -36.0)))
	await _frames(3)
	var tomato := ItemCatalog.by_id(&"tomato")
	_check(tomato.pick_target(a) == b, "помидор: цель — соперник впереди (автонаводка)")
	var b_counter := _parry_counter(b)
	_use(a, &"tomato")
	await _frames(3)
	var thrown: ThrownObject = null
	for node in _item_objects():
		if node is ThrownObject:
			thrown = node
	_check(thrown != null and thrown.target_car == b and CarItems.of(a).current == null,
			"помидор полетел сразу по нажатию, в соперника")
	await _frames(100)
	var miss := Vector2(thrown.global_position.x - b.global_position.x, thrown.global_position.z - b.global_position.z).length() 			if is_instance_valid(thrown) else INF
	_check(is_instance_valid(thrown) and thrown.is_landed() and miss < 2.5,
			"помидор упал на соперника (%.1f м от него)" % miss)
	_check(b_counter["hit"] == 1, "помидор сбил соперника (%d)" % b_counter["hit"])
	# Соперник сзади — цели нет, бросок по носу.
	b.teleport(Transform3D(Basis.IDENTITY, DUEL_SPOT + Vector3(0.0, 0.0, 20.0)))
	await _frames(3)
	_check(tomato.pick_target(a) == null, "соперник сзади — помидор цель не выбирает")


func _use(car: CarController, id: StringName) -> void:
	var items := CarItems.of(car)
	items.give(ItemCatalog.by_id(id))
	items.use_item()


## Счётчики попаданий и парирований машины (по сигналам CarParry).
func _parry_counter(car: CarController) -> Dictionary:
	var counter := {"hit": 0, "parried": 0}
	var parry := CarParry.of(car)
	parry.hit.connect(func(_h: Node) -> void: counter["hit"] += 1)
	parry.parried.connect(func(_h: Node) -> void: counter["parried"] += 1)
	return counter


func _item_objects() -> Array[ItemObject]:
	var result: Array[ItemObject] = []
	for node in _level.get_children():
		if node is ItemObject and not node.is_queued_for_deletion():
			result.append(node)
	return result


## Лазер: 4 луча через 0.3 с, 70 м вперёд; попадание — полная остановка; хозяина не задевает.
func _test_laser(duel: Dictionary) -> void:
	await _place_duel(duel, 20.0)
	var a: CarController = duel["a"]
	var b: CarController = duel["b"]
	var b_counter := _parry_counter(b)
	var a_counter := _parry_counter(a)
	(duel["input"] as ScriptedInput).throttle = 1.0
	await _frames(20)
	var speed_before := b.forward_speed
	_use(a, &"bullet")
	await _frames(3)
	_check(speed_before > 3.0 and absf(b.forward_speed) < 1.0 and b_counter["hit"] == 1,
			"лазер: соперник впереди остановлен (%.1f -> %.1f м/с)" % [speed_before, b.forward_speed])
	await _frames(60)
	_check(b_counter["hit"] == 4, "лазер: 4 луча за 0.9 с — 4 попадания (%d)" % b_counter["hit"])
	_check(a_counter["hit"] == 0, "свой лазер хозяина не задевает")
	await _frames(15)
	_check(_item_objects().is_empty(), "лучи исчезают через 0.2 с")
	# С окном парирования первый луч проходит сквозь.
	(duel["input"] as ScriptedInput).parry_once = true
	await _frames(2)
	_use(a, &"bullet")
	await _frames(3)
	_check(b_counter["parried"] >= 1, "лазер парируется (парирований %d)" % b_counter["parried"])
	await _frames(70)


## Шипы: полоса 40 м вдоль машины на 0.5 с; соперник — макс. скорость ×0.5 на 1.2 с.
func _test_spine(duel: Dictionary) -> void:
	await _place_duel(duel, 12.0)
	var a: CarController = duel["a"]
	var b: CarController = duel["b"]
	_use(a, &"spine")
	await _frames(3)
	_check(is_equal_approx(b.max_speed_multiplier, 0.5) and is_equal_approx(a.max_speed_multiplier, 1.0),
			"шипы: у соперника предел ×0.5 (%.2f), у хозяина без изменений" % b.max_speed_multiplier)
	await _frames(72)
	_check(is_equal_approx(b.max_speed_multiplier, 1.0), "шипы: через 1.2 с предел вернулся")
	_check(_item_objects().is_empty(), "полоса шипов исчезает через 0.5 с")


## Банан: лежит под хозяином 20 с; соперник въехал — стоп (парируется); хозяина не задевает.
func _test_banana(duel: Dictionary) -> void:
	await _place_duel(duel, -25.0)
	var a: CarController = duel["a"]
	var b: CarController = duel["b"]
	var a_counter := _parry_counter(a)
	var b_counter := _parry_counter(b)
	_use(a, &"banana")
	await _frames(3)
	var banana := _item_objects()[0] if not _item_objects().is_empty() else null
	_check(banana != null and (banana.get_node("Visual") as Sprite3D).texture == banana.own_texture,
			"свой банан игрок видит без розовой обводки (свой кадр)")
	Input.action_press(GameActions.ACCELERATE)
	await _frames(90)
	Input.action_release(GameActions.ACCELERATE)
	_check(a_counter["hit"] == 0, "свой банан хозяина не задевает")
	(duel["input"] as ScriptedInput).throttle = 1.0
	for i in 160:
		await physics_frame
		if b_counter["hit"] > 0:
			break
	(duel["input"] as ScriptedInput).throttle = 0.0
	_check(b_counter["hit"] == 1, "банан: соперник наехал — остановка (%d)" % b_counter["hit"])
	_check(is_instance_valid(banana) and not banana.is_queued_for_deletion(), "банан после наезда остаётся")
	var alive := banana.get_lifetime() if banana != null else 0.0
	for i in 21 * 60:
		await physics_frame
		if not is_instance_valid(banana):
			break
	_check(not is_instance_valid(banana) and absf(alive - 20.0) < 0.01, "банан исчезает через 20 с")


## Бумеранг: 40 м вперёд за 1 с и обратно; задевает соперника; исчезает через 2 с.
func _test_boomerang(duel: Dictionary) -> void:
	await _place_duel(duel, 25.0)
	var a: CarController = duel["a"]
	var b: CarController = duel["b"]
	var a_counter := _parry_counter(a)
	var b_counter := _parry_counter(b)
	var start := a.global_position
	_use(a, &"bumer")
	var boomerang: ItemObject = _item_objects()[0]
	await _frames(60)
	var travelled := Vector2(start.x, start.z).distance_to(Vector2(boomerang.global_position.x, boomerang.global_position.z))
	_check(travelled > 38.0 and travelled < 42.0, "бумеранг улетел на ~40 м за 1 с (%.1f м)" % travelled)
	_check(b_counter["hit"] >= 1, "бумеранг задел соперника (%d)" % b_counter["hit"])
	await _frames(65)
	_check(not is_instance_valid(boomerang), "бумеранг вернулся и исчез через 2 с")
	_check(a_counter["hit"] == 0, "свой бумеранг хозяина не задевает")

## Бомба: под хозяином, ему видна полупрозрачной; соперник наехал — предел ×0.5 на 1.2 с, бомба исчезла.
func _test_bomb(duel: Dictionary) -> void:
	await _place_duel(duel, -25.0)
	var a: CarController = duel["a"]
	var b: CarController = duel["b"]
	_use(a, &"bomb")
	await _frames(3)
	var bomb: ItemObject = _item_objects()[0]
	var visual := bomb.get_node("Visual") as GeometryInstance3D
	_check(visual != null and absf(visual.transparency - 0.5) < 0.01, "своя бомба для своего игрока полупрозрачная")
	_check(is_equal_approx(a.max_speed_multiplier, 1.0), "своя бомба хозяина не задевает")
	Input.action_press(GameActions.ACCELERATE)
	await _frames(90)
	Input.action_release(GameActions.ACCELERATE)
	(duel["input"] as ScriptedInput).throttle = 1.0
	var slowed := false
	for i in 120:
		await physics_frame
		slowed = slowed or is_equal_approx(b.max_speed_multiplier, 0.5)
		if slowed:
			break
	(duel["input"] as ScriptedInput).throttle = 0.0
	_check(slowed, "бомба: соперник наехал — предел ×0.5")
	await _frames(2)
	_check(not is_instance_valid(bomb), "бомба после взрыва исчезла")
	await _frames(75)
	_check(is_equal_approx(b.max_speed_multiplier, 1.0), "через 1.2 с после бомбы предел вернулся")


## Флешка: у соперников экран белеет полностью, у себя на 30 %; гаснет за ~4.5 с.
func _test_flash(duel: Dictionary) -> void:
	await _place_duel(duel, 20.0)
	var screen: ScreenEffects = duel["screen"]
	_use(duel["a"], &"flash")
	_check(is_equal_approx(screen.flash_opacity, 0.3), "своя флешка — экран белеет на 30 %")
	_use(duel["b"], &"flash")
	_check(is_equal_approx(screen.flash_opacity, 1.0), "флешка соперника — экран белый полностью")
	await _frames(150)
	_check(absf(screen.flash_opacity - 0.75) < 0.03, "за 2.5 с гаснет до 75 %% (%.2f)" % screen.flash_opacity)
	await _frames(130)
	_check(screen.flash_opacity == 0.0, "через 4.5 с вспышки нет")


## Мороженое: 5 пятен льда за 1.2 с; на чужом льду разгон и торможение ÷2.5, сцепление ÷4,
## руль вялый ×0.5 (машина «неуклюжая»); предел скорости не меняется.
func _test_icecream(duel: Dictionary) -> void:
	await _place_duel(duel, -20.0)
	var a: CarController = duel["a"]
	var b: CarController = duel["b"]
	_use(a, &"icecream")
	await _frames(80)
	_check(_item_objects().size() == 5, "мороженое: 5 пятен льда (%d)" % _item_objects().size())
	_check(is_equal_approx(a.acceleration_multiplier, 1.0), "свой лёд хозяина не задевает")
	a.teleport(Transform3D(Basis.IDENTITY, DUEL_SPOT + Vector3(12.0, 0.0, -30.0)))
	(duel["input"] as ScriptedInput).throttle = 1.0
	var iced := false
	var yaw_before := b.global_rotation.y
	for i in 120:
		await physics_frame
		if is_equal_approx(b.acceleration_multiplier, 1.0 / 2.5) and is_equal_approx(b.drift_recover_multiplier, 1.0 / 4.0):
			iced = true
			break
	_check(iced and is_equal_approx(b.max_speed_multiplier, 1.0) and is_equal_approx(b.steering_multiplier, 0.5),
			"на чужом льду разгон и торможение ÷2.5, сцепление ÷4, руль ×0.5, предел скорости тот же")
	_check(absf(angle_difference(yaw_before, b.global_rotation.y)) < deg_to_rad(5.0),
			"нос на въезде не уводит (%.0f°)" % rad_to_deg(angle_difference(yaw_before, b.global_rotation.y)))
	var spot := _item_objects()[0] as IceSpot
	var spot_visual := spot.get_node(^"Visual") as Sprite3D
	_check(spot_visual.modulate.a > 0.5, "пятно видно (альфа цвета %.2f)" % spot_visual.modulate.a)
	(duel["input"] as ScriptedInput).throttle = 1.0
	await _frames(90)
	(duel["input"] as ScriptedInput).throttle = 0.0
	_check(is_equal_approx(b.acceleration_multiplier, 1.0) and not IceSpot.is_on_ice(b), "съехал со льда — снова цепко")
	await _frames(int(6.0 * 60.0))
	_check(_item_objects().is_empty(), "лёд тает через 8 с")


## Водка: 2.5 с предел ×1.25, сцепление ÷2 и «пьяный» экран у своего игрока.
func _test_vodka(duel: Dictionary) -> void:
	await _place_duel(duel, 20.0)
	var a: CarController = duel["a"]
	var screen: ScreenEffects = duel["screen"]
	_use(duel["b"], &"vodka")
	_check(not screen.is_drunk(), "чужая водка своему экрану не мешает")
	_use(a, &"vodka")
	_check(is_equal_approx(a.max_speed_multiplier, 1.25) and is_equal_approx(a.drift_recover_multiplier, 0.5),
			"водка: предел ×1.25, сцепление ÷2")
	_check(screen.is_drunk(), "водка: экран «пьяный»")
	await _frames(155)
	_check(is_equal_approx(a.max_speed_multiplier, 1.0) and not screen.is_drunk(), "водка кончилась через 2.5 с")


## Гонка: коробки на маркерах трассы, слот предмета и полоска времени в HUD.
func _test_race_boxes_and_hud() -> void:
	var race := (load(RACE_PATH) as PackedScene).instantiate() as Race
	race.track_scene = load(TRACK_PATH) as PackedScene
	race.autostart = false
	root.add_child(race)
	var source := CarInputSource.new()
	race.add_child(source)
	var racer := race.spawn_racer("Игрок", true, source)
	race.begin()
	await _frames(5)
	var markers := race.track.find_children("*", "Marker3D", true, false).filter(
			func(m: Node) -> bool: return m.is_in_group(Race.ITEM_BOX_GROUP))
	_check(markers.size() > 0 and race.item_boxes.size() == markers.size(),
			"коробки на всех маркерах трассы (%d из %d)" % [race.item_boxes.size(), markers.size()])

	var items := CarItems.of(racer.car)
	var icon := race.get_node("RaceHud/TimerPanel/ItemIcon") as TextureRect
	var bar := race.get_node("RaceHud/TimerPanel/ItemTime") as TextureRect
	var empty_icon := icon.texture
	var nitro := ItemCatalog.by_id(&"nitro")
	items.give(nitro)
	await _frames(30)
	_check(icon.texture == nitro.icon_frames.back(), "в слоте HUD — иконка нитро (последний кадр анимации)")
	_check(bar.size.x == 0.0, "без эффекта полоски времени нет")
	items.use_item()
	await _frames(30)
	_check(bar.size.x > 20.0 and bar.size.x < 50.0, "полоска времени нитро убывает (%.0f px из 72)" % bar.size.x)
	_check(icon.texture == empty_icon, "после применения слот HUD пуст")
	await _frames(40)
	_check(bar.size.x == 0.0, "эффект кончился — полоски нет")
	race.queue_free()
	await _frames(10)


func _press_item() -> void:
	Input.action_press(GameActions.USE_ITEM)
	await _frames(2)
	Input.action_release(GameActions.USE_ITEM)
	await _frames(1)


func _place(position: Vector3) -> void:
	_release_all()
	_effects.clear()
	_car.teleport(Transform3D(Basis.IDENTITY, position))
	await _frames(3)


func _release_all() -> void:
	for action in [GameActions.ACCELERATE, GameActions.BRAKE, GameActions.STEER_LEFT,
			GameActions.STEER_RIGHT, GameActions.DRIFT, GameActions.PARRY, GameActions.USE_ITEM]:
		Input.action_release(action)


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _check(condition: bool, description: String) -> void:
	print("[%s] %s" % ["OK" if condition else "FAIL", description])
	if not condition:
		_failures.append(description)
