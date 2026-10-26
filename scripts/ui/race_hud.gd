class_name RaceHud
extends CanvasLayer
## Интерфейс гонки на спрайтах оригинала (экран 384×216):
##   * слева — иконки участников (RacerIcons: рожица в цвет машины, ник, номер места,
##     полоска прогресса, эмоции), как PlayerCarIcon оригинала, но по местам;
##   * слева снизу — «КРУГ:» с цветной цифрой (на новом круге цифра «прыгает» ×1.5, звук FinishLap);
##   * справа сверху — таймер MM:SS в плашке; правый отсек плашки — слот предмета (CurItem),
##     под ним красная полоска времени эффекта (ItemTime) и подсказка клавиши «Q» (на ПК);
##   * по центру — отсчёт 3-2-1-GO (звук Countdown), сообщения, плашка победителя
##     (WinnerBg: выезжает сверху, «поздравляю, X / ты победил!» или «победил X / …»,
##     звук Cheers у победителя) и результаты.

## Цветные цифры кругов 1..5 (lapnum в оригинале).
const LAP_TEXTURES: Array[Texture2D] = [
	preload("res://assets/original/textures/ui/lapnum-000.png"),
	preload("res://assets/original/textures/ui/lapnum-001.png"),
	preload("res://assets/original/textures/ui/lapnum-002.png"),
	preload("res://assets/original/textures/ui/lapnum-003.png"),
	preload("res://assets/original/textures/ui/lapnum-004.png"),
]
## Отсчёт: «3», «2», «1», «GO!» (countdown в оригинале).
const COUNTDOWN_TEXTURES: Array[Texture2D] = [
	preload("res://assets/original/textures/ui/countdown-000.png"),
	preload("res://assets/original/textures/ui/countdown-001.png"),
	preload("res://assets/original/textures/ui/countdown-002.png"),
	preload("res://assets/original/textures/ui/countdown-003.png"),
]
## Сколько секунд держать сообщение или «GO!» по центру.
const MESSAGE_TIME := 1.2
## Нижний отступ надписи круга, px.
const LAP_BOTTOM_MARGIN := 4.0

## Пустой слот предмета.
const NO_ITEM_TEXTURE := preload("res://assets/original/textures/ui/curitem-none-000.png")
## Полоска времени эффекта (ItemTime): полная ширина, px.
const ITEM_TIME_WIDTH := 72.0
## Иконка нового предмета «подпрыгивает» вниз на столько px и обратно за ITEM_BOUNCE_TIME.
const ITEM_BOUNCE := 4.0
const ITEM_BOUNCE_TIME := 0.1
## Взял коробку — сначала «барабан» (curitem-scroll оригинала, 16 кадров/с) столько секунд,
## потом предмет. В оригинале анимация Scroll есть, но в последней версии отключена.
const ITEM_SCROLL_TIME := 0.3
const ITEM_SCROLL_FPS := 16.0
const ITEM_SCROLL := [preload("res://assets/original/textures/ui/curitem-scroll-000.png"),
		preload("res://assets/original/textures/ui/curitem-scroll-001.png")]

const COUNTDOWN_SOUND := preload("res://assets/original/sounds/countdown.wav")
const LAP_SOUND := preload("res://assets/original/sounds/finishlap.wav")
const WIN_SOUND := preload("res://assets/original/sounds/cheers.wav")
const WINNER_BG := preload("res://assets/original/textures/ui/winnerbg.png")
## Плашка победителя: размер (WinnerBg 224×32) и куда выезжает (верх; в оригинале центр
## на высоте 216 / 2 − 4), px. Сообщения CenterLabel — выше неё.
const WINNER_SIZE := Vector2(224.0, 32.0)
const WINNER_TOP := 88.0
## Утешения проигравшим — как в оригинале.
const LOSE_PHRASES: Array[String] = ["повезёт в следующий раз!", "не расстраивайся!",
		"ему просто повезло!", "да у меня залагало просто!", "ой-ой!", "да я только разминался!",
		"так не бывает!", "ой-ой!", "это читер!", "я ведь почти победил!"]
## Цифра круга «прыгает» до этого масштаба и обратно за LAP_POP_TIME (в оригинале 1.5 и 0.35 с).
const LAP_POP_SCALE := 1.5
const LAP_POP_TIME := 0.35

var _race: RaceManager
var _racer: RacerState
var _message_left: float = 0.0
var _countdown_left: float = 0.0
var _items: CarItems
var _effects: CarEffects
## Эффект, время которого показывает полоска (последний предмет с таймером).
var _timed_effect: CarEffect
var _timed_bounce: bool = false
var _icon_item: Item
var _icon_time: float = 0.0
var _icon_top: float = 0.0
var _icon_tween: Tween
var _racer_icons: RacerIcons
var _winner: NinePatchRect
var _winner_title: Label
var _winner_sub: Label
var _winner_shown: bool = false
var _lap_tween: Tween
## Место в гонке (справа снизу, как в Mario Kart; просьба автора оригинала): большая цветная
## цифра lapnum, окраска по месту, «прыжок» при смене места.
var _place: Control
var _place_number: TextureRect
var _place_total: Label
var _place_shown: int = 0
var _place_tween: Tween
var _notices: VBoxContainer
var _results_table: GridContainer
var _lobby: Control
var _lobby_label: Label
var _lobby_empty: Control
var _online_label: Label
var _invite: Button

@onready var _place_label: Label = $PlaceLabel
@onready var _lap: Control = $Lap
@onready var _lap_number: TextureRect = $Lap/Number
@onready var _time_label: Label = $TimerPanel/TimeLabel
@onready var _countdown: TextureRect = $Countdown
@onready var _center_label: Label = $CenterLabel
@onready var _results: Control = $Results
@onready var _results_list: Label = $Results/Window/Panel/Box/List
@onready var _restart_button: Button = $Results/Window/Panel/Box/Buttons/RestartButton
@onready var _menu_button: Button = $Results/Window/Panel/Box/Buttons/MenuButton
@onready var _wait_label: Label = $Results/Window/Panel/Box/Wait
@onready var _item_icon: TextureRect = $TimerPanel/ItemIcon
@onready var _item_time: TextureRect = $TimerPanel/ItemTime
@onready var _space_hint: TextureRect = $TimerPanel/SpaceHint


func _ready() -> void:
	_results.visible = false
	_center_label.visible = false
	_countdown.visible = false
	_restart_button.pressed.connect(_on_restart_pressed)
	_menu_button.pressed.connect(func() -> void: Network.session().leave_to_menu())
	_icon_top = _item_icon.position.y
	_item_time.size.x = 0.0
	# Место теперь у иконок участников (номер перед ником).
	_place_label.visible = false
	_racer_icons = RacerIcons.new()
	_racer_icons.name = "RacerIcons"
	_racer_icons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_racer_icons)
	move_child(_racer_icons, 0)
	_build_winner_banner()
	_build_place()
	_style_results()
	_lap_number.pivot_offset = _lap_number.size * 0.5


## Подключить HUD к гонке и участнику, за которым он следит.
func setup(race: RaceManager, racer: RacerState) -> void:
	_race = race
	_racer = racer
	race.countdown_tick.connect(_on_countdown_tick)
	race.race_started.connect(func() -> void: _show_countdown(COUNTDOWN_TEXTURES.size() - 1))
	race.lap_started.connect(_on_lap_started)
	race.racer_finished.connect(_on_racer_finished)
	race.race_finished.connect(_show_results)
	_items = CarItems.of(racer.car)
	_effects = CarEffects.of(racer.car)
	if _items != null:
		_items.item_changed.connect(_on_item_changed)
		_items.item_used.connect(_on_item_used)
	if _effects != null:
		_effects.effect_removed.connect(_on_effect_removed)
	_racer_icons.setup(race)
	_update_icons_limit()


func _process(delta: float) -> void:
	if _race == null or _racer == null:
		return
	_place_label.text = "%d/%d" % [_racer.place, _race.racers.size()]
	_update_place()
	var lap := clampi(_racer.lap, 1, mini(_race.laps, LAP_TEXTURES.size()))
	_lap_number.texture = LAP_TEXTURES[lap - 1]
	var time := _race.race_time
	if _racer.finished and _racer.finish_time >= 0.0:
		time = _racer.finish_time
	_time_label.text = format_clock(time)
	if _message_left > 0.0:
		_message_left -= delta
		if _message_left <= 0.0:
			_center_label.visible = false
	if _countdown_left > 0.0:
		_countdown_left -= delta
		if _countdown_left <= 0.0:
			_countdown.visible = false
	_update_item_slot(delta)
	_keep_lobby_clear()


## Подсказка клавиши предмета (Q) — только без сенсорных кнопок, как в оригинале.
func set_key_hints_visible(hints_visible: bool) -> void:
	_space_hint.visible = hints_visible


func _update_item_slot(delta: float) -> void:
	# Иконка предмета: сначала «барабан», потом незацикленная анимация кадров curitem
	# (остаётся последний кадр).
	if _icon_item != null and _icon_time < 0.0:
		_icon_time += delta
		_item_icon.texture = ITEM_SCROLL[int(absf(_icon_time) * ITEM_SCROLL_FPS) % ITEM_SCROLL.size()]
		if _icon_time >= 0.0:
			_bounce_icon()
	elif _icon_item != null and not _icon_item.icon_frames.is_empty():
		_icon_time += delta
		var frame := 0
		if _icon_item.icon_fps > 0.0:
			frame = mini(int(_icon_time * _icon_item.icon_fps), _icon_item.icon_frames.size() - 1)
		_item_icon.texture = _icon_item.icon_frames[frame]
	# Полоска времени эффекта; пока заряжаем бросок (помидор) — сила броска.
	var fraction := 0.0
	var charge := _items.get_charge() if _items != null else -1.0
	if charge >= 0.0:
		fraction = charge
	elif _timed_effect != null:
		fraction = _timed_effect.get_fraction()
		if _timed_bounce:
			# Твин ширины 72 -> 0 с easeoutbounce (водка в оригинале).
			fraction = 1.0 - ease_out_bounce(1.0 - fraction)
	_item_time.size.x = ITEM_TIME_WIDTH * fraction


func _on_item_changed(item: Item) -> void:
	_icon_item = item
	# Отрицательное время — ещё крутится «барабан» (_update_item_slot).
	_icon_time = -ITEM_SCROLL_TIME
	if item == null:
		_icon_time = 0.0
		_item_icon.texture = NO_ITEM_TEXTURE
		return
	_item_icon.texture = ITEM_SCROLL[0]


## Как в оригинале: иконка опускается на 4 px и возвращается (0.1 с туда-обратно).
func _bounce_icon() -> void:
	if _icon_tween != null:
		_icon_tween.kill()
	_item_icon.position.y = _icon_top
	_icon_tween = create_tween()
	_icon_tween.tween_property(_item_icon, ^"position:y", _icon_top + ITEM_BOUNCE, ITEM_BOUNCE_TIME) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_icon_tween.tween_property(_item_icon, ^"position:y", _icon_top, ITEM_BOUNCE_TIME) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


func _on_item_used(item: Item) -> void:
	if not item.shows_timer or _effects == null:
		return
	var effects := _effects.get_effects()
	for i in range(effects.size() - 1, -1, -1):
		if effects[i].id == item.id:
			_timed_effect = effects[i]
			_timed_bounce = item.timer_bounce
			return


## Сглаживание «отскок в конце» (easeOutBounce), t и результат — 0..1.
static func ease_out_bounce(t: float) -> float:
	const N := 7.5625
	const D := 2.75
	if t < 1.0 / D:
		return N * t * t
	if t < 2.0 / D:
		t -= 1.5 / D
		return N * t * t + 0.75
	if t < 2.5 / D:
		t -= 2.25 / D
		return N * t * t + 0.9375
	t -= 2.625 / D
	return N * t * t + 0.984375


func _on_effect_removed(effect: CarEffect) -> void:
	if effect == _timed_effect:
		_timed_effect = null


## Поднять надписи круга и места над сенсорными кнопками; 0 — вернуть в угол.
func set_bottom_inset(pixels: float) -> void:
	for node: Control in [_lap, _place]:
		if node == null:
			continue
		var height := node.offset_bottom - node.offset_top
		node.offset_bottom = -LAP_BOTTOM_MARGIN - pixels
		node.offset_top = node.offset_bottom - height
	_update_icons_limit()


## Цвет цифры места: 1 — золото, 2 — серебро, 3 — бронза, дальше — серый.
const PLACE_TINTS: Array[Color] = [Color(1.0, 0.95, 0.55), Color(0.85, 0.9, 1.0), Color(1.0, 0.7, 0.45), Color(0.7, 0.7, 0.75)]


## Место — справа снизу, зеркально надписи круга: «МЕСТО:», цифра, «/N».
func _build_place() -> void:
	_place = Control.new()
	_place.name = "Place"
	_place.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place.anchor_left = 1.0
	_place.anchor_right = 1.0
	_place.anchor_top = 1.0
	_place.anchor_bottom = 1.0
	_place.offset_left = -84.0
	_place.offset_right = -4.0
	_place.offset_top = _lap.offset_top
	_place.offset_bottom = _lap.offset_bottom
	add_child(_place)
	var caption := _outlined_label("МЕСТО:", 6)
	caption.position = Vector2(0, 30)
	caption.size = Vector2(36, 16)
	caption.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_place.add_child(caption)
	_place_number = TextureRect.new()
	_place_number.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place_number.texture = LAP_TEXTURES[0]
	_place_number.position = Vector2(36, 0)
	_place_number.size = Vector2(32, 48)
	_place_number.pivot_offset = _place_number.size * 0.5
	_place.add_child(_place_number)
	_place_total = _outlined_label("/4", 6)
	_place_total.position = Vector2(68, 30)
	_place_total.size = Vector2(12, 16)
	_place_total.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_place.add_child(_place_total)
	_place.visible = false


func _outlined_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", Color.WHITE)
	label.add_theme_color_override(&"font_outline_color", Color(0.12, 0.05, 0.1))
	label.add_theme_constant_override(&"outline_size", 3)
	return label


## Место участника: видно, когда в гонке больше одного; при смене — цифра «прыгает».
func _update_place() -> void:
	var count := _race.racers.size()
	_place.visible = count > 1 and _racer.place > 0
	if not _place.visible:
		return
	var place := clampi(_racer.place, 1, LAP_TEXTURES.size())
	_place_total.text = "/%d" % count
	if place == _place_shown:
		return
	var better := _place_shown == 0 or place < _place_shown
	_place_shown = place
	_place_number.texture = LAP_TEXTURES[place - 1]
	_place_number.modulate = PLACE_TINTS[mini(place, PLACE_TINTS.size()) - 1]
	if _place_tween != null:
		_place_tween.kill()
	_place_tween = create_tween()
	_place_tween.tween_property(_place_number, ^"scale", Vector2.ONE * (1.35 if better else 0.8), 0.12) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_place_tween.tween_property(_place_number, ^"scale", Vector2.ONE, 0.2) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Иконки участников не должны залезать на надпись круга.
func _update_icons_limit() -> void:
	if _racer_icons != null and is_inside_tree():
		_racer_icons.set_bottom_limit(_lap.get_viewport().get_visible_rect().size.y + _lap.offset_top)


## 83.456 -> «01:23», как таймер оригинала.
static func format_clock(seconds: float) -> String:
	var total := floori(seconds)
	return "%02d:%02d" % [mini(floori(total / 60.0), 99), total % 60]


## 83.456 -> «1:23.46» (для результатов).
static func format_time(seconds: float) -> String:
	var minutes := floori(seconds / 60.0)
	return "%d:%05.2f" % [minutes, seconds - minutes * 60.0]


func _on_countdown_tick(seconds_left: int) -> void:
	# Звук Countdown оригинала — один на весь отсчёт, в его начале.
	if seconds_left == _race.countdown_seconds:
		Sfx.play(self, COUNTDOWN_SOUND)
	# 3 -> кадр 0 («3»), 2 -> кадр 1, 1 -> кадр 2.
	_show_countdown(clampi(3 - seconds_left, 0, COUNTDOWN_TEXTURES.size() - 2))


func _show_countdown(frame: int) -> void:
	_countdown.texture = COUNTDOWN_TEXTURES[frame]
	_countdown.visible = true
	_countdown_left = MESSAGE_TIME


func _show_message(text: String, duration: float = MESSAGE_TIME) -> void:
	_center_label.text = text
	_center_label.visible = true
	_message_left = duration


func _on_lap_started(racer: RacerState, lap: int) -> void:
	if lap <= 1:
		return
	# Круг пройден: эмоция «круг» на иконке (IconEmote "Lap" оригинала).
	racer.car.emote(&"lap", 1.0)
	if racer != _racer:
		return
	Sfx.play(self, LAP_SOUND)
	_pop_lap_number()
	if lap == _race.laps:
		_show_message("ПОСЛЕДНИЙ КРУГ!")


## Цифра круга «прыгает»: ×1.5 и обратно (scale popup оригинала, easeOutExpo, 0.35 с).
func _pop_lap_number() -> void:
	if _lap_tween != null:
		_lap_tween.kill()
	_lap_number.pivot_offset = _lap_number.size * 0.5
	_lap_number.scale = Vector2.ONE
	_lap_tween = create_tween()
	_lap_tween.tween_property(_lap_number, ^"scale", Vector2.ONE * LAP_POP_SCALE, LAP_POP_TIME) \
			.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_lap_tween.tween_property(_lap_number, ^"scale", Vector2.ONE, LAP_POP_TIME) \
			.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)


func _on_racer_finished(racer: RacerState) -> void:
	if racer.finish_place == 1 and not _winner_shown:
		_show_winner(racer)
	elif racer == _racer:
		_show_message("ФИНИШ! %d место" % racer.finish_place, 3.0)


## Первый финишировал: победа у него, «проиграл» у остальных (FinishGame оригинала).
func _show_winner(winner: RacerState) -> void:
	_winner_shown = true
	for racer in _race.racers:
		racer.car.emote(&"win" if racer == winner else &"lose", 3.0)
	if winner == _racer:
		_winner_title.text = "поздравляю, %s" % winner.display_name
		_winner_sub.text = "ты победил!"
		Sfx.play(self, WIN_SOUND)
	else:
		_winner_title.text = "победил %s" % winner.display_name
		_winner_sub.text = LOSE_PHRASES.pick_random()
	_winner.visible = true
	_winner.position.y = -WINNER_SIZE.y - 8.0
	var tween := create_tween()
	tween.tween_property(_winner, ^"position:y", WINNER_TOP, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Плашка победителя (WinnerBg оригинала — скруглённый прямоугольник 8×8, растянутый).
func _build_winner_banner() -> void:
	_winner = NinePatchRect.new()
	_winner.name = "Winner"
	_winner.texture = WINNER_BG
	_winner.patch_margin_left = 3
	_winner.patch_margin_right = 3
	_winner.patch_margin_top = 3
	_winner.patch_margin_bottom = 3
	_winner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_winner.anchor_left = 0.5
	_winner.anchor_right = 0.5
	_winner.offset_left = -WINNER_SIZE.x * 0.5
	_winner.offset_right = WINNER_SIZE.x * 0.5
	_winner.size = WINNER_SIZE
	_winner.visible = false
	add_child(_winner)
	# Как в оригинале: строка победителя шрифтом Text ×2, подпись — ×1.
	_winner_title = _banner_label(12, 3.0, 14.0)
	_winner_sub = _banner_label(6, 20.0, 8.0)


func _banner_label(font_size: int, top: float, height: float) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
	label.add_theme_constant_override(&"outline_size", 3)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.position = Vector2(0.0, top)
	label.size = Vector2(WINNER_SIZE.x, height)
	_winner.add_child(label)
	return label


## Окно результатов — в общем стиле (UiStyle): по размеру содержимого, по центру.
## Поля окна результатов, px.
const RESULTS_PADDING := Vector2(18, 12)


func _style_results() -> void:
	# Таблица: место (золото/серебро/бронза), ник, время; текстовый список — для автотеста.
	_results_table = GridContainer.new()
	_results_table.columns = 3
	_results_table.add_theme_constant_override(&"h_separation", 16)
	_results_table.add_theme_constant_override(&"v_separation", 5)
	_results_table.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var box := _results_list.get_parent() as VBoxContainer
	# Поля шире, сверху — место под нижнюю половину заголовка «РЕЗУЛЬТАТЫ».
	var panel := box.get_parent() as PanelContainer
	panel.add_theme_stylebox_override(&"panel", UiStyle.panel_style(UiStyle.TITLE_TOP_EXTRA, RESULTS_PADDING))
	box.add_child(_results_table)
	box.move_child(_results_table, 0)


func _show_results() -> void:
	var lines := PackedStringArray()
	for child in _results_table.get_children():
		child.queue_free()
	for caption in ["место", "игрок", "время"]:
		var head := UiStyle.hint(caption)
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		# Под шапкой — чуть больше места, чем между строками.
		head.custom_minimum_size.y = 9
		head.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		_results_table.add_child(head)
	for racer in _race.get_sorted_racers():
		var time_text := format_time(racer.finish_time) if racer.finish_time >= 0.0 else "не доехал"
		lines.append("%d. %s  %s" % [racer.place, racer.display_name, time_text])
		var place := UiStyle.heading("%d" % racer.place, PLACE_TINTS[clampi(racer.place - 1, 0, PLACE_TINTS.size() - 1)])
		var name_label := UiStyle.heading(racer.display_name, UiStyle.OWN_COLOR if racer == _racer else Color.WHITE)
		var time_label := UiStyle.heading(time_text, Color.WHITE if racer.finish_time >= 0.0 else UiStyle.HINT_COLOR)
		for cell in [place, name_label, time_label]:
			(cell as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			_results_table.add_child(cell)
	_results_list.text = "\n".join(lines)
	# Кнопки: одиночная — «ещё раз» / «в меню»; сеть — хост ведёт всех в лобби, гость ждёт.
	var online := Network.session().is_online()
	var host := not online or Network.session().is_host()
	_restart_button.visible = host
	_restart_button.text = "В ЛОББИ" if online else "ЕЩЁ РАЗ"
	_menu_button.text = "ВЫЙТИ" if online else "В МЕНЮ"
	_wait_label.visible = not host
	_winner.visible = false
	# Иконки игроков слева не нужны: все уже в таблице (и окно на них наезжало).
	_racer_icons.visible = false
	_results.visible = true


func _on_restart_pressed() -> void:
	if Network.session().is_online():
		# Сеть: обратно в лобби на карте всех ведёт хост.
		Network.session().request_lobby()
	else:
		get_tree().reload_current_scene()


# --------------------------------------------------------------------------
# Сеть: лобби на карте и участники на ходу
# --------------------------------------------------------------------------

## Окно лобби, как в оригинале: спрайт «Лобби» на рамке, карта (хост листает < >), сколько
## игроков; пока хост один — «в комнате нет людей!» и синяя «пригласить» (копирует приглашение
## с ID игры, вспыхивает зелёным); снизу «НАЧАТЬ» (хост) или «ждём хоста».
const LOBBY_TITLE := preload("res://assets/original/textures/ui/lobby-000.png")
const INVITE_SOURCE := preload("res://assets/original/textures/ui/invitebutton-000.png")
## Окно лобби невысокое и узкое: под ним видно свою машину (её верх — около 125 px от верха
## экрана), слева — иконки игроков. Отступ между строками, поля, где буквы «Лобби» (спрайт
## 80×40, сверху 10 пустых строк — отступ от края экрана 12 px).
const LOBBY_GAP := 6
const LOBBY_PADDING := Vector2(12, 10)
const LOBBY_TOP := 2.0
## Зазор между иконками игроков и окном лобби, px.
const LOBBY_ICONS_GAP := 4.0


func show_lobby(is_host: bool) -> void:
	if _lobby != null:
		_lobby.queue_free()
	var session := Network.session()
	# В лобби время, круг и место ещё ничего не значат — окно занимает верх экрана вместо них.
	_set_race_info_visible(false)
	# Слева — о комнате (карта, кто в ней, «начать»), справа у хоста — ID и «пригласить».
	# Окно невысокое и не шире места между иконками игроков и краем: под ним видно свою машину.
	var about := UiStyle.column(LOBBY_GAP)
	# Карта: хост листает < > (все остаются в игре с тем же ID), остальные видят название.
	var map_row := UiStyle.row(4)
	if is_host:
		map_row.add_child(_map_arrow("<", -1))
	var map_label := UiStyle.heading(LobbyMenu.map_title(session.map_name))
	map_label.custom_minimum_size.x = 76
	map_row.add_child(map_label)
	if is_host:
		map_row.add_child(_map_arrow(">", 1))
	about.add_child(map_row)
	# Хост один — текст оригинала, иначе — сколько игроков.
	_lobby_empty = UiStyle.column(2)
	_lobby_empty.add_child(UiStyle.text("в комнате нет людей!"))
	_lobby_empty.add_child(UiStyle.hint("(вы будете гонять один)"))
	_lobby_empty.visible = false
	about.add_child(_lobby_empty)
	_lobby_label = UiStyle.text("")
	about.add_child(_lobby_label)
	# ID игры: по нему друзья входят (меню, кнопка с человечком).
	var id_panel := PanelContainer.new()
	id_panel.theme_type_variation = &"InsetPanel"
	id_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var id_box := UiStyle.column(2)
	id_panel.add_child(id_box)
	var id_row := UiStyle.row(6)
	id_box.add_child(id_row)
	var id_caption := UiStyle.hint("ID игры")
	id_caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	id_row.add_child(id_caption)
	id_row.add_child(UiStyle.heading(session.session_id if session.session_id != "" else "…"))
	var content: Control
	if is_host:
		_invite = UiStyle.button("пригласить", _on_invite, false, UiStyle.Kind.SMALL)
		_invite.icon = _share_icon()
		_invite.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		id_box.add_child(_invite)
		# Можно ли войти через интернет — под кнопкой, в той же плашке.
		_online_label = UiStyle.hint("")
		id_box.add_child(_online_label)
		if not session.online_status_changed.is_connected(_update_lobby):
			session.online_status_changed.connect(_update_lobby)
		# Без фокуса: пробел (парирование) в лобби не должен запускать гонку. Enter — тоже «начать».
		var start := UiStyle.button("НАЧАТЬ", func() -> void: (get_parent() as Race).start_requested(), false)
		start.custom_minimum_size.x = 96
		start.tooltip_text = "Enter"
		about.add_child(start)
		var actions := UiStyle.column(LOBBY_GAP)
		actions.add_child(id_panel)
		actions.add_child(UiStyle.hint("Esc: выйти"))
		var columns := UiStyle.row(12)
		columns.add_child(about)
		var divider := VSeparator.new()
		divider.add_theme_stylebox_override(&"separator", _divider_style())
		columns.add_child(divider)
		columns.add_child(actions)
		content = columns
	else:
		about.add_child(id_panel)
		var wait := UiStyle.column(2)
		wait.add_child(UiStyle.text("ждём, пока хост начнёт…"))
		wait.add_child(UiStyle.hint("Esc: выйти"))
		about.add_child(wait)
		content = about
	_lobby = UiStyle.window("", content, LOBBY_TITLE, LOBBY_PADDING)
	_lobby.name = "Lobby"
	# Сверху по центру, как в оригинале; буквы «Лобби» — на LOBBY_TOP от края экрана.
	UiStyle.anchor_at(_lobby, Control.PRESET_CENTER_TOP, Control.GROW_DIRECTION_END, Vector2(0, LOBBY_TOP))
	add_child(_lobby)
	if not session.players_changed.is_connected(_update_lobby):
		session.players_changed.connect(_update_lobby)
	_update_lobby()


## Окно лобби — по центру, но не на иконках игроков слева (длинные ники): если задевает —
## сдвигается вправо ровно настолько, чтобы не задевать (таймер в лобби спрятан, справа свободно).
func _keep_lobby_clear() -> void:
	if _lobby == null or not is_instance_valid(_lobby) or not _lobby.is_inside_tree():
		return
	var icons_right := 0.0
	for node in _racer_icons.find_children("*", "Control", true, false):
		var control := node as Control
		if control.is_visible_in_tree() and control.size.x > 0.0:
			icons_right = maxf(icons_right, control.get_global_rect().end.x)
	var screen := get_viewport().get_visible_rect().size.x
	var half := _lobby.size.x * 0.5
	var shift := clampf(icons_right + LOBBY_ICONS_GAP - (screen * 0.5 - half), 0.0, maxf(screen * 0.5 - half - 2.0, 0.0))
	_lobby.offset_left = shift
	_lobby.offset_right = shift


## Время (с ячейкой предмета), круг и место — в гонке; в лобби прячутся.
func _set_race_info_visible(value: bool) -> void:
	for node: Control in [get_node(^"TimerPanel") as Control, _lap]:
		node.visible = value
	_place.modulate.a = 1.0 if value else 0.0


## Тонкая бледная черта между колонками окна лобби.
static func _divider_style() -> StyleBoxLine:
	var line := StyleBoxLine.new()
	line.vertical = true
	line.color = Color(1, 1, 1, 0.18)
	line.thickness = 1
	return line


## Кнопка смены карты в лобби (хост): step −1 — предыдущая, +1 — следующая.
## Без фокуса: пробел (парирование) её не нажимает.
func _map_arrow(text: String, step: int) -> Button:
	var button := UiStyle.button(text, func() -> void:
		var maps := LobbyMenu.list_maps()
		if maps.is_empty():
			return
		var index := maps.find(Network.session().map_name)
		Network.session().request_map(maps[posmod(index + step, maps.size())]), false, UiStyle.Kind.SMALL_SECONDARY)
	button.tooltip_text = "другая карта: все остаются в игре, ID не меняется"
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return button


## «Пригласить»: приглашение с ID игры — в буфер обмена (как Clipboard оригинала).
func _on_invite() -> void:
	var id := Network.session().session_id
	DisplayServer.clipboard_set("Пойдём погоняем в 3Dynamic Force! ID игры: %s" % id if id != "" else id)
	UiStyle.flash(_invite, "скопировано!")


## Значок «поделиться» с кнопки InviteButton оригинала (тёмные пиксели её левой части).
static func _share_icon() -> Texture2D:
	var source := INVITE_SOURCE.get_image()
	source.convert(Image.FORMAT_RGBA8)
	var icon := Image.create(9, 9, false, Image.FORMAT_RGBA8)
	for y in 9:
		for x in 9:
			var color := source.get_pixel(3 + x, 2 + y)
			if color.get_luminance() < 0.9:
				icon.set_pixel(x, y, color)
	return ImageTexture.create_from_image(icon)


func hide_lobby() -> void:
	_set_race_info_visible(true)
	if _lobby != null:
		_lobby.queue_free()
		_lobby = null


func _update_lobby() -> void:
	var session := Network.session()
	var alone := session.is_host() and session.players.size() <= 1
	if _lobby_label != null and is_instance_valid(_lobby_label):
		_lobby_label.text = "игроков: %d из %d" % [maxi(session.players.size(), 1), Network.MAX_PLAYERS]
		_lobby_label.visible = not alone
	if _lobby_empty != null and is_instance_valid(_lobby_empty):
		_lobby_empty.visible = alone
	if _online_label != null and is_instance_valid(_online_label):
		match session.online_status:
			Network.OnlineStatus.AVAILABLE:
				_online_label.text = "можно и через интернет"
				_online_label.tooltip_text = ""
			Network.OnlineStatus.CONNECTING:
				_online_label.text = "подключаемся к интернету…"
				_online_label.tooltip_text = ""
			Network.OnlineStatus.UNAVAILABLE:
				_online_label.text = "только локальная сеть"
				_online_label.tooltip_text = "интернета нет, зайти можно только из этой же сети"
			_:
				_online_label.text = "только локальная сеть"
				_online_label.tooltip_text = ""

## Участник добавился / ушёл (сеть) — иконки слева.
## Уведомление сверху по центру (вошёл/вышел из лобби): строки копятся столбиком,
## каждая держится NOTIFY_TIME и тает.
const NOTIFY_TIME := 3.0


func notify(text: String, color: Color = Color.WHITE, sound: AudioStream = null) -> void:
	if _notices == null:
		_notices = VBoxContainer.new()
		_notices.name = "Notices"
		_notices.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_notices.alignment = BoxContainer.ALIGNMENT_BEGIN
		_notices.anchor_left = 0.5
		_notices.anchor_right = 0.5
		_notices.offset_left = -110.0
		_notices.offset_right = 110.0
		_notices.offset_top = 4.0
		_notices.add_theme_constant_override(&"separation", 3)
		add_child(_notices)
	var label := _outlined_label(text, 6)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override(&"font_color", color)
	_notices.add_child(label)
	if sound != null:
		Sfx.play(self, sound)
	var tween := label.create_tween()
	tween.tween_interval(NOTIFY_TIME)
	tween.tween_property(label, ^"modulate:a", 0.0, 0.5)
	tween.tween_callback(label.queue_free)


func racer_added(racer: RacerState) -> void:
	if _race != null:
		_racer_icons.add_racer(racer)


func racer_removed(racer: RacerState) -> void:
	_racer_icons.remove_racer(racer)
