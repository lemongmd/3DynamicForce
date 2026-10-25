class_name RacerState
extends RefCounted
## Состояние одного участника гонки. Хранится и обновляется в RaceManager.
## В сетевой игре (этап 6) это состояние считает хост и рассылает клиентам.

var car: CarController
var display_name: String = ""
var is_local_player: bool = false
## Цвет иконки в HUD (по скину: R·64+64…, как PlayerCarIcon оригинала).
var color: Color = Color.WHITE
## Скин машины (CarSkin).
var skin: CarSkin
## Сеть: peer id игрока (1 — хост; в одиночной игре 1).
var peer_id: int = 1
var progress: TrackProgress

## Текущий круг: 0 — ещё не пересёк линию старта, 1..laps — едет, после финиша = laps.
var lap: int = 0
## Номер чекпоинта, который нужно пройти следующим (0 — линия старта/финиша).
var next_checkpoint: int = 0
## Сколько чекпоинтов пройдено за гонку (с учётом кругов).
var checkpoints_passed: int = 0
## Пройденная дистанция для сортировки мест, м.
var race_distance: float = 0.0
## Текущее место (1 — первый).
var place: int = 0

var finished: bool = false
## Время финиша, с; -1 — не доехал (гонка закончилась раньше).
var finish_time: float = -1.0
## Место на финише (0 — ещё не финишировал).
var finish_place: int = 0
## Время начала текущего круга и времена завершённых кругов, с.
var lap_start_time: float = 0.0
var lap_times: PackedFloat32Array = PackedFloat32Array()


## Лучший круг, с; -1 — ещё нет ни одного полного круга.
func get_best_lap() -> float:
	if lap_times.is_empty():
		return -1.0
	var best := lap_times[0]
	for t in lap_times:
		best = minf(best, t)
	return best
