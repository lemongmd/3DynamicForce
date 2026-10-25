class_name RaceManager
extends Node
## Правила гонки: обратный отсчёт, круги и чекпоинты, места, финиш.
##
## Чекпоинты — равные отрезки трассы (Track.checkpoint_count), чекпоинт 0 — линия
## старта/финиша. Чекпоинт засчитывается, только если он следующий по порядку,
## поэтому срезать через траву или «качаться» туда-обратно через финиш бесполезно.
## Пройденный чекпоинт становится точкой возврата машины (падение, застревание).
##
## В сетевой игре круги, чекпоинты, места и финиш считает только хост (authority);
## у клиентов authority = false — состояние приходит от хоста (apply_racer_state,
## apply_race_state), сигналы испускаются так же, при изменениях.

signal countdown_tick(seconds_left: int)
signal race_started
signal lap_started(racer: RacerState, lap: int)
signal checkpoint_passed(racer: RacerState, index: int)
signal racer_finished(racer: RacerState)
signal race_finished

enum State { WAITING, COUNTDOWN, RACING, FINISHED }

@export var track: Track
@export_range(1, 99) var laps: int = 5
@export_range(0, 10) var countdown_seconds: int = 3
## Сколько секунд после финиша первого ждать остальных (0 — ждать всех).
## В оригинале гонка кончается сразу при финише первого; ждать 30 с — решение автора ремейка.
@export var finish_timeout: float = 30.0

var state: State = State.WAITING
var racers: Array[RacerState] = []
## false — клиент сети: состояние гонки задаёт хост.
var authority: bool = true
## Время с момента старта, с.
var race_time: float = 0.0

var _countdown_left: float = 0.0
var _last_countdown_value: int = -1
var _finished_count: int = 0
var _timeout_left: float = -1.0


## Зарегистрировать машину в гонке. Вызывать, когда машина уже стоит на решётке.
func add_racer(car: CarController, display_name: String, is_local_player: bool) -> RacerState:
	var racer := RacerState.new()
	racer.car = car
	racer.display_name = display_name
	racer.is_local_player = is_local_player
	racer.progress = TrackProgress.new(track)
	racer.progress.update(car.global_position)
	car.controls_enabled = state == State.RACING
	racers.append(racer)
	_update_racer_distance(racer)
	_update_places()
	return racer


## Начать обратный отсчёт; по его окончании машины получают управление.
func start_countdown() -> void:
	if state != State.WAITING:
		return
	for racer in racers:
		racer.car.controls_enabled = false
	state = State.COUNTDOWN
	_countdown_left = float(countdown_seconds)
	_last_countdown_value = -1
	if countdown_seconds <= 0:
		_start_race()


## Убрать участника (отключился игрок). Места пересчитываются; если остальные уже
## финишировали — гонка кончается.
func remove_racer(racer: RacerState) -> void:
	racers.erase(racer)
	if racer.finished and racer.finish_place > 0:
		_finished_count = maxi(_finished_count - 1, 0)
	_update_places()
	if authority and state == State.RACING and not racers.is_empty() \
			and racers.all(func(r: RacerState) -> bool: return r.finished):
		_finish_race()


## Клиент: состояние участника от хоста. Испускает lap_started / racer_finished при изменениях.
func apply_racer_state(racer: RacerState, lap: int, next_checkpoint: int, checkpoints_passed: int,
		race_distance: float, finished: bool, finish_time: float, finish_place: int) -> void:
	var old_lap := racer.lap
	var was_finished := racer.finished
	if next_checkpoint != racer.next_checkpoint:
		# Возврат после падения — на последний пройденный чекпоинт (как у хоста).
		var passed := posmod(next_checkpoint - 1, track.checkpoint_count)
		racer.car.set_spawn_transform(track.get_transform_at(track.clamp_to_road(track.get_checkpoint_offset(passed) + 2.0)))
	racer.next_checkpoint = next_checkpoint
	racer.checkpoints_passed = checkpoints_passed
	racer.race_distance = race_distance
	racer.finish_place = finish_place
	if finished and not was_finished:
		racer.finished = true
		racer.lap = laps
		racer.finish_time = finish_time
		_update_places()
		if finish_time >= 0.0:
			racer_finished.emit(racer)
		return
	racer.lap = lap
	_update_places()
	if lap > old_lap and lap <= laps:
		if old_lap > 0:
			racer.lap_times.append(race_time - racer.lap_start_time)
		racer.lap_start_time = race_time
		lap_started.emit(racer, lap)


## Клиент: состояние гонки от хоста (время подтягивается плавно, финиш — сразу).
func apply_race_state(host_state: State, host_time: float) -> void:
	if host_state == State.RACING and state == State.RACING:
		race_time = host_time if absf(host_time - race_time) > 1.0 else lerpf(race_time, host_time, 0.2)
	elif host_state == State.FINISHED and state != State.FINISHED:
		race_time = host_time
		state = State.FINISHED
		race_finished.emit()


## Участник, которым управляет этот компьютер (null, если такого нет).
func get_local_racer() -> RacerState:
	for racer in racers:
		if racer.is_local_player:
			return racer
	return null


## Участники по местам (1-е место первым).
## Место машины для выбора предмета: 0 — первый, 1 — последний; −1 — гонка не идёт,
## участник один или машина не в гонке (тогда предмет равновероятный).
func place_share(car: CarController) -> float:
	if state != State.RACING or racers.size() < 2:
		return -1.0
	for racer in racers:
		if racer.car == car:
			if racer.finished or racer.place <= 0:
				return -1.0
			return float(racer.place - 1) / float(racers.size() - 1)
	return -1.0


func get_sorted_racers() -> Array[RacerState]:
	var sorted := racers.duplicate()
	sorted.sort_custom(_compare_racers)
	return sorted


func _physics_process(delta: float) -> void:
	match state:
		State.COUNTDOWN:
			_countdown_left -= delta
			var value := ceili(_countdown_left)
			if value > 0 and value != _last_countdown_value:
				_last_countdown_value = value
				countdown_tick.emit(value)
			if _countdown_left <= 0.0:
				_start_race()
		State.RACING:
			race_time += delta
			if not authority:
				return
			for racer in racers:
				_update_racer(racer)
			_update_places()
			if _timeout_left > 0.0:
				_timeout_left -= delta
				if _timeout_left <= 0.0:
					_finish_race()


func _start_race() -> void:
	state = State.RACING
	race_time = 0.0
	for racer in racers:
		racer.car.controls_enabled = true
		racer.lap_start_time = 0.0
	race_started.emit()


func _update_racer(racer: RacerState) -> void:
	if racer.finished:
		return
	var offset := racer.progress.update(racer.car.global_position)
	var segment := clampi(int(offset / track.get_checkpoint_length()), 0, track.checkpoint_count - 1)
	# Портал перенёс машину через разрыв дороги: чекпоинты внутри разрыва не проехать —
	# засчитываются, если машина уже дальше них.
	while segment != racer.next_checkpoint and track.is_checkpoint_in_gap(racer.next_checkpoint) \
			and posmod(segment - racer.next_checkpoint, track.checkpoint_count) < track.checkpoint_count * 0.5:
		_pass_checkpoint(racer, racer.next_checkpoint)
	if segment == racer.next_checkpoint:
		_pass_checkpoint(racer, segment)
	_update_racer_distance(racer)


func _pass_checkpoint(racer: RacerState, index: int) -> void:
	racer.checkpoints_passed += 1
	racer.next_checkpoint = (index + 1) % track.checkpoint_count
	# Возвращаться после падения/застревания — на этот чекпоинт, по центру дороги.
	racer.car.set_spawn_transform(track.get_transform_at(track.clamp_to_road(track.get_checkpoint_offset(index) + 2.0)))
	checkpoint_passed.emit(racer, index)
	if index != 0:
		return
	if racer.lap > 0:
		racer.lap_times.append(race_time - racer.lap_start_time)
	racer.lap_start_time = race_time
	racer.lap += 1
	if racer.lap > laps:
		_finish_racer(racer)
	else:
		lap_started.emit(racer, racer.lap)


## Дистанция = пройденные чекпоинты + путь от последнего пройденного.
## Монотонно растёт по ходу гонки, в том числе до первого пересечения старта.
func _update_racer_distance(racer: RacerState) -> void:
	var segment_length := track.get_checkpoint_length()
	var last := posmod(racer.next_checkpoint - 1, track.checkpoint_count)
	var since_last := fposmod(racer.progress.offset - last * segment_length, track.length)
	if since_last > track.length * 0.5:
		since_last -= track.length
	racer.race_distance = racer.checkpoints_passed * segment_length + since_last


func _finish_racer(racer: RacerState) -> void:
	racer.finished = true
	racer.lap = laps
	racer.finish_time = race_time
	_finished_count += 1
	racer.finish_place = _finished_count
	_update_places()
	racer_finished.emit(racer)
	if _finished_count >= racers.size():
		_finish_race()
	elif _timeout_left < 0.0 and finish_timeout > 0.0:
		_timeout_left = finish_timeout


## Конец гонки: кто не доехал, получает место по текущей дистанции и время -1.
func _finish_race() -> void:
	if state == State.FINISHED:
		return
	_update_places()
	for racer in get_sorted_racers():
		if not racer.finished:
			racer.finished = true
			racer.finish_time = -1.0
			_finished_count += 1
			racer.finish_place = _finished_count
	_update_places()
	state = State.FINISHED
	race_finished.emit()


func _update_places() -> void:
	var sorted := get_sorted_racers()
	for i in sorted.size():
		sorted[i].place = i + 1


## Финишировавшие — по месту финиша, остальные — по пройденной дистанции.
func _compare_racers(a: RacerState, b: RacerState) -> bool:
	if a.finish_place > 0 or b.finish_place > 0:
		if a.finish_place > 0 and b.finish_place > 0:
			return a.finish_place < b.finish_place
		return a.finish_place > 0
	return a.race_distance > b.race_distance
