class_name LobbyMenu
extends Control
## Главное меню как в оригинале (макет Menu, логика MenuS): фон MenuBackground, логотип
## пульсирует в такт, посередине — панель (menupanelbg) со страницами; при смене страницы
## панель меняет размер за 1/6 с с отскоком (Change page оригинала). Страницы:
##   * главная — кнопки-кресты оригинала: «играть» (по центру), гараж (слева), титры (справа),
##     «с друзьями» (снизу слева, кадр «вход» оригинала), настройки (снизу справа — шестерёнка
##     на пустом кресте оригинала);
##   * «где покатаемся?» — картинки карт оригинала (menuselectmap; наши карты — «абстракция»,
##     «?» — случайная), под ними «ОДИН» (одиночный заезд) и «С ДРУЗЬЯМИ» (создать игру Tube);
##   * «на чём поедем?» — гараж (GaragePage) и ник;
##   * «с друзьями» — вход по ID, игры в локальной сети, «ПРОВЕРКА СЕТИ» (NetCheck);
##   * настройки (SettingsPanel); титры — отдельный экран, как Credits оригинала.
## Внизу — «mace dev 2023» (автор оригинала) и состояние сети (иконки menuconnectionstatus: трекеры отвечают —
## «подключено», нет — «только локальная сеть»), вверху справа — ник и рожица цвета скина.
## Ник, карта и скин запоминаются в user://settings.cfg. Музыка — Menu_start, потом Menu_loop.
## Меню рисуется в полном разрешении окна (content_scale_mode = canvas_items), как у оригинала:
## пиксели крупные, но пульс логотипа и вращение фигур — плавные (в 384×216 они рябили).
## Своя картинка карты для меню — res://assets/textures/maps/<карта>.png (build_map_thumbs.gd).

const SETTINGS_PATH := "user://settings.cfg"
const TRACKS_DIR := "res://scenes/tracks/"
const LOGO := preload("res://assets/image.png")
## Названия карт для меню (остальные — по имени файла).
const MAP_TITLES := {"remake_01": "Трамплины", "map_a": "Хим. зона", "map_b": "Снежная", "map_d": "Пляж",
		"map_e": "Стройка", "map_f": "Шинозавод", "map_g": "Аквапарк", "map_h": "Радужная"}
## Картинки карт оригинала (menuselectmap): кадр по карте; наши и свои карты — «абстракция»,
## случайная — «?». Порядок кнопок — как в оригинале, наши карты — после.
const MAP_THUMBS := {"map_a": 0, "map_b": 1, "map_d": 3, "map_e": 4, "map_f": 5, "map_g": 6}
const THUMB_OWN := 7
const OWN_THUMBS := "res://assets/textures/maps/"
const THUMB_RANDOM := 8
const RANDOM_MAP := "?"
## Сайт автора оригинала (титры).
const AUTHOR_SITE := "https://macestudios.ru/"
const MENU_TEXTURES := "res://assets/original/textures/menu/"
const PANEL_TEXTURE := preload("res://assets/original/textures/menu/menupanelbg.png")
const FACE := preload("res://assets/original/textures/main/playercaricon-none-000.png")
## Кадры кнопок-крестов menustartbutton.
enum StartFrame { PLAY = 0, SKIN = 1, CREDITS = 2, BACK = 3, FRIENDS = 8, EMPTY = 9 }
enum Page { MAIN, MAPS, GARAGE, FRIENDS, SETTINGS }
## Центр панели по высоте (как в оригинале: 132 из 216) и отступы содержимого.
const PANEL_Y := 132.0
const PANEL_PAD := Vector2(16, 14)
const MAIN_PANEL := Vector2(192, 84)
## Стрелка «назад» от левого верхнего угла панели, px.
const BACK_OFFSET := Vector2(6, 9)
## Логотип: на главной — на месте оригинала (центр y = 56), на остальных страницах уезжает вверх,
## чтобы панель с картами/гаражом не наезжала на него.
const LOGO_Y_MAIN := 56.0
const LOGO_Y_PAGE := 28.0
## Панель не залезает под логотип и под нижние надписи (отступы, px).
const PANEL_GAP_TOP := 4.0
const PANEL_GAP_BOTTOM := 18.0
const PAGE_TIME := 1.0 / 6.0
## Логотип: сжимается до 0.95 за 1/3 с и снова (как в оригинале — в такт музыке).
const LOGO_BEAT := 1.0 / 3.0
## Шестерёнка настроек на пустом кресте (кадр 9): Y — жёлтый, O — оранжевый, K — контур.
const GEAR := [
	"...KKK...",
	".KKKYKKK.",
	".KYYYYYK.",
	"KKYOOOYKK",
	"KYYOKOYYK",
	"KKYOOOYKK",
	".KYYYYYK.",
	".KKKYKKK.",
	"...KKK...",
]

var _nick: LineEdit
var _map_names: PackedStringArray = []
var _map_buttons: Dictionary = {}
var _selected_map_name := ""
var _selected_label: Label
var _join_id: LineEdit
var _games: VBoxContainer
var _status: Label
var _skin: CarSkin = CarSkin.from_code(CarSkin.DEFAULT_CODE)
var _check_button: Button
var _check_result: Label

var _background: MenuBackground
var _logo: TextureRect
var _panel: NinePatchRect
var _panel_size := MAIN_PANEL
var _panel_tween: Tween
var _pages: Dictionary = {}
var _page: Page = Page.MAIN
var _back: TextureButton
var _credits: Control
var _garage: GaragePage
var _author: Label
var _player_name: Label
var _player_face: TextureRect
var _status_icon: TextureRect
var _status_text: Label
var _probes: Array[WebSocketPeer] = []
var _probe_time := 0.0
var _fade: ColorRect
var _toast_tween: Tween
var _logo_y := LOGO_Y_MAIN
var _scale_mode_before: Window.ContentScaleMode = Window.CONTENT_SCALE_MODE_VIEWPORT
## Титры прокручиваются сами (как в кино), колесо мыши тоже работает.
var _credits_scroll := 0.0
const CREDITS_SPEED := 10.0


func _ready() -> void:
	var net := Network.session()
	_scale_mode_before = get_window().content_scale_mode
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	_build_ui()
	GameMusic.player().play_menu()
	_load_settings()
	_refresh_player()
	_toast(net.last_end_reason)
	net.last_end_reason = ""
	if not Network.is_available():
		_toast("Сетевая игра недоступна: нет WebRTC (addons/webrtc_native)")
	_start_probe()
	# Проверка собранной игры: «-- --race=map_e» — сразу одиночный заезд на карте.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--race=") and _map_names.has(arg.trim_prefix("--race=")):
			_select_map(arg.trim_prefix("--race="), false)
			_on_single.call_deferred()
	net.start_listening()
	net.games_changed.connect(_refresh_games)
	_refresh_games()
	_show_page(Page.MAIN, false)


func _exit_tree() -> void:
	get_window().content_scale_mode = _scale_mode_before
	var net := Network.session()
	net.stop_listening()
	if net.games_changed.is_connected(_refresh_games):
		net.games_changed.disconnect(_refresh_games)
	for probe in _probes:
		probe.close()


func _process(delta: float) -> void:
	_layout()
	_poll_probe(delta)
	if _credits.visible:
		var scroll := _credits.get_meta(&"scroll") as ScrollContainer
		_credits_scroll += CREDITS_SPEED * delta
		if absf(scroll.scroll_vertical - _credits_scroll) > 2.0:
			_credits_scroll = scroll.scroll_vertical  # прокрутили колесом — едем дальше оттуда
		scroll.scroll_vertical = int(_credits_scroll)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"ui_cancel"):
		return
	if _credits.visible:
		_close_credits()
	elif _page != Page.MAIN:
		_go_back()
	else:
		return
	get_viewport().set_input_as_handled()


# --------------------------------------------------------------------------
# Сборка интерфейса
# --------------------------------------------------------------------------

func _build_ui() -> void:
	_background = MenuBackground.new()
	add_child(_background)

	_logo = TextureRect.new()
	_logo.texture = LOGO
	_logo.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_logo.size = LOGO.get_size()
	_logo.pivot_offset = _logo.size * 0.5
	add_child(_logo)
	var beat := _logo.create_tween().set_loops()
	beat.tween_property(_logo, ^"scale", Vector2.ONE * 0.95, LOGO_BEAT).from(Vector2.ONE) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	_panel = NinePatchRect.new()
	_panel.texture = PANEL_TEXTURE
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		_panel.set_patch_margin(side, 3)
	add_child(_panel)
	_back = _start_button(StartFrame.BACK, 16, false)
	_back.tooltip_text = "назад (Esc)"
	_back.pressed.connect(_go_back)

	_nick = LineEdit.new()
	_nick.placeholder_text = "ник"
	_nick.max_length = 12
	_nick.custom_minimum_size = Vector2(128, 0)
	_nick.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_nick.text_changed.connect(func(_text: String) -> void:
		_save_settings()
		_refresh_player())

	_pages[Page.MAIN] = _build_main_page()
	_pages[Page.MAPS] = _page_with_title("где покатаемся?", _build_maps_page())
	_garage = GaragePage.new()
	_garage.nick_field = _nick
	_garage.changed.connect(func(code: String) -> void:
		_skin = CarSkin.from_code(code)
		_save_settings()
		_refresh_player())
	_pages[Page.GARAGE] = _page_with_title("на чём поедем?", _garage)
	_pages[Page.FRIENDS] = _page_with_title("с друзьями", _build_friends_page())
	var settings := SettingsPanel.new()
	settings.add_theme_stylebox_override(&"panel", StyleBoxEmpty.new())
	settings.closed.connect(_go_back)
	_pages[Page.SETTINGS] = settings
	for page in _pages.values():
		(page as Control).visible = false
		add_child(page)
	# Стрелка «назад» — поверх страниц (на панели под ними клик доходил только в её угол);
	# место — у левого верхнего угла панели (_layout).
	add_child(_back)

	# Низ экрана: автор оригинала, состояние сети; сверху — версия ремейка и игрок.
	_author = _small_label("mace dev 2023")
	add_child(_author)
	var version := _small_label("ремейк %s" % ProjectSettings.get_setting("application/config/version", ""))
	version.modulate = Color(1.0, 1.0, 1.0, 0.6)
	version.position = Vector2(8, 6)
	add_child(version)
	_status_icon = TextureRect.new()
	_status_icon.texture = _status_frame(2)
	add_child(_status_icon)
	_status_text = _small_label("подключение...")
	_status_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_status_text)
	_player_face = TextureRect.new()
	_player_face.texture = FACE
	_player_face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_player_face.size = Vector2(16, 16)
	add_child(_player_face)
	_player_name = _small_label("")
	_player_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_player_name.add_theme_color_override(&"font_color", Color(0.0, 1.0, 0.2))
	add_child(_player_name)
	_status = _small_label("")
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_color_override(&"font_color", Color(1.0, 0.95, 0.6))
	_status.add_theme_color_override(&"font_outline_color", Color(0.0, 0.0, 0.0))
	_status.add_theme_constant_override(&"outline_size", 2)
	add_child(_status)

	_credits = _build_credits()
	_credits.visible = false
	add_child(_credits)

	# Белая вспышка при входе (слой MenuFade оригинала): через 0.2 с тает.
	_fade = ColorRect.new()
	_fade.color = Color.WHITE
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_fade)
	_fade.create_tween().tween_property(_fade, ^"modulate:a", 0.0, 0.6).set_delay(0.2)


## Главная страница: кресты на местах оригинала (относительно центра панели 168×72).
func _build_main_page() -> Control:
	var page := Control.new()
	page.custom_minimum_size = MAIN_PANEL - PANEL_PAD
	var center := page.custom_minimum_size * 0.5
	# Кресты — в родном размере картинок (48 и 32 px): уменьшенные до 24 рвались.
	var play := _start_button(StartFrame.PLAY, 48)
	play.tooltip_text = "играть"
	play.pressed.connect(_show_page.bind(Page.MAPS, true))
	_place(page, play, center + Vector2(0, -8))
	var garage := _start_button(StartFrame.SKIN, 32)
	garage.tooltip_text = "гараж"
	garage.pressed.connect(_show_page.bind(Page.GARAGE, true))
	_place(page, garage, center + Vector2(-68, -8))
	var credits := _start_button(StartFrame.CREDITS, 32)
	credits.tooltip_text = "титры"
	credits.pressed.connect(_open_credits)
	_place(page, credits, center + Vector2(68, -8))
	var friends := _start_button(StartFrame.FRIENDS, 32)
	friends.tooltip_text = "с друзьями: войти по ID"
	friends.pressed.connect(_show_page.bind(Page.FRIENDS, true))
	_place(page, friends, center + Vector2(-40, 22))
	var settings := _start_button(StartFrame.EMPTY, 32)
	settings.texture_normal = _gear_texture()
	settings.tooltip_text = "настройки"
	settings.pressed.connect(_show_page.bind(Page.SETTINGS, true))
	_place(page, settings, center + Vector2(40, 22))
	page.set_meta(&"focus", play)
	return page


func _build_maps_page() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 4)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override(&"h_separation", 16)
	grid.add_theme_constant_override(&"v_separation", 8)
	box.add_child(grid)
	_map_names = list_maps()
	# Проверка собранной игры: какие карты нашлись (в журнал).
	if OS.get_cmdline_user_args().has("--list-maps"):
		print("карты: ", ", ".join(_map_names))
	for map in _map_names + PackedStringArray([RANDOM_MAP]):
		var frame: int = THUMB_RANDOM if map == RANDOM_MAP else MAP_THUMBS.get(map, THUMB_OWN)
		var button := TextureButton.new()
		button.texture_normal = load("%smenuselectmap-%03d.png" % [MENU_TEXTURES, frame]) as Texture2D
		# Своя картинка карты (наши карты; у карт друзей — «абстракция» оригинала).
		if ResourceLoader.exists(OWN_THUMBS + map + ".png"):
			button.texture_normal = load(OWN_THUMBS + map + ".png") as Texture2D
		button.tooltip_text = "случайная карта" if map == RANDOM_MAP else _map_title(map)
		button.pressed.connect(_select_map.bind(map, true))
		MenuFx.juicy(button, false)
		grid.add_child(button)
		_map_buttons[map] = button
	_selected_label = _small_label("")
	_selected_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_selected_label)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", 8)
	box.add_child(row)
	row.add_child(_text_button("ОДИН", _on_single))
	var host := _text_button("С ДРУЗЬЯМИ", _on_host)
	host.disabled = not Network.is_available()
	host.tooltip_text = "создать игру: друзья войдут по ID"
	row.add_child(host)
	box.set_meta(&"focus", grid.get_child(0))
	return box


func _build_friends_page() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 3)
	box.custom_minimum_size = Vector2(216, 0)
	var join_row := HBoxContainer.new()
	box.add_child(join_row)
	_join_id = LineEdit.new()
	_join_id.placeholder_text = "ID игры"
	_join_id.max_length = 5
	_join_id.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_join_id.text_changed.connect(func(text: String) -> void:
		var caret := _join_id.caret_column
		_join_id.text = text.to_upper()
		_join_id.caret_column = caret)
	_join_id.text_submitted.connect(func(_text: String) -> void: _on_join())
	join_row.add_child(_join_id)
	var join := _text_button("ВОЙТИ", _on_join)
	join.disabled = not Network.is_available()
	join_row.add_child(join)
	box.add_child(_small_label("игры в локальной сети (вход в один клик):"))
	_games = VBoxContainer.new()
	box.add_child(_games)
	box.add_child(_small_label("создать игру: «играть», карта, «с друзьями»"))
	_check_button = _text_button("ПРОВЕРКА СЕТИ", _on_check_network)
	box.add_child(_check_button)
	_check_result = _small_label("")
	_check_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_check_result.custom_minimum_size = Vector2(216, 0)
	_check_result.visible = false
	box.add_child(_check_result)
	box.set_meta(&"focus", _join_id)
	return box


## Титры — отдельный экран, как Credits оригинала (тёмно-фиолетовый, стрелка назад).
func _build_credits() -> Control:
	var screen := ColorRect.new()
	screen.color = Color8(17, 8, 38)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_STOP
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	screen.add_child(scroll)
	screen.set_meta(&"scroll", scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override(&"separation", 1)
	scroll.add_child(box)
	var lines := [
		["", 4],
		["DYNAMIC FORCE", 12], ["игра от: mace dev 2023", 6], ["link", 6], ["", 4],
		["3DYNAMIC FORCE — ремейк в 3D", 12],
		["с одобрения автора оригинала; версия %s" % ProjectSettings.get_setting("application/config/version", ""), 6],
		["", 4], ["МУЗЫКА (из оригинала)", 12],
		["intro: spark the electric jester — remix by jx", 6],
		["хим. зона: ghost town (sonic forces) — remix by dv2", 6],
		["снежная: sylvania castle act 3 (sonic 4 ep2) — remix by jx", 6],
		["цирк: carnival night zone act 1 (sonic 3 beta) — mastered realm", 6],
		["пляж: dragon valley 1 (freedom planet) — remix by jx", 6],
		["стройка: sono chino sadame (jojo: ba) — remix by jx", 6],
		["шинозавод: oil desert zone act 2 (sonic 4 ep2) — just kam", 6],
		["аквапарк: jungle rush (sonic superstars) — daan demmers", 6],
		["", 4], ["СПРАЙТЫ", 12], ["все спрайты — mace dev", 6],
		["", 4], ["ЗВУКИ", 12], ["pizza tower, bfxr и что-то ещё", 6],
		["", 4], ["СОФТ", 12], ["оригинал: construct 3, paint.net, audacity", 6],
		["ремейк: godot 4.7, blender", 6],
		["", 4], ["чужие музыка и звуки — только для теста, не для продажи", 6],
	]
	for line in lines:
		if line[0] == "link":
			# Сайт автора оригинала — ссылка, открывается в браузере.
			var link := LinkButton.new()
			link.text = AUTHOR_SITE.trim_prefix("https://")
			link.uri = AUTHOR_SITE
			link.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			link.add_theme_font_size_override(&"font_size", 6)
			link.add_theme_color_override(&"font_color", Color(0.45, 0.8, 1.0))
			link.add_theme_color_override(&"font_hover_color", Color(0.75, 0.95, 1.0))
			box.add_child(link)
			continue
		var label := Label.new()
		label.text = line[0]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override(&"font_size", int(line[1]))
		if int(line[1]) == 12:
			label.add_theme_color_override(&"font_color", Color(1.0, 0.85, 0.3))
		box.add_child(label)
	var back := _start_button(StartFrame.BACK, 16, false)
	back.position = Vector2(8, 8)
	back.pressed.connect(_close_credits)
	screen.add_child(back)
	screen.set_meta(&"focus", back)
	return screen


# --------------------------------------------------------------------------
# Страницы
# --------------------------------------------------------------------------

func _show_page(page: Page, animate: bool = true) -> void:
	_page = page
	for key in _pages:
		(_pages[key] as Control).visible = key == page
	_back.visible = page != Page.MAIN
	var content := _pages[page] as Control
	var target := (content.get_combined_minimum_size() + PANEL_PAD).max(MAIN_PANEL)
	if page != Page.MAIN:
		target.y += 6.0
	var logo_y := LOGO_Y_MAIN if page == Page.MAIN else LOGO_Y_PAGE
	if _panel_tween != null:
		_panel_tween.kill()
	if animate:
		_panel_tween = create_tween().set_parallel()
		_panel_tween.tween_property(self, ^"_panel_size", target, PAGE_TIME) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_panel_tween.tween_property(self, ^"_logo_y", logo_y, PAGE_TIME * 1.5) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	else:
		_panel_size = target
		_logo_y = logo_y
	var focus: Control = null
	if page == Page.GARAGE:
		focus = _garage.first_button()
	elif content.has_meta(&"focus"):
		focus = content.get_meta(&"focus")
	if focus != null:
		_focus_later(focus)


## Фокус в конце кадра (страница уже на месте); меню могли закрыть — тогда ничего.
func _focus_later(control: Control) -> void:
	(func() -> void:
		if is_instance_valid(control) and control.is_inside_tree():
			control.grab_focus()).call_deferred()


func _go_back() -> void:
	MenuFx.cancel()
	_show_page(Page.MAIN)


func _open_credits() -> void:
	_credits.visible = true
	_credits_scroll = 0.0
	(_credits.get_meta(&"scroll") as ScrollContainer).scroll_vertical = 0
	_focus_later(_credits.get_meta(&"focus"))


func _close_credits() -> void:
	MenuFx.cancel()
	_credits.visible = false
	_focus_later(_pages[Page.MAIN].get_meta(&"focus"))


## Раскладка каждый кадр: экран может быть шире 384 (aspect expand), панель — по центру.
func _layout() -> void:
	var screen := get_viewport_rect().size
	_logo.position = (Vector2(screen.x * 0.5, _logo_y) - _logo.size * 0.5).round()
	# Панель — на месте оригинала (y = 132), но не под логотипом и не на нижних надписях.
	var top := _logo_y + _logo.size.y * 0.5 + PANEL_GAP_TOP + _panel_size.y * 0.5
	var bottom_limit := screen.y - PANEL_GAP_BOTTOM - _panel_size.y * 0.5
	var center := Vector2(screen.x * 0.5, clampf(PANEL_Y * screen.y / 216.0, top, maxf(bottom_limit, top)))
	_panel.size = _panel_size.round()
	_panel.position = (center - _panel.size * 0.5).round()
	# По высоте — вровень с заголовком страницы.
	_back.position = _panel.position + BACK_OFFSET
	for page in _pages.values():
		var control := page as Control
		if control.visible:
			control.size = control.get_combined_minimum_size()
			var offset := Vector2(0, 3) if control != _pages[Page.MAIN] else Vector2.ZERO
			control.position = (center - control.size * 0.5 + offset).round()
	var bottom := screen.y - 12.0
	_author.position = Vector2(8.0, bottom + 4.0)
	_status_icon.position = Vector2(screen.x - 20.0, bottom - 4.0)
	_status_text.size = Vector2(160, 8)
	_status_text.position = Vector2(screen.x - 184.0, bottom + 2.0)
	_player_face.position = Vector2(screen.x - 20.0, 4.0)
	_player_name.size = Vector2(160, 8)
	_player_name.position = Vector2(screen.x - 184.0, 8.0)
	_status.size = Vector2(minf(220.0, screen.x - 200.0), 0)
	_status.position = Vector2((screen.x - _status.size.x) * 0.5, bottom - 6.0)


# --------------------------------------------------------------------------
# Действия
# --------------------------------------------------------------------------

func _select_map(map: String, with_sound: bool) -> void:
	_selected_map_name = map
	for key in _map_buttons:
		var button: TextureButton = _map_buttons[key]
		button.modulate = Color.WHITE if key == map else Color(0.55, 0.55, 0.6)
	if with_sound:
		MenuFx.chosen()
	_selected_label.text = "случайная карта" if map == RANDOM_MAP else _map_title(map)


func _map_title(map: String) -> String:
	return map_title(map)


## Название карты для интерфейса (меню, лобби).
static func map_title(map: String) -> String:
	return String(MAP_TITLES.get(map, map))


## Карты папки трасс (без «_*.tscn» — служебных): сначала оригинала в его порядке, потом
## наши и свои по имени. В собранной игре сцены лежат как «map_a.tscn.remap».
static func list_maps() -> PackedStringArray:
	var names: Array = []
	for raw_file in DirAccess.get_files_at(TRACKS_DIR):
		var file := raw_file.trim_suffix(".remap")
		if file.ends_with(".tscn") and not file.begins_with("_") and not names.has(file.get_basename()):
			names.append(file.get_basename())
	names.sort_custom(func(a: String, b: String) -> bool:
		var order_a: int = MAP_THUMBS.get(a, 99)
		var order_b: int = MAP_THUMBS.get(b, 99)
		return order_a < order_b if order_a != order_b else a < b)
	return PackedStringArray(names)


func _refresh_games() -> void:
	for child in _games.get_children():
		child.queue_free()
	var net := Network.session()
	if net.found_games.is_empty():
		var none := _small_label("никого не видно")
		none.modulate = Color(1.0, 1.0, 1.0, 0.6)
		_games.add_child(none)
	else:
		for id in net.found_games:
			var info: Dictionary = net.found_games[id]
			var button := Button.new()
			button.text = "%s  %s  %d/%d" % [String(info.get("name", "?")),
					_map_title(String(info.get("map", ""))), int(info.get("players", 0)), int(info.get("max", 4))]
			button.disabled = not bool(info.get("open", true)) or not Network.is_available()
			button.pressed.connect(func() -> void: _join(String(id)))
			MenuFx.juicy(button)
			_games.add_child(button)
	if _page == Page.FRIENDS:
		_show_page.call_deferred(Page.FRIENDS, false)


func _nickname() -> String:
	var nick := _nick.text.strip_edges()
	return nick if nick != "" else "Игрок"


## Выбранная карта («?» — случайная из всех).
func _selected_map() -> String:
	if _selected_map_name == RANDOM_MAP:
		return _map_names[randi() % _map_names.size()] if not _map_names.is_empty() else "remake_01"
	return _selected_map_name if _map_names.has(_selected_map_name) else "remake_01"


func _on_single() -> void:
	var map := _selected_map()
	_save_settings()
	var net := Network.session()
	net.leave("")
	net.player_name = _nickname()
	net.map_name = map
	net.map_from_menu = true
	get_tree().change_scene_to_file(Network.RACE_SCENE)


func _on_host() -> void:
	var map := _selected_map()
	_save_settings()
	_toast("создаём игру…")
	if not Network.session().host_game(_nickname(), map):
		_toast("не удалось создать игру")


func _on_join() -> void:
	_join(_join_id.text)


func _join(id: String) -> void:
	_save_settings()
	if id.strip_edges().length() != 5:
		_toast("ID игры — 5 знаков")
		return
	_toast("входим в игру %s… (через интернет — до 30 с)" % id.to_upper(), 30.0)
	if not Network.session().join_game(id, _nickname()):
		_toast("не удалось войти")


func _on_check_network() -> void:
	_check_button.disabled = true
	_check_result.text = "проверяем (до 10 с)…"
	_check_result.visible = true
	_show_page(Page.FRIENDS, true)
	var check := NetCheck.new()
	add_child(check)
	check.finished.connect(func(lines: PackedStringArray) -> void:
		_check_result.text = "\n".join(lines)
		_check_button.disabled = false
		check.queue_free()
		if _page == Page.FRIENDS:
			_show_page(Page.FRIENDS, true))
	check.start(load(Network.CONTEXT_PATH) as TubeContext)


func _load_settings() -> void:
	var config := ConfigFile.new()
	var loaded := config.load(SETTINGS_PATH) == OK
	_nick.text = String(config.get_value("player", "name", "")) if loaded else ""
	var map := String(config.get_value("player", "map", "")) if loaded else ""
	if not _map_names.has(map) and map != RANDOM_MAP:
		map = _map_names[0] if not _map_names.is_empty() else ""
	_select_map(map, false)
	_skin = CarSkin.from_code(String(config.get_value("player", "skin", CarSkin.DEFAULT_CODE)) if loaded
			else CarSkin.DEFAULT_CODE)
	_garage.skin = CarSkin.from_code(_skin.to_code())
	_garage.refresh()
	Network.session().player_skin = _skin.to_code()


func _save_settings() -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("player", "name", _nickname())
	config.set_value("player", "map", _selected_map_name)
	config.set_value("player", "skin", _skin.to_code())
	config.save(SETTINGS_PATH)
	Network.session().player_skin = _skin.to_code()


## Ник и рожица цвета скина сверху справа (как иконка игрока в гонке).
func _refresh_player() -> void:
	_player_name.text = _nickname()
	_player_face.modulate = _skin.icon_color()


## Сообщение внизу по центру (как «нет сети!» оригинала): показывается и тает.
func _toast(text: String, seconds: float = 5.0) -> void:
	_status.text = text
	_status.modulate.a = 1.0
	if _toast_tween != null:
		_toast_tween.kill()
	if text == "":
		return
	_toast_tween = create_tween()
	_toast_tween.tween_property(_status, ^"modulate:a", 0.0, 0.8).set_delay(seconds)


# --------------------------------------------------------------------------
# Состояние сети: отвечают ли трекеры (через них друзья входят по ID)
# --------------------------------------------------------------------------

func _start_probe() -> void:
	if not Network.is_available():
		_set_status(1, "нет webrtc")
		return
	var context := load(Network.CONTEXT_PATH) as TubeContext
	for url in context.trackers_urls:
		var socket := WebSocketPeer.new()
		if socket.connect_to_url(url) == OK:
			_probes.append(socket)
	_probe_time = 0.0
	_set_status(2, "подключение...")


func _poll_probe(delta: float) -> void:
	if _probes.is_empty():
		return
	_probe_time += delta
	var open := false
	var waiting := false
	for socket in _probes:
		socket.poll()
		match socket.get_ready_state():
			WebSocketPeer.STATE_OPEN:
				open = true
			WebSocketPeer.STATE_CONNECTING:
				waiting = true
	if open:
		_set_status(3, "подключено")
	elif not waiting or _probe_time > 8.0:
		_set_status(1, "только локальная сеть")
	else:
		return
	for socket in _probes:
		socket.close()
	_probes.clear()


func _set_status(frame: int, text: String) -> void:
	_status_icon.texture = _status_frame(frame)
	_status_text.text = text


func _status_frame(frame: int) -> Texture2D:
	return load("%smenuconnectionstatus-%03d.png" % [MENU_TEXTURES, frame]) as Texture2D


# --------------------------------------------------------------------------
# Помощники
# --------------------------------------------------------------------------

## Кнопка-крест оригинала (кадр menustartbutton) размером side×side.
func _start_button(frame: int, side: int, with_click: bool = true) -> TextureButton:
	var button := TextureButton.new()
	button.texture_normal = load("%smenustartbutton-%03d.png" % [MENU_TEXTURES, frame]) as Texture2D
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_SCALE
	# Нажимается только видимый крест: прозрачные углы квадрата соседних крестов отбирали клики.
	button.texture_click_mask = _alpha_mask(button.texture_normal)
	button.size = Vector2(side, side)
	button.custom_minimum_size = Vector2(side, side)
	MenuFx.juicy(button, with_click)
	return button


## Маска нажатия по непрозрачным пикселям картинки.
static func _alpha_mask(texture: Texture2D) -> BitMap:
	var mask := BitMap.new()
	var image := texture.get_image()
	if image.is_compressed():
		image.decompress()
	mask.create_from_image_alpha(image, 0.5)
	return mask


func _place(page: Control, button: Control, center: Vector2) -> void:
	page.add_child(button)
	button.position = (center - button.custom_minimum_size * 0.5).round()


func _text_button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	MenuFx.juicy(button)
	return button


func _small_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## Страница с заголовком (как Text оригинала над содержимым).
func _page_with_title(title: String, content: Control) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 4)
	var label := Label.new()
	label.text = title
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(label)
	box.add_child(content)
	if content.has_meta(&"focus"):
		box.set_meta(&"focus", content.get_meta(&"focus"))
	return box


## Шестерёнка (GEAR) поверх пустого креста оригинала — кнопка настроек.
func _gear_texture() -> Texture2D:
	var cross := (load("%smenustartbutton-%03d.png" % [MENU_TEXTURES, StartFrame.EMPTY]) as Texture2D).get_image()
	if cross.is_compressed():
		cross.decompress()
	cross.convert(Image.FORMAT_RGBA8)
	var colors := {"Y": Color8(255, 222, 0), "O": Color8(255, 140, 20), "K": Color8(60, 0, 20)}
	var first_row: String = GEAR[0]
	var top := Vector2i(floori((cross.get_width() - first_row.length()) / 2.0),
			floori((cross.get_height() - GEAR.size()) / 2.0))
	for y in GEAR.size():
		var row: String = GEAR[y]
		for x in row.length():
			if colors.has(row[x]):
				cross.set_pixelv(top + Vector2i(x, y), colors[row[x]])
	return ImageTexture.create_from_image(cross)
