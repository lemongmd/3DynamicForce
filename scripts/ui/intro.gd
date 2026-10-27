class_name IntroScreen
extends Control
## Интро при запуске игры, как в оригинале (IntroS): под Menu_start (10.67 с), чёрный экран,
## картинки по очереди, каждая быстро проявляется и медленно гаснет (tween offsetOpacity
## easeOutExpo ping-pong, кадр раз в INTROSPEED 3.9 с); на «ПРЕДСТАВЛЯЕМ...» — белые вспышки
## и рост до ×5, в 10.612 с — меню (там уже Menu_loop). Автор ремейка: интро должно быть
## «под бит» — поэтому время берётся из позиции музыки (GameMusic.playback_position), а не
## из таймеров, а смены кадров — ровно на ударах трека (см. SEGMENTS). Надписи кадров — нашим
## спрайтовым шрифтом (TITLE_SIZE). Наш кадр с логотипом
## Claude (просьба автора ремейка) делит слот «Помощь в создании» пополам.
## Перед интро — прогрев (Warmup: карты, объекты, шейдеры; первая гонка не подвисает) на
## картинке загрузки (как при запуске), чтобы сама заставка шла без рывков.
## Пробел, Enter, Esc, клик или касание — пропустить (сразу меню и Menu_loop).
## Проверочные ключи сборки (-- --race=…, --list-maps) интро пропускают сразу.

const MENU_SCENE := "res://scenes/net/lobby_menu.tscn"
const MENU_TEXTURES := "res://assets/original/textures/menu/"
## Логотип Claude для нашего кадра (от автора ремейка, 128×48).
const CLAUDE_LOGO := preload("res://assets/textures/ui/claude_logo.png")
## Логотип выше на столько, px: начинается почти там же, где значки elita и lemongd.
const CLAUDE_LOGO_PAD := 8.0
## Надписи «Помощь в создании:», «Помощь с ремейком:», «ПРЕДСТАВЛЯЕМ...» — нашим спрайтовым
## шрифтом (Text оригинала, шрифт темы; просьба автора ремейка): заголовки ×2, «ПРЕДСТАВЛЯЕМ» ×3.
## В картинках оригинала они вшиты другим шрифтом, его в проекте нет.
const TITLE_SIZE := 12
const PRESENT_SIZE := 18
## Кадр «Помощь в создании» — как intro-a-001 (224×96): заголовок сверху, значки elita
## и lemongd — из intro-a-001 со строки HELPERS_TOP (без вшитой надписи).
const FRAME_SIZE := Vector2(224, 96)
const HELPERS_TOP := 26
const PRESENT_BOX := Vector2(320, 32)
const SPLASH := preload("res://assets/splash.png")
const UI_THEME := preload("res://ui/main_theme.tres")
## Фон загрузки — как boot_splash/bg_color в project.godot.
const SPLASH_COLOR := Color(0.078, 0.078, 0.149)
## Кадры: картинка intro-a-NNN (CLAUDE_FRAME — наш), начало и конец, с музыки. Menu_start —
## 180 ударов в минуту (удар 0.333 с, такт 1.333 с; сильные удары по замеру — 4.00, 7.98,
## 9.31 с): в оригинале кадры раз в 3.9 с — на 0.1–0.2 с раньше удара, у нас ровно на ударах
## 4.0 и 8.0 с; кадр Claude — с удара 6.0 с (середина слота «Помощь в создании»).
const CLAUDE_FRAME := -1
const SEGMENTS := [[0, 0.0, 4.0], [1, 4.0, 6.0], [CLAUDE_FRAME, 6.0, 8.0], [2, 8.0, 12.0]]
## «ПРЕДСТАВЛЯЕМ...»: вспышки с 9.33 с через 0.15 с (белый слой на 0.075 с), рост до ×5 за
## 1.4 с (easeInSine), меню — в 10.612 с.
const PULSE_AT := 9.33
const PULSE_EVERY := 0.15
const ZOOM_TIME := 1.4
const ZOOM_SCALE := 5.0
const END_AT := 10.612
## Картинки — по центру экрана, на 4 px ниже середины (Intro оригинала: x 192, y 112 из 384×216).
const CENTER_DROP := 4.0
## Шаг прогрева рисуется столько кадров.
const WARM_FRAMES := 3
const SKIP_ARGS: Array[String] = ["--race=", "--list-maps"]

enum Phase { LOADING, INTRO, LEAVING }

var _scale_mode_before: Window.ContentScaleMode = Window.CONTENT_SCALE_MODE_VIEWPORT
var _phase := Phase.LOADING
var _warmup: Warmup
var _warm_frames := 0
var _skip_after_loading := false
## Время интро без звука (тесты, нет звуковой карты).
var _elapsed := 0.0
var _splash: Control
var _flash: ColorRect
var _hint: Label
var _frames: Dictionary = {}


func _ready() -> void:
	# Без экрана (--headless) показывать и прогревать нечего — сразу меню.
	var skip_intro := DisplayServer.get_name() == "headless"
	for arg in OS.get_cmdline_user_args():
		for prefix in SKIP_ARGS:
			skip_intro = skip_intro or arg.begins_with(prefix)
	if skip_intro:
		_phase = Phase.LEAVING
		get_tree().change_scene_to_file.call_deferred(MENU_SCENE)
		return
	_scale_mode_before = get_window().content_scale_mode
	# Как меню: база 384×216, но масштаб плавный (рост «ПРЕДСТАВЛЯЕМ...» ×5).
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	_build()
	_warmup = Warmup.new()
	_warmup.name = "Warmup"
	add_child(_warmup)


func _exit_tree() -> void:
	get_window().content_scale_mode = _scale_mode_before


func _process(delta: float) -> void:
	match _phase:
		Phase.LOADING:
			_process_loading()
		Phase.INTRO:
			_elapsed += delta
			var music := GameMusic.player().playback_position()
			_show_time(music if music >= 0.0 else _elapsed)


func _input(event: InputEvent) -> void:
	if _phase == Phase.LEAVING:
		return
	var key := event as InputEventKey
	var skip := key != null and key.pressed and not key.echo \
			and key.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE]
	skip = skip or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed)
	skip = skip or (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed)
	if not skip:
		return
	get_viewport().set_input_as_handled()
	if _phase == Phase.LOADING:
		_skip_after_loading = true
	else:
		_go_menu(true)


## Прогрев: шаг, WARM_FRAMES кадров на отрисовку, следующий; всё — интро под музыку.
func _process_loading() -> void:
	if _warm_frames > 0:
		_warm_frames -= 1
		return
	if _warmup.remaining() > 0:
		_warmup.step()
		_warm_frames = WARM_FRAMES
		return
	_warmup.clear()
	if _skip_after_loading:
		_go_menu(true)
		return
	_splash.visible = false
	_phase = Phase.INTRO
	GameMusic.player().play_intro()


func _build() -> void:
	theme = UI_THEME
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(black)
	for segment: Array in SEGMENTS:
		var frame: int = segment[0]
		var node := _build_frame(frame)
		_frames[frame] = node
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		node.pivot_offset = node.size * 0.5
		node.visible = false
		add_child(node)
	_flash = ColorRect.new()
	_flash.color = Color.WHITE
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.visible = false
	add_child(_flash)
	# Загрузка — та же картинка, что при запуске игры (boot splash), чтобы переход был незаметен.
	var splash := ColorRect.new()
	splash.color = SPLASH_COLOR
	splash.set_anchors_preset(Control.PRESET_FULL_RECT)
	splash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var logo := TextureRect.new()
	logo.texture = SPLASH
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.set_anchors_preset(Control.PRESET_FULL_RECT)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	splash.add_child(logo)
	_hint = Label.new()
	_hint.theme_type_variation = &"HintLabel"
	_hint.text = "грузим трассы..."
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_top = -24.0
	_hint.offset_bottom = -12.0
	splash.add_child(_hint)
	_splash = splash
	add_child(splash)


## Кадр интро: картинка оригинала или собранный из значков и надписи нашим шрифтом.
func _build_frame(frame: int) -> Control:
	var box := Control.new()
	box.size = FRAME_SIZE
	match frame:
		0:
			return _texture_rect(load("%sintro-a-000.png" % MENU_TEXTURES) as Texture2D)
		1:
			_add_label(box, "Помощь в создании:", TITLE_SIZE, Rect2(0, 6, FRAME_SIZE.x, 18))
			var icons := AtlasTexture.new()
			icons.atlas = load("%sintro-a-001.png" % MENU_TEXTURES) as Texture2D
			icons.region = Rect2(0, HELPERS_TOP, FRAME_SIZE.x, FRAME_SIZE.y - HELPERS_TOP)
			var rect := _texture_rect(icons)
			rect.position.y = HELPERS_TOP
			box.add_child(rect)
		CLAUDE_FRAME:
			_add_label(box, "Помощь с ремейком:", TITLE_SIZE, Rect2(0, 6, FRAME_SIZE.x, 18))
			var logo := _texture_rect(CLAUDE_LOGO)
			# Сразу под заголовком (у картинки свои 13 px пустоты сверху), как значки elita и lemongd.
			logo.position = Vector2((FRAME_SIZE.x - logo.size.x) * 0.5, HELPERS_TOP - CLAUDE_LOGO_PAD)
			box.add_child(logo)
		2:
			box.size = PRESENT_BOX
			_add_label(box, "ПРЕДСТАВЛЯЕМ...", PRESENT_SIZE, Rect2(Vector2.ZERO, PRESENT_BOX))
	return box


func _texture_rect(texture: Texture2D) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = texture
	rect.stretch_mode = TextureRect.STRETCH_KEEP
	rect.size = texture.get_size()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


func _add_label(parent: Control, text: String, font_size: int, rect: Rect2) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", font_size)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.position = rect.position
	label.size = rect.size
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)


## Вид интро в момент t (с начала Menu_start).
func _show_time(t: float) -> void:
	if t >= END_AT:
		_go_menu(false)
		return
	for segment: Array in SEGMENTS:
		var node: Control = _frames[segment[0]]
		var start: float = segment[1]
		var end: float = segment[2]
		node.visible = t >= start and t < end
		if not node.visible:
			continue
		# На широком экране видно больше по ширине — центр от размера экрана.
		node.position = size * 0.5 + Vector2(0.0, CENTER_DROP) - node.size * 0.5
		# Ping-pong: первая половина — проявление (easeOutExpo), вторая — то же назад.
		var half := (end - start) * 0.5
		var x := (t - start) / half
		node.modulate.a = _ease_out_expo(x if x <= 1.0 else 2.0 - x)
		node.scale = Vector2.ONE
		if segment[0] != CLAUDE_FRAME and t >= PULSE_AT:
			var zoom := _ease_in_sine(minf((t - PULSE_AT) / ZOOM_TIME, 1.0))
			node.scale = Vector2.ONE * lerpf(1.0, ZOOM_SCALE, zoom)
	_flash.visible = t >= PULSE_AT and fmod(t - PULSE_AT, PULSE_EVERY) < PULSE_EVERY * 0.5


## skip — пропустили: Menu_start обрывается, сразу Menu_loop.
func _go_menu(skip: bool) -> void:
	if _phase == Phase.LEAVING:
		return
	_phase = Phase.LEAVING
	if skip:
		GameMusic.player().play(GameMusic.MENU_LOOP)
	get_tree().change_scene_to_file(MENU_SCENE)


static func _ease_out_expo(x: float) -> float:
	return 1.0 if x >= 1.0 else maxf(1.0 - pow(2.0, -10.0 * x), 0.0)


static func _ease_in_sine(x: float) -> float:
	return 1.0 - cos(x * PI * 0.5)
