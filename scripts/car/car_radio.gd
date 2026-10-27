class_name CarRadio
extends Node
## Магнитола машины (пасхалка автора ремейка): играет трек из assets/music/radio, слышно всем,
## кто рядом — громкость по расстоянию до своей машины (до RADIUS м). Звук — «сабвуфер в Жигулях»
## (просьба автора ремейка): своя шина BUS_NAME (в Music) — эквалайзер с подъёмом басов, жёсткий
## лимитер с запасом громкости, анализатор спектра. Пока играет — вокруг машины кольцо
## эквалайзера (RadioRing, столбики по спектру), кузов подпрыгивает на басах. Включает своя
## панель (RadioPanel, клавиша 7); в сети трек
## и место в нём уходят остальным (Network.send_radio), у них играет на «марионетке».
## Пока радио слышно, музыка карты тише (GameMusic.set_duck).
## Узел «Radio» появляется у машины при первом обращении (CarRadio.of).

signal changed

const TRACKS_DIR := "res://assets/music/radio/"
## Обложки 32×32 (официальные обложки альбомов с Deezer, ffmpeg -vf scale=32:32:flags=area)
## и названия треков.
const COVERS_DIR := TRACKS_DIR + "covers/"
const INFO := TRACKS_DIR + "tracks.json"
## Слышно до RADIUS м, в NEAR м — во всю громкость.
const RADIUS := 40.0
const NEAR := 8.0
## Музыка карты тише на столько, когда радио слышно во всю, дБ.
const DUCK_DB := -18.0
const NODE_NAME := &"Radio"
## Шина радио: сначала тише на HEADROOM_DB (треки и так в 0 дБ: без запаса подъём басов только
## давил лимитер — басы выходили те же, автор ремейка: «заглушил»), эквалайзер EQ6 (32, 100,
## 320 Гц, 1, 3.2, 10 кГц) — басы сильно вверх, лимитер — плотно обратно до потолка; анализатор
## спектра — для кольца. Замер на «Бассоке» (запись выхода шины): громкость −7.5 LUFS против
## −8.2 у файла, суб-басы +2 дБ, верхи −2.4 дБ (бас над верхами 12 дБ против 8), пики −0.3 дБ.
const BUS_NAME := &"Radio"
const HEADROOM_DB := -9.0
const EQ_GAINS_DB: Array[float] = [14.0, 13.0, 4.0, -1.0, 0.0, 2.0]
const LIMITER_GAIN_DB := 9.0
const LIMITER_CEILING_DB := -0.3
const SPECTRUM_EFFECT := 3
## Полосы кольца: RadioRing.BARS / 2 полос от SPECTRUM_LOW до SPECTRUM_HIGH Гц (логарифмически),
## по кругу зеркально; уровень — от FLOOR_DB до 0 дБ, выше частоты — на TILT_DB за полосу громче
## (у музыки верхи тише); гаснет на DECAY за секунду.
const SPECTRUM_LOW := 40.0
const SPECTRUM_HIGH := 12000.0
const FLOOR_DB := -54.0
const TILT_DB := 1.6
const DECAY := 2.2
## Кузов на басах: подскок до BOUNCE_HEIGHT м, опускается на BOUNCE_FALL м/с.
const BOUNCE_HEIGHT := 0.18
const BOUNCE_FALL := 1.2
## Удар баса: насколько уровень выше среднего (среднее догоняет за ~1/BASS_AVERAGE_RATE с).
const BASS_AVERAGE_RATE := 4.0
const KICK_SCALE := 8.0

## Слышимость всех играющих радио (для приглушения музыки карты): id узла -> 0..1.
static var _heard: Dictionary = {}

## Путь трека (пусто — выключено).
var track := ""

var _car: CarController
var _player: AudioStreamPlayer
var _ring: RadioRing
var _levels := PackedFloat32Array()
var _bounce := 0.0
var _bass_average := 0.0
var _visual: Node3D
var _visual_rest_y := 0.0
## На паузе: какой трек и с какого места продолжить.
var _paused_track := ""
var _paused_at := 0.0


## Магнитола машины (создаётся при первом обращении).
static func of(car: CarController) -> CarRadio:
	var radio := car.get_node_or_null(NodePath(NODE_NAME)) as CarRadio
	if radio == null:
		radio = CarRadio.new()
		radio.name = NODE_NAME
		car.add_child(radio)
	return radio


## Треки папки assets/music/radio (в собранной игре — по .import), по имени.
static func tracks() -> PackedStringArray:
	var found: Array = []
	for raw in DirAccess.get_files_at(TRACKS_DIR):
		var file := raw.trim_suffix(".import").trim_suffix(".remap")
		if file.get_extension().to_lower() in ["mp3", "ogg", "wav"] and not found.has(TRACKS_DIR + file):
			found.append(TRACKS_DIR + file)
	found.sort()
	return PackedStringArray(found)


## Название и исполнитель: из tracks.json (в именах файлов порядок разный), иначе из имени
## файла «исполнитель - трек». {"title": …, "artist": …}
static func info(path: String) -> Dictionary:
	var base := path.get_file().get_basename()
	var known := load(INFO) as JSON if ResourceLoader.exists(INFO) else null
	if known != null and known.data is Dictionary and (known.data as Dictionary).has(base):
		return (known.data as Dictionary)[base]
	for separator in [" - ", " – "]:
		var parts := base.split(separator, true, 1)
		if parts.size() == 2:
			return {"title": parts[1], "artist": parts[0]}
	return {"title": base, "artist": ""}


## Обложка трека (covers/<имя файла>.png, 32×32) или null.
static func cover(path: String) -> Texture2D:
	var file := COVERS_DIR + path.get_file().get_basename() + ".png"
	return load(file) as Texture2D if ResourceLoader.exists(file) else null


func _ready() -> void:
	_car = get_parent() as CarController
	_levels.resize(RadioRing.BARS)
	_visual = _car.get_node_or_null(^"Visual") as Node3D if _car != null else null
	if _visual != null:
		_visual_rest_y = _visual.position.y


## Шина радио (создаётся при первом треке): басы, лимитер, спектр; уходит в Music.
static func _bus_index() -> int:
	var index := AudioServer.get_bus_index(BUS_NAME)
	if index >= 0:
		return index
	index = AudioServer.bus_count
	AudioServer.add_bus(index)
	AudioServer.set_bus_name(index, BUS_NAME)
	AudioServer.set_bus_send(index, GameMusic.BUS)
	var headroom := AudioEffectAmplify.new()
	headroom.volume_db = HEADROOM_DB
	AudioServer.add_bus_effect(index, headroom, 0)
	var eq := AudioEffectEQ6.new()
	for band in EQ_GAINS_DB.size():
		eq.set_band_gain_db(band, EQ_GAINS_DB[band])
	AudioServer.add_bus_effect(index, eq, 1)
	var limiter := AudioEffectHardLimiter.new()
	limiter.pre_gain_db = LIMITER_GAIN_DB
	limiter.ceiling_db = LIMITER_CEILING_DB
	AudioServer.add_bus_effect(index, limiter, 2)
	AudioServer.add_bus_effect(index, AudioEffectSpectrumAnalyzer.new(), SPECTRUM_EFFECT)
	return index


func _exit_tree() -> void:
	_heard.erase(get_instance_id())
	_apply_duck()


## Включить трек с места position, с; local — включил сам игрок (тогда — остальным в сети).
func play_track(path: String, position: float = 0.0, local: bool = true) -> void:
	_stop_player()
	track = path
	if not path.is_empty():
		_paused_track = ""
	if not path.is_empty() and DisplayServer.get_name() != "headless":
		var stream := load(path) as AudioStream
		if stream != null:
			_player = AudioStreamPlayer.new()
			_player.bus = AudioServer.get_bus_name(_bus_index())
			_player.stream = stream
			_player.volume_db = -80.0
			_player.finished.connect(_on_finished)
			add_child(_player)
			_player.play(clampf(position, 0.0, stream.get_length()))
	_show_ring(not path.is_empty())
	if local:
		Network.session().send_radio(path, position)
	changed.emit()


func stop(local: bool = true) -> void:
	play_track("", 0.0, local)


func is_playing() -> bool:
	return not track.is_empty()


## Что показывать в плеере: играющий трек, иначе стоящий на паузе, иначе первый.
func current() -> String:
	if not track.is_empty():
		return track
	if not _paused_track.is_empty():
		return _paused_track
	var list := tracks()
	return list[0] if not list.is_empty() else ""


## Пауза / продолжить с того же места (остальным — тишина и снова трек с места).
func toggle_pause() -> void:
	if is_playing():
		var paused := track
		_paused_at = playback_position()
		stop()
		_paused_track = paused
		changed.emit()
	else:
		var resume := current()
		if not resume.is_empty():
			play_track(resume, _paused_at if resume == _paused_track else 0.0)


## Следующий (step 1) или предыдущий (−1) трек по списку, с начала.
func skip(step: int) -> void:
	var list := tracks()
	if list.is_empty():
		return
	var index := list.find(current())
	play_track(list[posmod(index + step, list.size())])


## Сколько уже играет текущий трек, с (для тех, кто вошёл позже).
func playback_position() -> float:
	return _player.get_playback_position() if _player != null else 0.0


func _process(delta: float) -> void:
	if track.is_empty() or _car == null:
		return
	var heard := _heard_level()
	if _player != null:
		_player.volume_db = linear_to_db(maxf(heard, 0.001))
	_heard[get_instance_id()] = heard
	_apply_duck()
	_update_levels(delta)
	if _ring != null:
		_ring.set_levels(_levels)
	# Подскок кузова на ударах: бас (полосы 1–2, ~60–120 Гц) резко выше своего среднего —
	# толчок вверх сразу, вниз — плавно. По самому уровню кузов просто висел бы приподнятым.
	var bass := maxf(_levels[1], _levels[2])
	_bass_average = lerpf(_bass_average, bass, minf(BASS_AVERAGE_RATE * delta, 1.0))
	var kick := clampf((bass - _bass_average) * KICK_SCALE, 0.0, 1.0) * BOUNCE_HEIGHT
	_bounce = kick if kick > _bounce else move_toward(_bounce, kick, BOUNCE_FALL * delta)
	if _visual != null:
		_visual.position.y = _visual_rest_y + _bounce


## Уровни столбиков по спектру шины радио (смесь всех слышимых радио — делим на самое громкое,
## чтобы кольцо далёкой машины тоже плясало).
func _update_levels(delta: float) -> void:
	var analyzer := AudioServer.get_bus_effect_instance(_bus_index(), SPECTRUM_EFFECT) \
			as AudioEffectSpectrumAnalyzerInstance
	var loudest := 0.05
	for level: float in _heard.values():
		loudest = maxf(loudest, level)
	@warning_ignore("integer_division")
	var bands := RadioRing.BARS / 2
	for band in bands:
		var low := SPECTRUM_LOW * pow(SPECTRUM_HIGH / SPECTRUM_LOW, float(band) / bands)
		var high := SPECTRUM_LOW * pow(SPECTRUM_HIGH / SPECTRUM_LOW, float(band + 1) / bands)
		var level := 0.0
		if analyzer != null:
			var magnitude := analyzer.get_magnitude_for_frequency_range(low, high)
			var db := linear_to_db(maxf((magnitude.x + magnitude.y) * 0.5 / loudest, 0.00001)) + band * TILT_DB
			level = clampf((db - FLOOR_DB) / -FLOOR_DB, 0.0, 1.0)
		for bar in [band, RadioRing.BARS - 1 - band]:
			_levels[bar] = level if level > _levels[bar] else maxf(level, _levels[bar] - DECAY * delta)


## Кольцо эквалайзера: есть, пока играет трек.
func _show_ring(on: bool) -> void:
	if on and _ring == null and _car != null:
		_ring = RadioRing.new()
		_ring.name = "RadioRing"
		_car.add_child(_ring)
	elif not on and _ring != null:
		_ring.queue_free()
		_ring = null
		_levels.fill(0.0)
		_bounce = 0.0
		if _visual != null:
			_visual.position.y = _visual_rest_y


## Слышимость 0..1: по расстоянию до своей машины (нет её — до камеры), плавно к краю.
func _heard_level() -> float:
	var listener: Node3D = null
	for node in get_tree().get_nodes_in_group(ItemObject.LOCAL_PLAYER_GROUP):
		listener = node as Node3D
		break
	if listener == null:
		listener = get_viewport().get_camera_3d()
	if listener == null:
		return 1.0
	var distance := listener.global_position.distance_to(_car.global_position)
	var t := clampf((distance - NEAR) / (RADIUS - NEAR), 0.0, 1.0)
	return (1.0 - t) * (1.0 - t)


func _on_finished() -> void:
	# Трек кончился — следующий по списку (у всех одинаково: каждый листает сам).
	var list := tracks()
	if list.is_empty():
		return
	var next := list[(list.find(track) + 1) % list.size()]
	play_track(next, 0.0, false)


func _stop_player() -> void:
	_heard.erase(get_instance_id())
	_apply_duck()
	if _player != null:
		_player.queue_free()
		_player = null


static func _apply_duck() -> void:
	var loudest := 0.0
	for level: float in _heard.values():
		loudest = maxf(loudest, level)
	GameMusic.player().set_duck(DUCK_DB * loudest)
