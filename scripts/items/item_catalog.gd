class_name ItemCatalog
extends RefCounted
## Все 12 предметов оригинала + наш «Помидор» (бросок). В оригинале коробка выбирает предмет
## равновероятно: choose("Bullet", "Spine", "Banana", "Flash", "Icecream", "Bumer", "Bomb",
## "Vodka", "NoDrift", "Nitro", "Dash", "Stop") (Aupa там отключён — его нет).
## У нас в гонке — по месту, как в Mario Kart (просьба автора ремейка: «чем ближе к первому
## месту, тем хуже предметы»): лидеру чаще то, что кладут на дорогу позади (банан, бомба,
## лёд, шипы), отстающим — то, что догоняет и сбивает впереди (нитро, рывок, лазер, флешка).

const ITEMS := [
	preload("res://items/bullet.tres"),
	preload("res://items/spine.tres"),
	preload("res://items/banana.tres"),
	preload("res://items/flash.tres"),
	preload("res://items/icecream.tres"),
	preload("res://items/bumer.tres"),
	preload("res://items/bomb.tres"),
	preload("res://items/vodka.tres"),
	preload("res://items/nodrift.tres"),
	preload("res://items/nitro.tres"),
	preload("res://items/dash.tres"),
	preload("res://items/stop.tres"),
	# Наш предмет (просьба автора оригинала): бросок на расстояние с зарядом.
	preload("res://items/tomato.tres"),
]


## Вес предмета по месту: [первый, середина, последний]; между ними — линейно.
## Сумма весов на каждом месте ~22: у лидера нитро в 6 раз реже, чем у последнего.
const PLACE_WEIGHTS := {
	&"banana": [3.0, 2.0, 0.8],
	&"bomb": [3.0, 2.0, 0.8],
	&"icecream": [3.0, 2.0, 0.8],
	&"spine": [3.0, 2.0, 0.8],
	&"stop": [2.0, 1.0, 0.5],
	&"nodrift": [2.0, 1.5, 1.0],
	&"bumer": [1.5, 2.0, 1.5],
	&"tomato": [1.5, 2.0, 2.0],
	&"bullet": [0.8, 2.0, 2.8],
	&"flash": [0.6, 1.5, 2.8],
	&"vodka": [0.6, 1.5, 2.0],
	&"nitro": [0.5, 1.5, 3.0],
	&"dash": [0.5, 1.5, 2.8],
}


## Все предметы.
static func all() -> Array[Item]:
	var result: Array[Item] = []
	for item in ITEMS:
		result.append(item as Item)
	return result


## Случайный предмет (rng — для повторяемости в тестах и сети; null — общий генератор).
static func random_item(rng: RandomNumberGenerator = null) -> Item:
	var index := rng.randi_range(0, ITEMS.size() - 1) if rng != null else randi_range(0, ITEMS.size() - 1)
	return ITEMS[index] as Item


## Предмет по месту в гонке: place_share 0 — первый, 1 — последний; < 0 — места нет
## (лобби, заезд в одиночку) — равновероятно, как в оригинале.
static func item_for_place(place_share: float, rng: RandomNumberGenerator = null) -> Item:
	if place_share < 0.0:
		return random_item(rng)
	var weights := PackedFloat32Array()
	var total := 0.0
	for item in ITEMS:
		var weight := place_weight((item as Item).id, place_share)
		weights.append(weight)
		total += weight
	var roll := (rng.randf() if rng != null else randf()) * total
	for i in ITEMS.size():
		roll -= weights[i]
		if roll < 0.0:
			return ITEMS[i] as Item
	return ITEMS[ITEMS.size() - 1] as Item


## Вес предмета id на месте place_share (0 — первый, 1 — последний).
static func place_weight(id: StringName, place_share: float) -> float:
	var row: Array = PLACE_WEIGHTS.get(id, [1.0, 1.0, 1.0])
	var t := clampf(place_share, 0.0, 1.0) * 2.0
	if t <= 1.0:
		return lerpf(row[0], row[1], t)
	return lerpf(row[1], row[2], t - 1.0)


## Предмет по id (или null).
static func by_id(id: StringName) -> Item:
	for item in ITEMS:
		if (item as Item).id == id:
			return item
	return null
