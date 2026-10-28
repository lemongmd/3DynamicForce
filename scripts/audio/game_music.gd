class_name GameMusic
extends Node
## Музыка игры (тег «music» оригинала): одна дорожка за раз, смена — плавным переходом.
## Автозагрузка «Music»; из кода — GameMusic.player() (в автотестах -s узел создаётся сам).
## Шина Music (громкость — в настройках). Играет и во время паузы.
##
## Как в оригинале:
##   * интро — Menu_start (play_intro), меню — по кругу Menu_loop (play_menu); в сезон Хэллоуина
##     (Season) — хэллоуинский ремикс Spark Main Theme: интро — его вступление, меню — петля;
##   * лобби на карте — LobbyForce, −10 дБ;
##   * гонка — через 0.4 с после старта музыка карты (Track.music), по кругу;
##   * первый финишировал — EbucheeMoloko, −2 дБ;
##   * объект карты Trigger «Music X» — смена музыки.

const BUS := &"Music"
## Плавный переход между дорожками, с.
const FADE_TIME := 0.4
const MENU_INTRO := preload("res://assets/original/music/menu_start.ogg")
const MENU_LOOP := preload("res://assets/original/music/menu_loop.ogg")
const HALLOWEEN_START := preload("res://assets/music/menu_halloween_start.ogg")
const HALLOWEEN_LOOP := preload("res://assets/music/menu_halloween_loop.ogg")
const LOBBY := preload("res://assets/original/music/lobbyforce.ogg")
const FINISH := preload("res://assets/original/sounds/ebucheemoloko.wav")
const LOBBY_VOLUME_DB := -10.0
const FINISH_VOLUME_DB := -2.0
## Тише этого — считаем, что дорожка не слышна, дБ.
const SILENT_DB := -60.0

static var _instance: GameMusic

## Что играет сейчас (null — тишина).
var current: AudioStream

var _player: AudioStreamPlayer
## Громкость дорожки без приглушения и само приглушение (радио рядом, CarRadio), дБ.
var _base_db := 0.0
var _duck_db := 0.0
var _loop: bool = true
## Что играть следом, когда текущая (не зацикленная) дорожка кончится.
var _queue: Array[AudioStream] = []
var _fading: Array[AudioStreamPlayer] = []


## Музыка игры: автозагрузка «Music»; в автотестах — создаётся здесь.
static func player() -> GameMusic:
	if is_instance_valid(_instance):
		return _instance
	var tree := Engine.get_main_loop() as SceneTree
	_instance = tree.root.get_node_or_null(^"Music") as GameMusic
	if _instance == null:
		_instance = GameMusic.new()
		_instance.name = "Music"
		tree.root.add_child.call_deferred(_instance)
	return _instance


func _ready() -> void:
	_instance = self
	process_mode = Node.PROCESS_MODE_ALWAYS


## Играть stream (по кругу, если loop) с громкостью volume_db; та же дорожка — не перезапускать.
func play(stream: AudioStream, volume_db: float = 0.0, loop: bool = true) -> void:
	_queue.clear()
	_base_db = volume_db
	if stream == current and _player != null and _player.playing:
		_player.volume_db = volume_db + _duck_db
		return
	_fade_out_current()
	current = stream
	_loop = loop
	# Без экрана (тесты) — только запоминаем: недоигранная дорожка висела бы в аудиосервере.
	if stream == null or not is_inside_tree() or DisplayServer.get_name() == "headless":
		return
	_player = AudioStreamPlayer.new()
	_player.bus = BUS
	_player.stream = stream
	_player.volume_db = volume_db + _duck_db
	_player.finished.connect(_on_finished.bind(_player))
	add_child(_player)
	_player.play()


## Музыка интро (один раз) и меню (по кругу); в сезон Хэллоуина — ремикс.
static func intro_stream() -> AudioStream:
	return HALLOWEEN_START if Season.is_halloween() else MENU_INTRO


static func menu_stream() -> AudioStream:
	return HALLOWEEN_LOOP if Season.is_halloween() else MENU_LOOP


## Интро: Menu_start один раз, потом Menu_loop (IntroS оригинала; интро идёт под Menu_start).
func play_intro() -> void:
	var streams: Array[AudioStream] = [intro_stream(), menu_stream()]
	_play_sequence(streams)


## Меню: Menu_loop по кругу (MenuS оригинала). Доигрывает Menu_start интро — пусть кончится
## сама (интро уходит в меню чуть раньше её конца), дальше и так Menu_loop.
## restart — начать музыку меню сразу (интро пропустили).
func play_menu(restart: bool = false) -> void:
	var loop := menu_stream()
	if current == loop or (current == intro_stream() and not _queue.is_empty() and not restart):
		return
	play(loop)


## Сколько секунд играет текущая дорожка (по звуку, с поправкой на задержку вывода);
## −1 — ничего не играет (тесты без звука).
func playback_position() -> float:
	if _player == null or not _player.playing:
		return -1.0
	return _player.get_playback_position() + AudioServer.get_time_since_last_mix() \
			- AudioServer.get_output_latency()


func play_lobby() -> void:
	play(LOBBY, LOBBY_VOLUME_DB)


func play_finish() -> void:
	play(FINISH, FINISH_VOLUME_DB)


## Приглушить музыку на db (≤ 0; 0 — как была): рядом играет радио машины.
func set_duck(db: float) -> void:
	if is_equal_approx(db, _duck_db):
		return
	_duck_db = db
	if _player != null:
		_player.volume_db = _base_db + _duck_db


## Тишина (плавно).
func stop() -> void:
	play(null)


func _on_finished(finished_player: AudioStreamPlayer) -> void:
	if finished_player != _player:
		return
	if not _queue.is_empty():
		_play_sequence(_queue.duplicate())
	elif _loop:
		_player.play()


## Дорожки по очереди, последняя — по кругу.
func _play_sequence(streams: Array[AudioStream]) -> void:
	play(streams[0], 0.0, streams.size() == 1)
	_queue = streams.slice(1)


func _fade_out_current() -> void:
	if _player == null:
		return
	var old := _player
	_player = null
	_fading.append(old)
	var tween := create_tween()
	tween.tween_property(old, ^"volume_db", SILENT_DB, FADE_TIME)
	tween.tween_callback(func() -> void:
		_fading.erase(old)
		old.queue_free())
