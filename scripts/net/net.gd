class_name Network
extends Node
## Сетевая игра (этап 6) на аддоне Tube (addons/tube, WebRTC; на ПК и Android — с
## GDExtension webrtc-native). Автозагрузка «Net»; из кода — Network.session().
## Хост тоже играет, 2–4 игрока. Хост создаёт сессию и получает её ID (5 знаков),
## остальные входят по ID:
##   * в локальной сети — без интернета (локальная сигнализация Tube, широковещание);
##     вдобавок хост рассылает ID по сети (_broadcaster), и в меню игра видна списком;
##   * через интернет — без VPN: соединение напрямую (P2P), найти друг друга помогают
##     публичные трекеры WebTorrent и STUN-серверы (scenes/net/tube_context.tres).
##     Не соединится, если у обоих игроков «строгий» роутер (symmetric NAT) и не помог
##     UPnP — для этого нужен свой TURN-сервер (в контекст, turn_servers).
## Сверху Tube — обычный высокоуровневый мультиплеер Godot (RPC, хост пересылает):
##
## Плавность (главное требование автора ремейка):
##   * своей машиной каждый управляет сам, без задержки руля и парирования; её состояние
##     уходит остальным ненадёжно ~30 раз в секунду (стоя — 10) — _car_state;
##   * чужие машины — «марионетки» (CarController.is_puppet) с NetCarSync: буфер 100 мс,
##     интерполяция, экстраполяция при потере пакетов, мягкая подтяжка;
##   * время гонки и места приходят от хоста 10 раз в секунду, время подтягивается плавно.
## Стабильность:
##   * хост — единственный источник правды по гонке: круги, чекпоинты, места, финиш
##     (_race_state), коробки предметов (_request_box -> _box_taken), попадания предметов
##     (пострадавший сообщает _report_hit, хост проверяет и подтверждает _hit_confirmed —
##     исход парирования берётся из окна пострадавшего, как требует ТЗ);
##   * события — надёжные RPC; проверка версии протокола при входе; отключение игрока
##     посреди гонки убирает его машину; уход хоста возвращает всех в меню.
## В оригинале попадания проверял пострадавший, а позиции слал каждый сам (24 Гц) —
## позиции так и остались, попадания — по ТЗ через хост.

signal players_changed
signal games_changed
## Сессия кончилась (отключились / не пустили): причина для меню.
signal session_ended(reason: String)
## Изменилась доступность игры через интернет (у хоста: трекеры подключились / нет).
signal online_status_changed

const PROTOCOL_VERSION := 7
const MAX_PLAYERS := 4
## Настройки Tube: App ID, трекеры, STUN (грузится при запуске, не preload: иначе редактор
## держит ресурс до выхода).
const CONTEXT_PATH := "res://scenes/net/tube_context.tres"
## Сколько ждать прямого соединения с игроком (попытка, с) и сколько попыток: у Tube по
## умолчанию 2 с × 3 — через интернет (трекеры, STUN, пробивка NAT) этого мало, вход
## обрывался «не удалось войти». Всего — до 30 с.
const SIGNALING_TIMEOUT := 5.0
const SIGNALING_ATTEMPTS := 6
## Рассылка ID сессии по локальной сети (чтобы игра была видна в меню списком).
const DISCOVERY_PORT := 47801
const DISCOVERY_INTERVAL := 1.0
## Игра пропадает из списка, если о ней молчат дольше, с.
const DISCOVERY_TIMEOUT := 3.5
const DISCOVERY_TAG := "3DynamicForce"
## Частота отправки своей машины: в движении и стоя, Гц (в оригинале 24 и 4).
const CAR_SEND_RATE := 30.0
const CAR_IDLE_SEND_RATE := 10.0
## Частота рассылки состояния гонки хостом, Гц.
const RACE_SEND_RATE := 10.0
## Сколько первых пакетов после телепорта помечать «не сглаживать».
const TELEPORT_PACKETS := 3
const RACE_SCENE := "res://scenes/race/race.tscn"
const MENU_SCENE := "res://scenes/net/lobby_menu.tscn"

## Доступность игры через интернет у хоста.
enum OnlineStatus { OFF, CONNECTING, AVAILABLE, UNAVAILABLE }

static var _instance: Network

## Игроки сессии: peer id -> {"name": String, "slot": int (место на решётке и цвет)}.
var players: Dictionary = {}
## Карта сессии (имя файла в scenes/tracks без .tscn).
var map_name: String = "remake_01"
## Ник этого игрока.
var player_name: String = "Игрок"
## Скин машины этого игрока (строка CarSkin, ставит меню из гаража).
var player_skin: String = CarSkin.DEFAULT_CODE
## ID сессии (5 знаков; его хост сообщает друзьям).
var session_id: String = ""
## Через интернет (трекеры) или только локальная сеть. Тесты выключают.
var use_internet: bool = true
## Доступность через интернет (для лобби хоста).
var online_status: OnlineStatus = OnlineStatus.OFF
## Найденные в локальной сети игры: ID сессии -> {"name", "map", "players", "max", "open", "seen"}.
var found_games: Dictionary = {}
## Сцена гонки сессии (её задаёт Race).
var race: Race
## Причина последнего конца сессии (для меню после смены сцены).
var last_end_reason: String = ""
## Гонка уже стартовала — новых не пускаем (хост).
var race_started: bool = false
## Одиночная игра из меню: гонка берёт карту map_name и ник player_name.
var map_from_menu: bool = false

var _tube: TubeClient
var _leaving: bool = false
var _broadcaster: PacketPeerUDP
var _listener: PacketPeerUDP
var _discovery_left: float = 0.0
var _send_left: float = 0.0
var _race_send_left: float = 0.0
var _teleport_packets: int = 0
var _local_car: CarController
## Объекты предметов на трассе по id (для бомбы, попаданий): id -> ItemObject.
var _objects: Dictionary = {}


## Сеть игры: автозагрузка «Net». В автотестах (godot -s) автозагрузок нет — тогда
## узел создаётся здесь (появится в дереве в конце кадра; до сессии он не нужен).
static func session() -> Network:
	if is_instance_valid(_instance):
		return _instance
	var tree := Engine.get_main_loop() as SceneTree
	_instance = tree.root.get_node_or_null(^"Net") as Network
	if _instance == null:
		_instance = Network.new()
		_instance.name = "Net"
		tree.root.add_child.call_deferred(_instance)
	return _instance


func _ready() -> void:
	_instance = self
	# Громкость и экран из сохранённых настроек — при запуске игры.
	GameSettings.apply()
	_tube = TubeClient.new()
	_tube.name = "Tube"
	_tube.context = _load_context()
	_tube.peer_signaling_timeout = SIGNALING_TIMEOUT
	_tube.peer_signaling_max_attempts = SIGNALING_ATTEMPTS
	add_child(_tube)
	_tube.peer_connected.connect(_on_peer_connected)
	_tube.peer_disconnected.connect(_on_peer_disconnected)
	_tube.session_created.connect(_on_session_created)
	_tube.session_joined.connect(_on_session_joined)
	_tube.session_left.connect(_on_session_left)
	_tube.error_raised.connect(_on_tube_error)


# --------------------------------------------------------------------------
# Сессия
# --------------------------------------------------------------------------

## Есть открытая сессия (хост создал или клиент вошёл).
func is_online() -> bool:
	if _tube == null:
		return false
	if _tube.is_server:
		return _tube.state in [TubeClient.State.CREATING_SESSION, TubeClient.State.SESSION_CREATED]
	return _tube.state == TubeClient.State.SESSION_JOINED


func is_host() -> bool:
	return is_online() and _tube.is_server


## Свой peer id (1 — хост и одиночная игра).
func my_id() -> int:
	return _tube.peer_id if is_online() else 1


## Сетевая игра на этой платформе возможна (есть WebRTC).
static func is_available() -> bool:
	return TubeClient.is_webrtc_available()


## Создать игру: сессия Tube (ID сразу известен), своя машина, рассылка ID по локальной сети.
## Через интернет игра станет доступна, когда подключатся трекеры (online_status).
## Tube без интернета не шлёт session_created, хотя по локальной сети войти можно, —
## поэтому гонка грузится сразу, не дожидаясь его.
func host_game(nickname: String, map: String) -> bool:
	leave("")
	player_name = nickname
	map_name = map
	_tube.context = _context()
	_tube.create_session()
	if _tube.state == TubeClient.State.IDLE:
		return false
	session_id = _tube.session_id
	race_started = false
	players = {1: {"name": nickname, "slot": 0, "skin": player_skin}}
	if not use_internet:
		_set_online_status(OnlineStatus.OFF)
	elif _tube.state == TubeClient.State.SESSION_CREATED:
		_set_online_status(OnlineStatus.AVAILABLE)
	else:
		_set_online_status(OnlineStatus.CONNECTING)
	_start_broadcast()
	_load_scene(RACE_SCENE)
	return true


## Войти в игру по ID сессии. Гонка загрузится, когда хост пустит (_welcome).
func join_game(id: String, nickname: String) -> bool:
	leave("")
	player_name = nickname
	_tube.context = _context()
	_tube.join_session(id.strip_edges().to_upper())
	return _tube.state != TubeClient.State.IDLE


## Выйти из сессии (в меню — leave_to_menu).
func leave(reason: String) -> void:
	_stop_broadcast()
	if _tube != null and _tube.state != TubeClient.State.IDLE:
		_leaving = true
		_tube.leave_session()
		_leaving = false
	players.clear()
	_objects.clear()
	race = null
	_local_car = null
	race_started = false
	session_id = ""
	_set_online_status(OnlineStatus.OFF)
	if reason != "":
		last_end_reason = reason
		session_ended.emit(reason)


## Выйти и вернуться в меню.
func leave_to_menu(reason: String = "") -> void:
	leave(reason)
	_load_scene(MENU_SCENE)


## Игроки по местам на решётке.
func get_player_ids() -> Array[int]:
	var ids: Array[int] = []
	for id in players:
		ids.append(int(id))
	ids.sort_custom(func(a: int, b: int) -> bool: return int(players[a]["slot"]) < int(players[b]["slot"]))
	return ids


## Своя машина гонки (её состояние уходит остальным).
func set_local_car(car: CarController) -> void:
	_local_car = car
	if car != null:
		car.respawned.connect(func() -> void: _teleport_packets = TELEPORT_PACKETS)
		car.warped.connect(func() -> void: _teleport_packets = TELEPORT_PACKETS)
		car.emote_requested.connect(_on_local_emote)
		_teleport_packets = TELEPORT_PACKETS


## Контекст Tube: с интернетом (трекеры) или только локальная сеть.
func _context() -> TubeContext:
	if use_internet:
		return _load_context()
	var local := _load_context().duplicate() as TubeContext
	local.set(&"_generate_app_id_tool_button", Callable())
	local.trackers_urls = []
	local.stun_servers_urls = []
	return local


func _set_online_status(status: OnlineStatus) -> void:
	if online_status != status:
		online_status = status
		online_status_changed.emit()


func _load_scene(path: String) -> void:
	get_tree().change_scene_to_file.call_deferred(path)


func _on_session_created() -> void:
	if use_internet:
		_set_online_status(OnlineStatus.AVAILABLE)


func _on_session_joined() -> void:
	# Ник и скин одной строкой «ник;скин» (как alias оригинала «ник;;скин»): старые версии
	# с другим числом аргументов всё равно получат «разные версии игры».
	rpc_id(1, &"_hello", PROTOCOL_VERSION, "%s;%s" % [player_name.replace(";", ""), player_skin])


func _on_session_left() -> void:
	if _leaving:
		return
	leave_to_menu("Хост закрыл игру" if not _tube.is_server else "Игра закрыта")


func _on_tube_error(code: int, message: String) -> void:
	match code:
		TubeClient.SessionError.JOIN_SESSION_FAILED:
			push_warning("Tube: %s" % message)
			leave_to_menu(_join_error_text(message))
		TubeClient.SessionError.CREATE_SESSION_FAILED:
			leave_to_menu("Не удалось создать игру")
		TubeClient.SessionError.ONLINE_SIGNALING_FAILED:
			# Нет интернета или трекеров: играть можно только в локальной сети.
			_set_online_status(OnlineStatus.UNAVAILABLE)
		_:
			push_warning("Tube: %s" % message)


## Причина неудачного входа понятными словами (по сообщению Tube).
static func _join_error_text(message: String) -> String:
	if message.contains("any tracker"):
		return "Не удалось войти: трекеры не отвечают. Проверь интернет и файрвол или нажми «ПРОВЕРКА СЕТИ»"
	if message.contains("max connection attempts"):
		return "Не удалось войти: игра с таким ID не ответила за 30 с. Проверь ID. Если он верный, соединение не пропустили роутеры: пусть оба нажмут «ПРОВЕРКА СЕТИ»"
	if message.contains("connection failed"):
		return "Не удалось войти: прямое соединение не прошло. Возможно, у обоих строгий NAT, пусть оба нажмут «ПРОВЕРКА СЕТИ»"
	if message.contains("session id invalid"):
		return "Не удалось войти: неверный ID игры"
	return "Не удалось войти: %s" % message


func _on_peer_connected(_id: int) -> void:
	# Клиент сначала представится (_hello); до этого он не игрок.
	pass


func _on_peer_disconnected(id: int) -> void:
	if not players.has(id):
		return
	players.erase(id)
	if is_host():
		rpc(&"_players", players)
	players_changed.emit()
	if race != null:
		race.remove_net_player(id)


## Клиент -> хост: «я такой-то (ник;скин), версия протокола такая-то».
@rpc("any_peer", "call_remote", "reliable")
func _hello(version: int, nickname: String) -> void:
	if not is_host():
		return
	var sender := multiplayer.get_remote_sender_id()
	var reason := ""
	if version != PROTOCOL_VERSION:
		reason = "Разные версии игры (у хоста %d, у тебя %d)" % [PROTOCOL_VERSION, version]
	elif players.size() >= MAX_PLAYERS:
		reason = "Игра заполнена (%d из %d)" % [players.size(), MAX_PLAYERS]
	elif race_started:
		reason = "Гонка уже идёт, зайди, когда все вернутся в лобби"
	if reason != "":
		rpc_id(sender, &"_rejected", reason)
		get_tree().create_timer(0.5).timeout.connect(func() -> void:
			if is_host():
				_tube.kick_peer(sender))
		return
	players[sender] = {"name": nickname.get_slice(";", 0).substr(0, 16), "slot": _free_slot(),
			"skin": CarSkin.from_code(nickname.get_slice(";", 1)).to_code()}
	rpc_id(sender, &"_welcome", map_name, players)
	rpc(&"_players", players)
	players_changed.emit()
	if race != null:
		race.add_net_player(sender)


func _free_slot() -> int:
	var used := []
	for id in players:
		used.append(int(players[id]["slot"]))
	for slot in MAX_PLAYERS:
		if not slot in used:
			return slot
	return MAX_PLAYERS - 1


## Хост -> новый клиент: пустили, вот карта и игроки.
@rpc("authority", "call_remote", "reliable")
func _welcome(map: String, all_players: Dictionary) -> void:
	if not ResourceLoader.exists(Race.TRACKS_DIR + map + ".tscn"):
		leave_to_menu("У тебя нет карты «%s», попроси её у хоста" % map)
		return
	map_name = map
	players = all_players
	race_started = false
	players_changed.emit()
	_load_scene(RACE_SCENE)


## Хост -> клиент: не пустили.
@rpc("authority", "call_remote", "reliable")
func _rejected(reason: String) -> void:
	leave_to_menu(reason)


## Хост -> все: список игроков изменился.
@rpc("authority", "call_remote", "reliable")
func _players(all_players: Dictionary) -> void:
	var before := players.keys()
	players = all_players
	players_changed.emit()
	if race == null:
		return
	for id in players:
		if not id in before:
			race.add_net_player(int(id))
	for id in before:
		if not players.has(id):
			race.remove_net_player(int(id))


# --------------------------------------------------------------------------
# Гонка
# --------------------------------------------------------------------------

## Хост: «начать» — всех на решётку, отсчёт.
func request_start(laps: int) -> void:
	if not is_host() or race_started:
		return
	race_started = true
	_stop_broadcast()
	rpc(&"_start_race", laps)


@rpc("authority", "call_local", "reliable")
func _start_race(laps: int) -> void:
	race_started = true
	if race != null:
		race.start_net_race(laps)


## Хост: сменить карту в лобби — сессия и ID те же, все перезагружают лобби на новой карте
## («комната»: раньше ради другой карты приходилось создавать игру заново и слать новый ID).
func request_map(map: String) -> void:
	if not is_host() or race_started or map == map_name:
		return
	if not ResourceLoader.exists(Race.TRACKS_DIR + map + ".tscn"):
		return
	rpc(&"_change_map", map)


@rpc("authority", "call_local", "reliable")
func _change_map(map: String) -> void:
	# У клиента такой карты может не быть (своя карта хоста) — выходим с понятной причиной.
	if not ResourceLoader.exists(Race.TRACKS_DIR + map + ".tscn"):
		leave_to_menu("У тебя нет карты «%s», попроси её у хоста" % map)
		return
	map_name = map
	_back_to_lobby()


## Хост: после гонки — всех обратно в лобби на карте (новые игроки снова могут войти).
func request_lobby() -> void:
	if is_host():
		rpc(&"_back_to_lobby")


@rpc("authority", "call_local", "reliable")
func _back_to_lobby() -> void:
	race_started = false
	race = null
	_local_car = null
	_objects.clear()
	if is_host():
		_start_broadcast()
	get_tree().reload_current_scene.call_deferred()


func _physics_process(delta: float) -> void:
	_poll_discovery(delta)
	if not is_online() or race == null:
		return
	if _local_car != null and is_instance_valid(_local_car):
		_send_left -= delta
		if _send_left <= 0.0:
			var moving := absf(_local_car.forward_speed) > 0.1 or not _local_car.is_on_floor()
			_send_left = 1.0 / (CAR_SEND_RATE if moving or _teleport_packets > 0 else CAR_IDLE_SEND_RATE)
			var teleport := _teleport_packets > 0
			_teleport_packets = maxi(_teleport_packets - 1, 0)
			rpc(&"_car_state", NetCarSync.now(), _local_car.get_net_state(), teleport)
	if is_host():
		_race_send_left -= delta
		if _race_send_left <= 0.0:
			_race_send_left = 1.0 / RACE_SEND_RATE
			_send_race_state()


## Хозяин машины -> все: её состояние.
@rpc("any_peer", "call_remote", "unreliable_ordered")
func _car_state(sender_time: float, state: Array, teleport: bool) -> void:
	if race == null:
		return
	var car := race.get_net_car(multiplayer.get_remote_sender_id())
	if car == null:
		return
	var sync := NetCarSync.of(car)
	if sync != null:
		sync.push(sender_time, state, teleport)


func _send_race_state() -> void:
	var manager := race.race_manager
	var data := []
	for id in get_player_ids():
		var racer := race.get_net_racer(id)
		if racer == null:
			continue
		data.append([id, racer.lap, racer.next_checkpoint, racer.checkpoints_passed, racer.race_distance,
				racer.finished, racer.finish_time, racer.finish_place])
	rpc(&"_race_state", int(manager.state), manager.race_time, data)


## Хост -> все: круги, чекпоинты, места и финиш всех участников.
@rpc("authority", "call_remote", "unreliable_ordered")
func _race_state(state: int, race_time: float, data: Array) -> void:
	if race == null:
		return
	var manager := race.race_manager
	for row in data:
		var racer := race.get_net_racer(int(row[0]))
		if racer != null:
			manager.apply_racer_state(racer, row[1], row[2], row[3], row[4], row[5], row[6], row[7])
	manager.apply_race_state(state as RaceManager.State, race_time)


# --------------------------------------------------------------------------
# Предметы
# --------------------------------------------------------------------------

## Своя машина въехала в коробку: спросить хоста (он решает, есть ли она и что внутри).
func request_box(index: int) -> void:
	if is_host():
		_grant_box(index, 1)
	else:
		rpc_id(1, &"_request_box", index)


@rpc("any_peer", "call_remote", "reliable")
func _request_box(index: int) -> void:
	if is_host():
		_grant_box(index, multiplayer.get_remote_sender_id())


func _grant_box(index: int, peer: int) -> void:
	if race == null or index < 0 or index >= race.item_boxes.size() or not race.item_boxes[index].usable:
		return
	# Предмет — по месту взявшего (хост знает места всех).
	var box := race.item_boxes[index]
	rpc(&"_box_taken", index, peer, box.item_for(race.get_net_car(peer)).id)


## Хост -> все: коробку взял peer, внутри item_id (предмет получает только он).
@rpc("authority", "call_local", "reliable")
func _box_taken(index: int, peer: int, item_id: StringName) -> void:
	if race == null or index < 0 or index >= race.item_boxes.size():
		return
	var car := race.get_net_car(peer)
	race.item_boxes[index].take(car, ItemCatalog.by_id(item_id) if peer == my_id() else null)


## Своя машина применила предмет: остальные повторяют его у себя (объекты, вспышка);
## power — сила заряда (помидор), у остальных предмет летит так же.
func item_used(item: Item, power: float = 1.0, target: CarController = null) -> void:
	if is_online():
		# Цель автонаводки — по номеру игрока (0 — нет).
		var target_peer := int(target.get_meta(ItemObject.NET_PEER_META, 0)) if target != null else 0
		rpc(&"_item_used", item.id, power, target_peer)


@rpc("any_peer", "call_remote", "reliable")
func _item_used(item_id: StringName, power: float, target_peer: int) -> void:
	if race == null:
		return
	var car := race.get_net_car(multiplayer.get_remote_sender_id())
	var item := ItemCatalog.by_id(item_id)
	if car == null or item == null:
		return
	if item.others_hear:
		for sound in item.use_sounds:
			Sfx.play(self, sound)
	var target := race.get_net_car(target_peer) if target_peer != 0 else null
	item.use_at(car, power, target)


## Объект предмета появился (у всех одинаковый id: хозяин + номер по порядку).
func register_object(item_object: ItemObject) -> void:
	_objects[item_object.object_id] = item_object


func unregister_object(item_object: ItemObject) -> void:
	if _objects.get(item_object.object_id) == item_object:
		_objects.erase(item_object.object_id)


## Свою машину задел объект предмета: сообщить хосту; исход парирования — по своему окну.
func report_hit(item_object: ItemObject, parried: bool) -> void:
	if is_host():
		_confirm_hit(item_object.object_id, 1, parried)
	else:
		rpc_id(1, &"_report_hit", item_object.object_id, parried)


@rpc("any_peer", "call_remote", "reliable")
func _report_hit(object_id: int, parried: bool) -> void:
	if is_host():
		_confirm_hit(object_id, multiplayer.get_remote_sender_id(), parried)


## Хост проверяет: объект ещё есть, задет не хозяин — и подтверждает всем.
func _confirm_hit(object_id: int, victim: int, parried: bool) -> void:
	var item_object: ItemObject = _objects.get(object_id)
	if item_object == null or not is_instance_valid(item_object) or item_object.is_queued_for_deletion():
		return
	var car := race.get_net_car(victim) if race != null else null
	if car == null or car == item_object.owner_car:
		return
	rpc(&"_hit_confirmed", object_id, victim, parried)


@rpc("authority", "call_local", "reliable")
func _hit_confirmed(object_id: int, victim: int, parried: bool) -> void:
	var item_object: ItemObject = _objects.get(object_id)
	var car := race.get_net_car(victim) if race != null else null
	if item_object == null or not is_instance_valid(item_object) or car == null:
		return
	item_object.apply_hit(car, parried)


# --------------------------------------------------------------------------
# Эмоции
# --------------------------------------------------------------------------

func _on_local_emote(emote_name: StringName, seconds: float) -> void:
	if is_online():
		rpc(&"_emote", emote_name, seconds)


@rpc("any_peer", "call_remote", "reliable")
func _emote(emote_name: StringName, seconds: float) -> void:
	var car := race.get_net_car(multiplayer.get_remote_sender_id()) if race != null else null
	if car != null:
		car.emote(emote_name, seconds)


# --------------------------------------------------------------------------
# Радио машины (CarRadio): трек и место в нём — остальным
# --------------------------------------------------------------------------

## Своё радио включили или выключили (path пустой) — остальным.
func send_radio(path: String, position: float) -> void:
	if is_online():
		rpc(&"_radio", path, position)


@rpc("any_peer", "call_remote", "reliable")
func _radio(path: String, position: float) -> void:
	var car := race.get_net_car(multiplayer.get_remote_sender_id()) if race != null else null
	# Трек — только из своей папки радио (чужой путь не грузим).
	if car != null and (path.is_empty() or CarRadio.tracks().has(path)):
		CarRadio.of(car).play_track(path, position, false)


# --------------------------------------------------------------------------
# Игры в локальной сети: хост рассылает ID сессии, меню показывает список
# --------------------------------------------------------------------------

func _start_broadcast() -> void:
	_stop_broadcast()
	_broadcaster = PacketPeerUDP.new()
	_broadcaster.set_broadcast_enabled(true)
	_broadcaster.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	_discovery_left = 0.0


func _stop_broadcast() -> void:
	if _broadcaster != null:
		_broadcaster.close()
	_broadcaster = null


## Слушать объявления игр (меню).
func start_listening() -> void:
	if _listener != null:
		return
	_listener = PacketPeerUDP.new()
	if _listener.bind(DISCOVERY_PORT) != OK:
		_listener = null


func stop_listening() -> void:
	if _listener != null:
		_listener.close()
	_listener = null
	found_games.clear()


func _poll_discovery(delta: float) -> void:
	if _broadcaster != null and is_host():
		_discovery_left -= delta
		if _discovery_left <= 0.0:
			_discovery_left = DISCOVERY_INTERVAL
			var info := {"game": DISCOVERY_TAG, "v": PROTOCOL_VERSION, "id": session_id, "name": player_name,
					"map": map_name, "players": players.size(), "max": MAX_PLAYERS, "open": not race_started}
			_broadcaster.put_packet(JSON.stringify(info).to_utf8_buffer())
	if _listener == null:
		return
	var changed := false
	while _listener.get_available_packet_count() > 0:
		var info = JSON.parse_string(_listener.get_packet().get_string_from_utf8())
		if info is Dictionary and info.get("game") == DISCOVERY_TAG and int(info.get("v", 0)) == PROTOCOL_VERSION:
			info["seen"] = NetCarSync.now()
			found_games[String(info.get("id", ""))] = info
			changed = true
	for id in found_games.keys():
		if NetCarSync.now() - float(found_games[id]["seen"]) > DISCOVERY_TIMEOUT:
			found_games.erase(id)
			changed = true
	if changed:
		games_changed.emit()


## Контекст Tube из файла. Кнопка редактора «Generate app id» в TubeContext — лямбда,
## которая держит сам ресурс (цикл ссылок: ресурс не освобождается при выходе); в игре
## она не нужна — разрываем.
static func _load_context() -> TubeContext:
	var context := load(CONTEXT_PATH) as TubeContext
	context.set(&"_generate_app_id_tool_button", Callable())
	return context
