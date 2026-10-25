class_name RacerIcons
extends Control
## Иконки участников слева (PlayerCarIcon оригинала): рожица 24×24 в цвет машины, ник
## над ней (свой — зелёный), полоска прогресса гонки под ней (красная, 24 px на всю гонку)
## и эмоции: на время эмоции рожица меняется (злость, парирование, предмет, круг, победа…)
## и вырастает до 32 px, потом возвращается к случайной спокойной.
## Лучше оригинала: иконки стоят по местам (перестраиваются с подскоком) и с номером места.

const FACE_TEXTURES: Array[Texture2D] = [
	preload("res://assets/original/textures/main/playercaricon-none-000.png"),
	preload("res://assets/original/textures/main/playercaricon-none-001.png"),
	preload("res://assets/original/textures/main/playercaricon-none-002.png"),
	preload("res://assets/original/textures/main/playercaricon-none-003.png"),
]
const EMOTE_TEXTURES := {
	&"angry": preload("res://assets/original/textures/main/playercaricon-angry-000.png"),
	&"hehe": preload("res://assets/original/textures/main/playercaricon-hehe-000.png"),
	&"item": preload("res://assets/original/textures/main/playercaricon-item-000.png"),
	&"lap": preload("res://assets/original/textures/main/playercaricon-lap-000.png"),
	&"lose": preload("res://assets/original/textures/main/playercaricon-lose-000.png"),
	&"parry": preload("res://assets/original/textures/main/playercaricon-parry-000.png"),
	&"rage": preload("res://assets/original/textures/main/playercaricon-rage-000.png"),
	&"unsee": preload("res://assets/original/textures/main/playercaricon-unsee-000.png"),
	&"vntz": preload("res://assets/original/textures/main/playercaricon-vntz-000.png"),
	&"vodka": preload("res://assets/original/textures/main/playercaricon-vodka-000.png"),
	&"win": preload("res://assets/original/textures/main/playercaricon-win-000.png"),
}
## Размер иконки и на время эмоции, px (в оригинале 24 и 32).
const ICON_SIZE := 24.0
const EMOTE_SIZE := 32.0
## Центр первой иконки и шаг между иконками, px (в оригинале x = 20, y = 36 + 32·N).
const FIRST_CENTER := Vector2(20.0, 36.0)
const STEP := 32.0
## Самый тесный шаг (с сенсорными кнопками надпись круга поднимается), px.
const MIN_STEP := 22.0
## Свой ник — зелёный (#0f3 в оригинале).
const OWN_NAME_COLOR := Color(0.0, 1.0, 0.2)

var _race: RaceManager
## Нижняя граница списка (верх надписи круга), px от верха.
var _bottom_limit: float = 216.0
var _entries: Array[Dictionary] = []


## Создать иконки участников гонки race.
func setup(race: RaceManager) -> void:
	_race = race
	for racer in race.racers:
		_add_entry(racer)
	_layout(true)


## Участник добавился (сеть: игрок вошёл в лобби).
func add_racer(racer: RacerState) -> void:
	if _entries.any(func(e: Dictionary) -> bool: return e["racer"] == racer):
		return
	_add_entry(racer)
	_layout(true)


## Участник ушёл (сеть).
func remove_racer(racer: RacerState) -> void:
	for entry in _entries:
		if entry["racer"] == racer:
			(entry["holder"] as Control).queue_free()
			_entries.erase(entry)
			_layout(true)
			return


## Иконки не ниже этой высоты (верх надписи круга), px.
func set_bottom_limit(y: float) -> void:
	_bottom_limit = y
	_layout(true)


func _add_entry(racer: RacerState) -> void:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)

	var name_label := Label.new()
	name_label.text = racer.display_name
	# Ники — шрифтом Text ×1, как PlayerCarName оригинала (6 px).
	name_label.add_theme_font_size_override(&"font_size", 6)
	name_label.add_theme_color_override(&"font_color", OWN_NAME_COLOR if racer.is_local_player else Color.WHITE)
	name_label.add_theme_color_override(&"font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
	name_label.add_theme_constant_override(&"outline_size", 3)
	name_label.position = Vector2(-12.0, -20.0)
	holder.add_child(name_label)

	var icon := TextureRect.new()
	icon.texture = FACE_TEXTURES.pick_random()
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_SCALE
	# Цвет скина (R·64+64…, как PlayerCarIcon оригинала).
	icon.modulate = racer.color
	icon.size = Vector2(ICON_SIZE, ICON_SIZE)
	icon.position = -icon.size * 0.5
	icon.pivot_offset = icon.size * 0.5
	holder.add_child(icon)

	var bar_back := ColorRect.new()
	bar_back.color = Color(0.0, 0.0, 0.0, 0.5)
	bar_back.position = Vector2(-ICON_SIZE * 0.5, ICON_SIZE * 0.5 + 1.0)
	bar_back.size = Vector2(ICON_SIZE, 2.0)
	holder.add_child(bar_back)
	var bar := ColorRect.new()
	bar.color = Color(1.0, 0.0, 0.0)
	bar.position = bar_back.position
	bar.size = Vector2(0.0, 2.0)
	holder.add_child(bar)
	# Ник поверх всех рожиц (и соседних): на время эмоции рожица вырастает до 32 px.
	name_label.z_index = 1

	var entry := {"racer": racer, "holder": holder, "icon": icon, "name": name_label, "bar": bar,
			"emote_left": 0.0, "slot": -1, "tween": null, "size_tween": null}
	_entries.append(entry)
	racer.car.emote_requested.connect(_on_emote.bind(entry))


func _process(delta: float) -> void:
	if _race == null:
		return
	var total := maxf(_race.laps * _race.track.length, 1.0) if _race.track != null else 1.0
	for entry in _entries:
		var racer: RacerState = entry["racer"]
		var label: Label = entry["name"]
		# Хост сетевой игры — 👑 после ника, как в оригинале (символ есть в шрифте Text).
		var crown := " 👑" if Network.session().is_online() and racer.peer_id == 1 else ""
		label.text = ("%d %s%s" % [racer.place, racer.display_name, crown]) if racer.place > 0 else racer.display_name + crown
		# Полоска прогресса: плавно догоняет (в оригинале твин 1/4 с).
		var bar: ColorRect = entry["bar"]
		var target := ICON_SIZE * clampf(racer.race_distance / total, 0.0, 1.0)
		if racer.finished:
			target = ICON_SIZE
		bar.size.x = lerpf(bar.size.x, target, 1.0 - exp(-12.0 * delta))
		# Эмоция кончилась — спокойная рожица и обычный размер.
		if float(entry["emote_left"]) > 0.0:
			entry["emote_left"] = float(entry["emote_left"]) - delta
			if float(entry["emote_left"]) <= 0.0:
				(entry["icon"] as TextureRect).texture = FACE_TEXTURES.pick_random()
				_resize(entry, ICON_SIZE, Tween.TRANS_BACK)
	_layout(false)


## Иконки по местам; при смене порядка — переезд с подскоком.
func _layout(instant: bool) -> void:
	if _entries.is_empty():
		return
	var count := _entries.size()
	var step := STEP
	if count > 1:
		step = clampf((_bottom_limit - 4.0 - ICON_SIZE * 0.5 - FIRST_CENTER.y) / (count - 1), MIN_STEP, STEP)
	var sorted := _entries.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pa: int = (a["racer"] as RacerState).place
		var pb: int = (b["racer"] as RacerState).place
		return pa < pb if pa != pb else _entries.find(a) < _entries.find(b))
	for slot in sorted.size():
		var entry: Dictionary = sorted[slot]
		(entry["name"] as Label).visible = step >= STEP - 0.5
		var target := FIRST_CENTER + Vector2(0.0, step * slot)
		var holder: Control = entry["holder"]
		if instant:
			holder.position = target
			entry["slot"] = slot
		elif int(entry["slot"]) != slot:
			entry["slot"] = slot
			if entry["tween"] != null:
				(entry["tween"] as Tween).kill()
			var tween := holder.create_tween()
			tween.tween_property(holder, ^"position", target, 0.3).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
			entry["tween"] = tween


func _on_emote(emote_name: StringName, seconds: float, entry: Dictionary) -> void:
	if not EMOTE_TEXTURES.has(emote_name):
		return
	(entry["icon"] as TextureRect).texture = EMOTE_TEXTURES[emote_name]
	entry["emote_left"] = seconds
	_resize(entry, EMOTE_SIZE, Tween.TRANS_SINE)


func _resize(entry: Dictionary, size_px: float, transition: Tween.TransitionType) -> void:
	var icon: TextureRect = entry["icon"]
	if entry["size_tween"] != null:
		(entry["size_tween"] as Tween).kill()
	var tween := icon.create_tween().set_parallel()
	tween.tween_property(icon, ^"size", Vector2(size_px, size_px), 0.2).set_trans(transition).set_ease(Tween.EASE_OUT)
	tween.tween_property(icon, ^"position", -Vector2(size_px, size_px) * 0.5, 0.2).set_trans(transition).set_ease(Tween.EASE_OUT)
	entry["size_tween"] = tween


## Текстура рожицы участника сейчас (для тестов).
func get_emote_texture(racer: RacerState) -> Texture2D:
	for entry in _entries:
		if entry["racer"] == racer:
			return (entry["icon"] as TextureRect).texture
	return null
