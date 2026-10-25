class_name Race
extends Node3D
## Сцена гонки: трасса, участники, обратный отсчёт, камера и HUD.
##
## Ботов в игре нет (LAN-мультиплеер). Одиночная игра — один локальный игрок
## (autostart). Сетевая (Network.session().is_online()): машины всех игроков сессии по их местам на
## решётке, своя — с клавиатуры, чужие — «марионетки» с NetCarSync; сначала лобби прямо
## на карте (как в оригинале: катаемся у старта, машину притягивает в радиус
## LOBBY_RADIUS), хост жмёт «Начать» — все на решётку, отсчёт. Круги, места и финиш
## в сети считает хост (RaceManager.authority). После финиша машина — «призрак».

const MAX_RACERS := 4
## Папка трасс: аргумент запуска `-- --map=<имя>` грузит res://scenes/tracks/<имя>.tscn.
const TRACKS_DIR := "res://scenes/tracks/"
## Файл, через который редактор карт передаёт карту для пробного заезда.
const EDITOR_TEST_MAP_FILE := "user://editor_test_map.txt"
## Группа маркеров мест коробок предметов на трассе.
const ITEM_BOX_GROUP := &"item_box_spots"
## Лобби на карте: машину притягивает к старту, если она дальше, м (96 px в оригинале),
## и с какой силой (м/с толчка на метр сверх радиуса).
const LOBBY_RADIUS := 12.0
## Музыка карты — через столько секунд после старта (как в оригинале).
const MUSIC_DELAY := 0.4
const LOBBY_PULL := 3.0

## Трасса гонки (меню выбора карты — этап 7).
@export var track_scene: PackedScene
@export var car_scene: PackedScene
## Коробка предметов: ставится на каждый маркер группы item_box_spots трассы.
@export var item_box_scene: PackedScene
@export_range(1, 99) var laps: int = 5
@export var player_name: String = "Игрок"
## Сразу добавить локального игрока и начать отсчёт. Выключают тесты и (позже) лобби,
## чтобы сначала добавить всех участников, а потом вызвать begin().
@export var autostart: bool = true

var player_racer: RacerState
var track: Track
## Коробки предметов на трассе.
var item_boxes: Array[ItemBox] = []
## Сеть: участники по peer id.
var _net_racers: Dictionary = {}
var _pause: PauseMenu
var _finish_music: bool = false

@onready var race_manager: RaceManager = $RaceManager
@onready var player_input: PlayerInputSource = $PlayerInput
@onready var _cars: Node3D = $Cars
@onready var _camera: TopDownCamera = $TopDownCamera
@onready var _hud: RaceHud = $RaceHud
## Сеть: звуки входа и выхода игрока (выход — CardCollect, как в оригинале).
const JOIN_SOUND := preload("res://assets/original/sounds/checkpoint.wav")
const LEAVE_SOUND := preload("res://assets/original/sounds/cardcollect.wav")
## Сообщать о входе/выходе игроков (после первых машин лобби).
var _announce_players: bool = false
@onready var _screen_effects: ScreenEffects = $ScreenEffects
@onready var _touch: TouchControls = $TouchControls


func _ready() -> void:
	_load_track()
	race_manager.track = track
	race_manager.laps = laps
	race_manager.racer_finished.connect(_on_racer_finished)
	race_manager.racer_finished.connect(_on_first_finish)
	race_manager.countdown_tick.connect(_on_countdown_tick)
	race_manager.race_started.connect(_on_race_started)
	_pause = PauseMenu.new()
	_pause.name = "PauseMenu"
	add_child(_pause)
	_touch.visibility_changed.connect(_update_hud_inset)
	_update_hud_inset()
	if Network.session().is_online():
		_setup_online()
	elif autostart:
		# Заезд из меню — со своим ником и скином (гараж); иначе (тест, F6) — скин по месту.
		var net := Network.session()
		if net.map_from_menu:
			spawn_racer(net.player_name, true, player_input, -1, CarSkin.from_code(net.player_skin))
		else:
			spawn_racer(player_name, true, player_input)
		begin()


func _physics_process(_delta: float) -> void:
	# Лобби на карте: своя машина далеко от старта — тянем обратно.
	if not Network.session().is_online() or player_racer == null or race_manager.state != RaceManager.State.WAITING:
		return
	var car := player_racer.car
	var to_start := track.get_point_at(0.0) - car.global_position
	to_start.y = 0.0
	var beyond := to_start.length() - LOBBY_RADIUS
	if beyond > 0.0:
		car.add_push(to_start.normalized() * beyond * LOBBY_PULL)


func _unhandled_input(event: InputEvent) -> void:
	if Network.session().is_host() and race_manager.state == RaceManager.State.WAITING \
			and event.is_action_pressed(&"ui_accept") and not _pause.is_open():
		start_requested()


# --------------------------------------------------------------------------
# Музыка (как в оригинале): лобби — LobbyForce; отсчёт — тишина; через 0.4 с после
# старта — музыка карты; первый финишировал — EbucheeMoloko.
# --------------------------------------------------------------------------

func _on_countdown_tick(seconds_left: int) -> void:
	if seconds_left == race_manager.countdown_seconds:
		GameMusic.player().stop()


func _on_race_started() -> void:
	get_tree().create_timer(MUSIC_DELAY, false).timeout.connect(func() -> void:
		if race_manager.state == RaceManager.State.RACING and not _finish_music:
			GameMusic.player().play(track.music))


func _on_first_finish(racer: RacerState) -> void:
	if racer.finish_place == 1 and not _finish_music:
		_finish_music = true
		GameMusic.player().play_finish()


# --------------------------------------------------------------------------
# Сеть
# --------------------------------------------------------------------------

func _setup_online() -> void:
	Network.session().race = self
	race_manager.authority = Network.session().is_host()
	for id in Network.session().get_player_ids():
		add_net_player(id)
	# Дальше о каждом пришедшем и ушедшем — уведомление (просьба автора оригинала).
	_announce_players = true
	if player_racer != null:
		_attach_view()
		player_racer.car.controls_enabled = true
	_hud.show_lobby(Network.session().is_host())
	GameMusic.player().play_lobby()


## Хост: «Начать» (кнопка в HUD или Enter).
func start_requested() -> void:
	Network.session().request_start(laps)


## Добавить машину игрока сессии (своя — с клавиатуры, чужая — марионетка).
func add_net_player(peer_id: int) -> void:
	if _net_racers.has(peer_id) or not Network.session().players.has(peer_id):
		return
	var info: Dictionary = Network.session().players[peer_id]
	var is_local := peer_id == Network.session().my_id()
	var racer := spawn_racer(String(info["name"]), is_local, player_input if is_local else null, int(info["slot"]),
			CarSkin.from_code(String(info.get("skin", CarSkin.PRESETS[int(info["slot"]) % CarSkin.PRESETS.size()]))))
	if racer == null:
		return
	racer.peer_id = peer_id
	racer.car.set_meta(ItemObject.NET_PEER_META, peer_id)
	if is_local:
		Network.session().set_local_car(racer.car)
		if race_manager.state == RaceManager.State.WAITING:
			racer.car.controls_enabled = true
	else:
		racer.car.is_puppet = true
		var sync := NetCarSync.new()
		sync.name = "NetSync"
		racer.car.add_child(sync)
	_net_racers[peer_id] = racer
	_hud.racer_added(racer)
	if _announce_players and not is_local:
		_hud.notify("%s вошёл в лобби" % racer.display_name, Color(0.4, 1.0, 0.5), JOIN_SOUND)
	_update_camera_opponents()


## Игрок ушёл: убрать его машину.
func remove_net_player(peer_id: int) -> void:
	var racer: RacerState = _net_racers.get(peer_id)
	if racer == null:
		return
	_net_racers.erase(peer_id)
	race_manager.remove_racer(racer)
	_hud.racer_removed(racer)
	var where := "из лобби" if race_manager.state == RaceManager.State.WAITING else "из игры"
	_hud.notify("%s вышел %s" % [racer.display_name, where], Color(1.0, 0.55, 0.45), LEAVE_SOUND)
	racer.car.queue_free()
	_update_camera_opponents()


func get_net_racer(peer_id: int) -> RacerState:
	return _net_racers.get(peer_id)


func get_net_car(peer_id: int) -> CarController:
	var racer: RacerState = _net_racers.get(peer_id)
	return racer.car if racer != null else null


## Сеть: хост начал гонку — своя машина на своё место решётки, отсчёт.
func start_net_race(race_laps: int) -> void:
	laps = race_laps
	race_manager.laps = race_laps
	if player_racer != null:
		var info: Dictionary = Network.session().players.get(Network.session().my_id(), {"slot": 0})
		var spawn := track.get_grid_transform(int(info["slot"]))
		player_racer.car.teleport(spawn)
		player_racer.car.set_spawn_transform(spawn)
		player_racer.progress.reset()
		player_racer.progress.update(spawn.origin)
	_hud.hide_lobby()
	race_manager.start_countdown()


func _update_camera_opponents() -> void:
	var opponents: Array[Node3D] = []
	for racer in race_manager.racers:
		if racer != player_racer:
			opponents.append(racer.car)
	_camera.opponents = opponents


## Трасса: из редактора карт (кнопка «Запустить гонку»), из аргумента запуска
## --map=<имя>, иначе track_scene.
func _load_track() -> void:
	var scene := track_scene
	# Карта из меню / сетевой сессии.
	if Network.session().is_online() or Network.session().map_from_menu:
		var menu_path := TRACKS_DIR + Network.session().map_name + ".tscn"
		if ResourceLoader.exists(menu_path):
			scene = load(menu_path) as PackedScene
	# Редактор карт оставляет путь карты в файле; читаем один раз (только отладочная сборка).
	if OS.is_debug_build() and FileAccess.file_exists(EDITOR_TEST_MAP_FILE):
		var path := FileAccess.get_file_as_string(EDITOR_TEST_MAP_FILE).strip_edges()
		DirAccess.remove_absolute(EDITOR_TEST_MAP_FILE)
		if ResourceLoader.exists(path):
			scene = load(path) as PackedScene
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):
			var path := TRACKS_DIR + arg.trim_prefix("--map=") + ".tscn"
			if ResourceLoader.exists(path):
				scene = load(path) as PackedScene
			else:
				push_warning("Race: нет трассы %s, беру %s" % [path, track_scene.resource_path])
	track = scene.instantiate() as Track
	track.name = "Track"
	add_child(track)
	move_child(track, 0)
	_apply_atmosphere()
	_spawn_item_boxes()


## Дымка вдали и небо за краем карты — цвета карты (Track.haze_color).
func _apply_atmosphere() -> void:
	var world := get_node_or_null(^"WorldEnvironment") as WorldEnvironment
	if world == null or world.environment == null:
		return
	var environment := world.environment.duplicate() as Environment
	environment.fog_light_color = track.haze_color
	environment.background_color = track.haze_color
	world.environment = environment


## Коробки предметов — на маркеры трассы (группа item_box_spots, ItemBox оригинала).
func _spawn_item_boxes() -> void:
	if item_box_scene == null:
		return
	var holder := Node3D.new()
	holder.name = "ItemBoxes"
	add_child(holder)
	for marker in track.find_children("*", "Marker3D", true, false):
		if not marker.is_in_group(ITEM_BOX_GROUP):
			continue
		var box := item_box_scene.instantiate() as ItemBox
		box.name = "ItemBox%d" % (item_boxes.size() + 1)
		holder.add_child(box)
		box.global_position = (marker as Node3D).global_position
		box.index = item_boxes.size()
		box.race_manager = race_manager
		item_boxes.append(box)


## Поставить машину участника на место стартовой решётки slot (-1 — на следующее).
## is_local_player — за ним следят камера и HUD. skin — скин машины (CarSkin; нет — скин
## по месту: красная, синяя, зелёная, жёлтая). Возвращает состояние участника.
func spawn_racer(display_name: String, is_local_player: bool, input_source: CarInputSource,
		slot: int = -1, skin: CarSkin = null) -> RacerState:
	var index := slot if slot >= 0 else race_manager.racers.size()
	if race_manager.racers.size() >= MAX_RACERS:
		push_error("Race: не больше %d участников." % MAX_RACERS)
		return null
	var car := car_scene.instantiate() as CarController
	car.name = "Car%d" % index
	if skin == null:
		skin = CarSkin.preset(index)
	(car.get_node("Visual") as CarVisual).skin = skin
	_cars.add_child(car)
	var spawn := track.get_grid_transform(index)
	car.teleport(spawn)
	car.set_spawn_transform(spawn)
	# Упал с трассы — ниже её самой низкой точки (а не нуля мира: дорога может уходить вниз).
	car.kill_height = track.fall_height()
	car.input_source = input_source
	var racer := race_manager.add_racer(car, display_name, is_local_player)
	racer.color = skin.icon_color()
	racer.skin = skin
	if is_local_player:
		player_racer = racer
	return racer


## Все участники на месте: подключить камеру и HUD, начать обратный отсчёт.
func begin() -> void:
	if player_racer == null and not race_manager.racers.is_empty():
		player_racer = race_manager.racers[0]
	if player_racer != null:
		_attach_view()
	race_manager.start_countdown()


## Камера, HUD и эффекты экрана — за своим участником.
func _attach_view() -> void:
	# Свои объекты предметов игрок видит «своими», вспышка и «пьяный» экран — для него.
	player_racer.car.add_to_group(ItemObject.LOCAL_PLAYER_GROUP)
	_screen_effects.viewer = player_racer.car
	_camera.target = player_racer.car
	_camera.snap_to_target()
	_hud.setup(race_manager, player_racer)
	_update_camera_opponents()


func _update_hud_inset() -> void:
	_hud.set_bottom_inset(TouchControls.BOTTOM_INSET if _touch.visible else 0.0)
	_hud.set_key_hints_visible(not _touch.visible)


func _on_racer_finished(racer: RacerState) -> void:
	racer.car.set_ghost(true)
