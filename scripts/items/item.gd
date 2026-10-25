class_name Item
extends Resource
## Предмет из коробки (CurItem оригинала). Параметры, иконка и звуки —
## в ресурсе items/<id>.tres, действие — в use() наследника.
##
## Наследники: ItemSelfEffect (на себя: Nitro, NoDrift, Dash, Stop, Vodka),
## ItemSpawn (объекты на трассе: лазер, шипы, банан, бумеранг, бомба, мороженое),
## ItemFlash (флешка), ItemThrow (помидор — бросок на расстояние, наш предмет).

## Имя предмета в оригинале в нижнем регистре: nitro, nodrift, dash, stop…
@export var id: StringName
## Название для интерфейса.
@export var display_name: String
## Кадры иконки в слоте (curitem-<id>-NNN оригинала), 20×16 px.
@export var icon_frames: Array[Texture2D] = []
## Скорость анимации иконки, кадр/с (анимация не зацикленная, как в оригинале).
@export var icon_fps: float = 16.0
## Звуки при использовании (играют одновременно).
@export var use_sounds: Array[AudioStream] = []
## Показывать ли полоску времени (ItemTime оригинала) на время эффекта.
@export var shows_timer: bool = false
## Полоска убывает «с подскоками» (easeoutbounce у водки в оригинале), иначе — ровно.
@export var timer_bounce: bool = false
## В сети звуки use_sounds слышат и остальные (флешка: Damage4 у всех, как в оригинале).
@export var others_hear: bool = false
## Эмоция хозяина на иконке при применении (вантуз — vntz, водка — vodka, флешка — hehe), 1 с.
@export var use_emote: StringName = &""
## Заряд: > 0 — кнопку предмета держат, сила растёт до 1 за это время, бросок — когда отпустили
## (помидор). 0 — предмет применяется сразу по нажатию.
@export var charge_time: float = 0.0


## Применить предмет машиной car. Звуки use_sounds играет CarItems.
func use(_car: CarController) -> void:
	pass


## Применить с силой power 0..1 (заряд, см. charge_time); обычные предметы её не замечают.
func use_with_power(car: CarController, _power: float) -> void:
	use(car)


## Цель предмета с автонаводкой (помидор — ItemThrow): машина или null. Обычные — null.
## Выбирает хозяин; в сети цель передаётся всем (Network.item_used), чтобы бросок у всех
## летел в одну машину.
func pick_target(_car: CarController) -> CarController:
	return null


## Применить по цели (автонаводка); обычные предметы цель не замечают.
func use_at(car: CarController, power: float, _target: CarController) -> void:
	use_with_power(car, power)


## Сколько длится эффект предмета, с (для полоски времени; 0 — мгновенный).
func get_duration() -> float:
	return 0.0
