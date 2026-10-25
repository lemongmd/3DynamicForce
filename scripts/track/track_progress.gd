class_name TrackProgress
extends RefCounted
## Где машина на трассе: расстояние вдоль центральной линии от старта.
##
## Ближайшая точка ищется рядом с прошлой (окно window_m), поэтому на развязках
## и эстакадах прогресс не перескакивает на соседний участок трассы. Если машина
## оказалась далеко от линии (телепорт, вылет), поиск идёт по всей трассе.

var track: Track
## Сколько метров в обе стороны от прошлого положения просматривать.
var window_m: float = 40.0
## Дальше этого расстояния от линии — искать по всей трассе.
var resync_distance: float = 40.0
## Расстояние вдоль трассы от линии старта, 0..track.length.
var offset: float = 0.0
## Расстояние до центральной линии, м.
var distance_from_center: float = 0.0

var _segment: int = -1


func _init(target_track: Track) -> void:
	track = target_track


## Забыть прошлое положение (следующий update ищет по всей трассе).
func reset() -> void:
	_segment = -1


func update(global_pos: Vector3) -> float:
	var result := track.project(global_pos, _segment, window_m)
	if _segment >= 0 and float(result["distance"]) > resync_distance:
		result = track.project(global_pos, -1, window_m)
	_segment = int(result["segment"])
	offset = float(result["offset"])
	distance_from_center = float(result["distance"])
	return offset
