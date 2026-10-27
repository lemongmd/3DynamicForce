class_name RadioPanel
extends CanvasLayer
## Мини-плеер магнитолы своей машины (пасхалка автора ремейка; вид — как мини-плеер Spotify,
## в нашем стиле): клавиша 7 — плашка выезжает сверху: обложка, название и исполнитель
## (CarRadio.info / cover), полоска хода трека, кнопки «назад», «играть/пауза», «вперёд».
## Пока открыт: 1 — назад, 2 — пауза, 3 — вперёд; 7 — спрятать. Кнопки без фокуса: пробел
## (парирование) их не нажмёт.

const UI_THEME := preload("res://ui/main_theme.tres")
const TOGGLE_KEYS: Array[Key] = [KEY_7, KEY_KP_7]
## Плашка выезжает сверху за SLIDE_TIME до отступа TOP, px.
const SLIDE_TIME := 0.25
const TOP := 4.0
const PADDING := Vector2(5, 5)
const COVER_SIZE := 32.0
## Ширина колонки с названием; название крупно (×2), если влезает, иначе ×1.
const TEXT_WIDTH := 112.0
const TITLE_BIG := 12
const TITLE_SMALL := 6
const PROGRESS_HEIGHT := 2.0
const PROGRESS_BACK := Color(1, 1, 1, 0.25)
## Значки кнопок 7×7 (X — белый пиксель).
const ICON_PREV := ["X....X", "X...XX", "X..XXX", "X.XXXX", "X..XXX", "X...XX", "X....X"]
const ICON_NEXT := ["X....X", "XX...X", "XXX..X", "XXXX.X", "XXX..X", "XX...X", "X....X"]
const ICON_PLAY := ["X.....", "XXX...", "XXXXX.", "XXXXXX", "XXXXX.", "XXX...", "X....."]
const ICON_PAUSE := ["XX.XX", "XX.XX", "XX.XX", "XX.XX", "XX.XX", "XX.XX", "XX.XX"]
## Обложки нет — нота на цветном квадрате (цвет — от названия).
const NOTE := [
	"........", "...XXXX.", "...X..X.", "...X..X.", "...X..X.", ".XXX.XX.", "XXXXXXX.", ".XX.....",
]

## Машина, чьей магнитолой управляем (своя).
var car: CarController:
	set(value):
		if _radio != null and _radio.changed.is_connected(_refresh):
			_radio.changed.disconnect(_refresh)
		car = value
		_radio = CarRadio.of(car) if car != null else null
		if _radio != null:
			_radio.changed.connect(_refresh)
		_refresh()

var _radio: CarRadio
var _root: Control
var _plate: PanelContainer
var _cover: TextureRect
var _title: Label
var _artist: Label
var _progress: ColorRect
var _play: Button
var _icons: Dictionary = {}
var _open := false
var _tween: Tween


func _ready() -> void:
	layer = 6
	for icon_name in ["prev", "next", "play", "pause"]:
		_icons[icon_name] = _icon({"prev": ICON_PREV, "next": ICON_NEXT, "play": ICON_PLAY, "pause": ICON_PAUSE}[icon_name])
	_root = Control.new()
	_root.theme = UI_THEME
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_plate = PanelContainer.new()
	_plate.add_theme_stylebox_override(&"panel", UiStyle.panel_style(0.0, PADDING))
	var row := UiStyle.row(6)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	_plate.add_child(row)
	_cover = TextureRect.new()
	_cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cover.stretch_mode = TextureRect.STRETCH_SCALE
	_cover.custom_minimum_size = Vector2(COVER_SIZE, COVER_SIZE)
	row.add_child(_cover)
	var text := VBoxContainer.new()
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.add_theme_constant_override(&"separation", 2)
	text.custom_minimum_size.x = TEXT_WIDTH
	row.add_child(text)
	_title = Label.new()
	_title.clip_text = true
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title.custom_minimum_size.x = TEXT_WIDTH
	text.add_child(_title)
	_artist = UiStyle.hint("")
	_artist.clip_text = true
	_artist.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_artist.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_artist.custom_minimum_size.x = TEXT_WIDTH
	text.add_child(_artist)
	var bar := ColorRect.new()
	bar.color = PROGRESS_BACK
	bar.custom_minimum_size = Vector2(TEXT_WIDTH, PROGRESS_HEIGHT)
	text.add_child(bar)
	_progress = ColorRect.new()
	_progress.color = Color.WHITE
	_progress.size = Vector2(0.0, PROGRESS_HEIGHT)
	bar.add_child(_progress)
	var buttons := UiStyle.row(3)
	# Кнопки — своего размера, по середине высоты плашки (не тянутся под обложку).
	buttons.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(buttons)
	buttons.add_child(_button("prev", _on_skip.bind(-1), UiStyle.Kind.SMALL_SECONDARY, Vector2(16, 16)))
	_play = _button("play", _on_play, UiStyle.Kind.SMALL, Vector2(20, 18))
	buttons.add_child(_play)
	buttons.add_child(_button("next", _on_skip.bind(1), UiStyle.Kind.SMALL_SECONDARY, Vector2(16, 16)))
	UiStyle.anchor_at(_plate, Control.PRESET_CENTER_TOP, Control.GROW_DIRECTION_END)
	_plate.visible = false
	_root.add_child(_plate)
	_refresh()


func _process(_delta: float) -> void:
	if not _plate.visible or _radio == null:
		return
	var length := 0.0
	var path := _radio.current()
	if _radio.is_playing() and not path.is_empty():
		var stream := load(path) as AudioStream
		length = stream.get_length() if stream != null else 0.0
	var share := clampf(_radio.playback_position() / length, 0.0, 1.0) if length > 0.0 else 0.0
	_progress.size.x = share * TEXT_WIDTH


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or car == null:
		return
	var code := key.physical_keycode
	if code in TOGGLE_KEYS:
		_set_open(not _open)
	elif _open and (code == KEY_1 or code == KEY_KP_1):
		_on_skip(-1)
	elif _open and (code == KEY_2 or code == KEY_KP_2):
		_on_play()
	elif _open and (code == KEY_3 or code == KEY_KP_3):
		_on_skip(1)
	else:
		return
	get_viewport().set_input_as_handled()


func _set_open(open: bool) -> void:
	_open = open
	if _tween != null:
		_tween.kill()
	_plate.visible = true
	_refresh()
	var hidden := -_plate.get_combined_minimum_size().y - 4.0
	if open:
		_set_top(hidden)
	_tween = create_tween()
	_tween.tween_method(_set_top, _plate.offset_top, TOP if open else hidden, SLIDE_TIME) \
			.set_trans(Tween.TRANS_BACK if open else Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT if open else Tween.EASE_IN)
	if not open:
		_tween.tween_callback(func() -> void: _plate.visible = false)


func _set_top(value: float) -> void:
	_plate.offset_top = value
	_plate.offset_bottom = value


## Обложка, название, исполнитель и значок «играть/пауза» — по текущему треку.
func _refresh() -> void:
	if _plate == null:
		return
	var path := _radio.current() if _radio != null else ""
	var info := CarRadio.info(path) if not path.is_empty() else {"title": "треков нет", "artist": ""}
	var cover := CarRadio.cover(path) if not path.is_empty() else null
	_cover.texture = cover if cover != null else _note_cover(String(info["title"]))
	_title.text = String(info["title"])
	# Крупно (×2), если название влезает; иначе как подпись (×1).
	var font := _title.get_theme_font(&"font")
	var fits := font != null and font.get_string_size(_title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_BIG).x <= TEXT_WIDTH
	_title.add_theme_font_size_override(&"font_size", TITLE_BIG if fits else TITLE_SMALL)
	_artist.text = String(info["artist"])
	_play.icon = _icons["pause"] if _radio != null and _radio.is_playing() else _icons["play"]


func _on_play() -> void:
	if _radio != null:
		_radio.toggle_pause()


func _on_skip(step: int) -> void:
	if _radio != null:
		_radio.skip(step)


func _button(icon_name: String, callback: Callable, kind: UiStyle.Kind, minimum: Vector2) -> Button:
	var button := UiStyle.button("", callback, false, kind)
	button.icon = _icons[icon_name]
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.custom_minimum_size = minimum
	return button


## Пиксельный значок из строк (X — белый).
static func _icon(rows: Array) -> ImageTexture:
	var image := Image.create(String(rows[0]).length(), rows.size(), false, Image.FORMAT_RGBA8)
	for y in rows.size():
		var row := String(rows[y])
		for x in row.length():
			if row[x] == "X":
				image.set_pixel(x, y, Color.WHITE)
	return ImageTexture.create_from_image(image)


## Обложка-заглушка: нота на квадрате цвета от названия (×4 до 32 px).
static func _note_cover(title_text: String) -> ImageTexture:
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color.from_hsv(float(absi(title_text.hash()) % 360) / 360.0, 0.55, 0.6))
	for y in NOTE.size():
		for x in String(NOTE[y]).length():
			if String(NOTE[y])[x] == "X":
				image.set_pixel(x, y, Color.WHITE)
	return ImageTexture.create_from_image(image)
