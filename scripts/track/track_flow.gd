class_name TrackFlow
extends RefCounted
## Проверка карты глазами гонщика: проходимость и логика расстановки (level-дизайн).
##
## Правила — из практики дизайна гоночных трасс (SuperTuxKart «Making Tracks: Gameplay
## Fundamentals», Л. Макмиллан «A Rational Approach to Racing Game Track Design» и др.):
## дорогу и препятствия видно заранее, у прыжка — свободная зона приземления, ускорители —
## на выходе из поворотов и простых участках, проезд не требует резких манёвров на скорости,
## старт широкий и свободный. Всё считается по физике нашей машины (CarController).
##
## Что проверяется (ошибка — проехать нельзя или нечестно, внимание — нелогично/неудобно):
##   * проезд: путь машины между твёрдыми препятствиями с учётом того, как резко она может
##     сместиться вбок на своей скорости (поворот носа ограничен, дорога сама поворачивает);
##     нет пути даже медленно — ошибка, есть только медленно — внимание (слалом слишком резкий);
##   * слепые места: твёрдое препятствие или ограждение сразу за крутым поворотом;
##   * прыжок: в зоне приземления препятствие (ошибка) или поворот (внимание);
##   * ускоритель: ведёт прямо в препятствие или перед крутым поворотом (вылет в стену);
##   * лента против хода: позади неё препятствие — машину прижмёт (ошибка);
##   * старт: на решётке и сразу за линией — препятствие (ошибка);
##   * коробки предметов внутри препятствий; узкая дорога.
## Плюс оценка круга: время при идеальной езде без ускорителей и самая низкая скорость.

## Физика машины (CarController): максимум, разгон, торможение, руль lerp(60, 120) °/с.
const MAX_SPEED := 30.0
const ACCELERATION := 16.0
const BRAKING := 40.0 * 0.6
const TURN_SLOW := deg_to_rad(60.0)
const TURN_FAST := deg_to_rad(120.0)
## Машина 1.6 × 3 м: полуширина с запасом и полудлина.
const CAR_HALF_WIDTH := 1.0
const CAR_HALF_LENGTH := 1.5
## Шаг по трассе, м; шаг сетки поперёк дороги, м.
const STEP := 1.0
const CELL := 0.25
## Наклон пути к оси дороги (tan угла) не больше этого — машина едет вперёд, а не поперёк.
const MAX_SLOPE := 0.7
const SLOPE_BINS := 29
## Скорости, на которых пробуем проехать, если на гоночной не выходит, м/с.
const SPEED_CAPS := [20.0, 12.0, 6.0]
## Обзор: камера видит примерно столько метров вперёд; поворот круче этого — «слепой».
const SIGHT := 18.0
const BLIND_TURN := deg_to_rad(50.0)
## Прыжок: зона приземления после трамплина, м.
const LANDING_FROM := 6.0
const LANDING_TO := 28.0
## Ускоритель: смотрим вперёд на столько метров.
const PAD_LOOKAHEAD := 30.0
const PAD_SHARP_TURN := deg_to_rad(75.0)
## После ускорителя на его полосе столько метров без твёрдых препятствий.
const PAD_CLEAR := 16.0
## Старт: решётка позади линии и разгон после неё, м.
const START_BACK := 24.0
const START_AHEAD := 12.0
## Самый узкий честный проезд, м: 2 блока оригинала (6 м) — можно, 1 блок (3 м) — машине тесно.
const MIN_ROAD_WIDTH := 5.0

const ERROR := "ошибка"
const WARNING := "внимание"


## Анализ трассы (она должна быть в дереве). Возвращает {issues: Array[Dictionary]
## ({level, offset, lateral, message}), errors, warnings, lap_time, min_speed, summary}.
static func analyze(track: Track) -> Dictionary:
	var issues: Array[Dictionary] = []
	var objects := _collect(track)
	var samples := maxi(int(track.length / STEP), 8)
	var speeds := _speed_profile(track, samples)

	if track.min_road_width() < MIN_ROAD_WIDTH:
		_add(issues, WARNING, 0.0, 0.0, "проезд %.1f м — уже машины с запасом (нужно от %.0f м)" % [
				track.min_road_width(), MIN_ROAD_WIDTH])
	_check_passage(track, objects, speeds, samples, issues)
	_check_blind(track, objects, issues)
	_check_ramps(track, objects, issues)
	_check_pads(track, objects, issues)
	_check_conveyors(track, objects, issues)
	_check_start(track, objects, issues)
	_check_boxes(objects, issues)

	var lap_time := 0.0
	var min_speed := INF
	for i in samples:
		if track.is_in_gap(i * STEP):
			continue
		lap_time += STEP / maxf(speeds[i], 1.0)
		min_speed = minf(min_speed, speeds[i])
	issues.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["offset"] < b["offset"])
	var errors := issues.filter(func(x: Dictionary) -> bool: return x["level"] == ERROR).size()
	var warnings := issues.size() - errors
	var summary := "круг ≈ %.0f с на гоночной скорости (без ускорителей), самая медленная точка %.0f м/с; ошибок %d, внимание %d" % [
			lap_time, min_speed, errors, warnings]
	return {"issues": issues, "errors": errors, "warnings": warnings, "lap_time": lap_time,
			"min_speed": min_speed, "summary": summary}


## Поворот дороги от from до to (метры от старта), без прямой через разрыв портала:
## участок, пересекающий разрыв, обрезается до разрыва.
static func _turn(track: Track, from: float, to: float) -> float:
	for gap in track.get_gaps():
		for shift in [0.0, track.length, -track.length]:
			var gx: float = gap.x + shift
			var gy: float = gap.y + shift
			if from < gx and to > gx:
				to = gx - 1.0
			if from < gy and to > gy:
				from = gy + 1.0
	if to <= from:
		return 0.0
	return track.get_direction_at(from).angle_to(track.get_direction_at(to))


## Текст замечания для списка.
static func format(issue: Dictionary) -> String:
	return "%s, %.0f м: %s" % [issue["level"], issue["offset"], issue["message"]]


# --------------------------------------------------------------------------

static func _add(issues: Array[Dictionary], level: String, offset: float, lateral: float, message: String) -> void:
	issues.append({"level": level, "offset": offset, "lateral": lateral, "message": message})


## Объекты из Props: вид, положение в координатах трассы, размер вдоль и поперёк.
static func _collect(track: Track) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var props := track.get_node_or_null(^"Props")
	if props == null:
		return result
	for child in props.get_children():
		var node := child as Node3D
		if node == null:
			continue
		var kind := ""
		if node.is_in_group(TrackLayout.RAMP_GROUP):
			kind = "ramp"
		elif node.is_in_group(TrackLayout.ITEM_BOX_GROUP):
			kind = "box"
		elif node is BoostPad:
			kind = "pad"
		elif node is MapZone:
			kind = "conveyor" if (node as MapZone).kind == MapZone.Kind.CONVEYOR else "zone"
		elif node is ParryHazard:
			kind = "parry"
		elif node is SnowTurret:
			continue  # стоит на стене
		elif node is StaticBody3D:
			kind = "solid"
		else:
			continue
		var where := TrackLayout.locate(track, node.global_position)
		var offset := float(where["offset"])
		var relative := TrackLayout.relative_yaw(track, node.global_basis.orthonormalized().get_euler().y, offset)
		var half := TrackLayout.half_extents(node)
		if node is MapZone:
			half = (node as MapZone).size * 0.5
		var across := absf(cos(relative)) * half.x + absf(sin(relative)) * half.y
		var along := absf(sin(relative)) * half.x + absf(cos(relative)) * half.y
		var entry := {"node": node, "kind": kind, "offset": offset, "lateral": float(where["lateral"]),
				"across": across, "along": along}
		if node is MapZone:
			# Направление ленты: её ось +X по ходу гонки (1) или против (−1).
			var dir := track.get_direction_at(offset)
			entry["flow"] = signf(node.global_basis.x.dot(dir))
		result.append(entry)
	return result


## Кривизна центральной линии (1/м) в точке offset.
static func _curvature(track: Track, offset: float) -> float:
	return _turn(track, offset - 3.0, offset + 3.0) / 6.0


## Скорость, с которой машина проходит кривизну kappa: руль ω(v) = 60..120 °/с,
## нужно ω(v) ≥ κ·v.
static func _corner_speed(kappa: float) -> float:
	var b := (TURN_FAST - TURN_SLOW) / MAX_SPEED
	if kappa <= b:
		return MAX_SPEED
	return minf(TURN_SLOW / (kappa - b), MAX_SPEED)


## Гоночная скорость в каждой точке: по кривизне, с разгоном и торможением.
static func _speed_profile(track: Track, samples: int) -> PackedFloat32Array:
	var v := PackedFloat32Array()
	v.resize(samples)
	for i in samples:
		v[i] = _corner_speed(_curvature(track, i * STEP))
	for pass_index in 2:
		for i in range(samples - 1, -1, -1):
			var next := v[(i + 1) % samples]
			v[i] = minf(v[i], sqrt(next * next + 2.0 * BRAKING * STEP))
		for i in samples:
			var previous := v[posmod(i - 1, samples)]
			v[i] = minf(v[i], sqrt(previous * previous + 2.0 * ACCELERATION * STEP))
	return v


## Свободные клетки поперёк дороги для центра машины в точке i (1 — свободно).
static func _free_cells(track: Track, solids: Array, offset: float, cells: int) -> PackedByteArray:
	var free := PackedByteArray()
	free.resize(cells)
	free.fill(1)
	# Клетки — по самой широкой дороге; где дорога уже (segment_widths), крайние заняты стеной.
	var edge: float = track.road_half_width_at(offset) - CAR_HALF_WIDTH
	var start: float = -track.max_road_width() * 0.5
	for c in cells:
		var lateral := start + (c + 0.5) * CELL
		if absf(lateral) > edge:
			free[c] = 0
	for o in solids:
		var d := absf(_wrap(offset - float(o["offset"]), track.length))
		if d > float(o["along"]) + CAR_HALF_LENGTH:
			continue
		var lo := float(o["lateral"]) - float(o["across"]) - CAR_HALF_WIDTH
		var hi := float(o["lateral"]) + float(o["across"]) + CAR_HALF_WIDTH
		for c in cells:
			var lateral := start + (c + 0.5) * CELL
			if lateral > lo and lateral < hi:
				free[c] = 0
	return free


static func _wrap(d: float, length: float) -> float:
	return wrapf(d, -length * 0.5, length * 0.5)


## Проезд между твёрдыми препятствиями. Состояние машины — смещение вбок и наклон пути
## к оси дороги; за метр наклон меняется не больше чем на запас руля (руль минус кривизна
## самой дороги). Проходим круг от старта; если гоночной скорости не хватает — пробуем медленнее.
static func _check_passage(track: Track, objects: Array[Dictionary], speeds: PackedFloat32Array,
		samples: int, issues: Array[Dictionary]) -> void:
	var solids := objects.filter(func(o: Dictionary) -> bool: return o["kind"] == "solid")
	if solids.is_empty():
		return
	var cells := int(track.max_road_width() / CELL)
	var free_by_sample: Array[PackedByteArray] = []
	var curvature := PackedFloat32Array()
	for i in samples:
		free_by_sample.append(_free_cells(track, solids, i * STEP, cells))
		curvature.append(_curvature(track, i * STEP))
	var fail := _sweep(track, free_by_sample, curvature, speeds, samples, cells, INF)
	if fail < 0:
		return
	# На гоночной скорости не выходит: где и на какой скорости проехать можно.
	for cap in SPEED_CAPS:
		if _sweep(track, free_by_sample, curvature, speeds, samples, cells, cap) < 0:
			_add(issues, WARNING, fail * STEP, 0.0,
					"резкий манёвр между препятствиями: на гоночной скорости (%.0f м/с) не объехать, только ≤ %.0f м/с — раздвиньте ряды или дайте место" % [
					speeds[fail], cap])
			return
	var still := _sweep(track, free_by_sample, curvature, speeds, samples, cells, SPEED_CAPS[SPEED_CAPS.size() - 1])
	_add(issues, ERROR, maxf(still, 0) * STEP, 0.0, "дорога перекрыта твёрдыми препятствиями — проехать нельзя")


## Проход круга; −1 — проехали, иначе номер точки, где путей не осталось.
static func _sweep(track: Track, free_by_sample: Array[PackedByteArray], curvature: PackedFloat32Array,
		speeds: PackedFloat32Array, samples: int, cells: int, cap: float) -> int:
	var slope_step := 2.0 * MAX_SLOPE / (SLOPE_BINS - 1)
	var reach := PackedByteArray()
	reach.resize(cells * SLOPE_BINS)
	var first: PackedByteArray = free_by_sample[0]
	for c in cells:
		if first[c] == 1:
			reach[c * SLOPE_BINS + (SLOPE_BINS >> 1)] = 1
	for i in range(1, samples + 1):
		var index := i % samples
		if track.is_in_gap(index * STEP):
			continue
		var v := minf(speeds[index], cap)
		var turn := lerpf(TURN_SLOW, TURN_FAST, clampf(v / MAX_SPEED, 0.0, 1.0))
		var spare := maxf(turn / maxf(v, 1.0) - absf(curvature[index]), 0.02) * STEP
		var slope_reach := maxi(int(spare / slope_step), 1)
		var free: PackedByteArray = free_by_sample[index]
		var next := PackedByteArray()
		next.resize(cells * SLOPE_BINS)
		var any := false
		for c in cells:
			for s in SLOPE_BINS:
				if reach[c * SLOPE_BINS + s] == 0:
					continue
				for ds in range(-slope_reach, slope_reach + 1):
					var s2 := s + ds
					if s2 < 0 or s2 >= SLOPE_BINS:
						continue
					var slope := -MAX_SLOPE + (s + s2) * 0.5 * slope_step
					var c2 := c + roundi(slope * STEP / CELL)
					if c2 < 0 or c2 >= cells or free[c2] == 0:
						continue
					next[c2 * SLOPE_BINS + s2] = 1
					any = true
		if not any:
			return index
		reach = next
	return -1


## Препятствие или ограждение сразу за крутым поворотом — его не видно до последнего.
static func _check_blind(track: Track, objects: Array[Dictionary], issues: Array[Dictionary]) -> void:
	for o in objects:
		if o["kind"] != "solid" and o["kind"] != "parry":
			continue
		var at: float = o["offset"]
		var turn := _turn(track, at - SIGHT, at - 2.0)
		if turn > BLIND_TURN:
			_add(issues, WARNING, at, o["lateral"],
					"%s сразу за поворотом на %.0f° — его видно в последний момент; отодвиньте на выход из поворота или поставьте перед ним предупреждение" % [
					o["node"].name, rad_to_deg(turn)])


## Трамплин: свободное приземление на прямой.
static func _check_ramps(track: Track, objects: Array[Dictionary], issues: Array[Dictionary]) -> void:
	for ramp in objects:
		if ramp["kind"] != "ramp":
			continue
		var at: float = ramp["offset"]
		for o in objects:
			if o["kind"] != "solid":
				continue
			var d := _wrap(float(o["offset"]) - at, track.length)
			var overlap := absf(float(o["lateral"]) - float(ramp["lateral"])) < float(o["across"]) + float(ramp["across"]) + CAR_HALF_WIDTH
			if d > LANDING_FROM and d < LANDING_TO and overlap:
				_add(issues, ERROR, float(o["offset"]), o["lateral"],
						"%s в зоне приземления после %s — машина падает прямо на него" % [o["node"].name, ramp["node"].name])
		var turn := _turn(track, at, at + LANDING_TO)
		if turn > deg_to_rad(25.0):
			_add(issues, WARNING, at, ramp["lateral"],
					"%s: приземление на повороте (%.0f°) — в полёте не повернуть, машину несёт в стену" % [
					ramp["node"].name, rad_to_deg(turn)])


## Ускоритель: не в препятствие и не перед крутым поворотом.
static func _check_pads(track: Track, objects: Array[Dictionary], issues: Array[Dictionary]) -> void:
	var reported := {}
	for pad in objects:
		if pad["kind"] != "pad":
			continue
		var at: float = pad["offset"]
		var row := int(at / 6.0)
		for o in objects:
			if o["kind"] != "solid":
				continue
			var d := _wrap(float(o["offset"]) - at, track.length)
			var overlap := absf(float(o["lateral"]) - float(pad["lateral"])) < float(o["across"]) + float(pad["across"])
			if d > 2.0 and d < PAD_CLEAR and overlap and not reported.has("o%d" % row):
				reported["o%d" % row] = true
				_add(issues, WARNING, at, pad["lateral"],
						"ускоритель ведёт прямо в %s (%.0f м) — разгон в препятствие" % [o["node"].name, d])
		var turn := _turn(track, at, at + PAD_LOOKAHEAD)
		if turn > PAD_SHARP_TURN and not reported.has("t%d" % row):
			reported["t%d" % row] = true
			_add(issues, WARNING, at, pad["lateral"],
					"ускоритель перед крутым поворотом (%.0f° за %.0f м) — лучше на выходе из поворота" % [
					rad_to_deg(turn), PAD_LOOKAHEAD])


## Лента против хода прижимает машину к тому, что позади неё.
static func _check_conveyors(track: Track, objects: Array[Dictionary], issues: Array[Dictionary]) -> void:
	for belt in objects:
		if belt["kind"] != "conveyor" or float(belt.get("flow", 1.0)) > 0.0:
			continue
		for o in objects:
			if o["kind"] != "solid":
				continue
			var d := _wrap(float(belt["offset"]) - float(o["offset"]), track.length) - float(belt["along"])
			var overlap := absf(float(o["lateral"]) - float(belt["lateral"])) < float(o["across"]) + float(belt["across"])
			if d > -1.0 and d < 8.0 and overlap:
				_add(issues, ERROR, float(o["offset"]), o["lateral"],
						"%s позади ленты против хода — лента прижмёт к нему машину" % o["node"].name)


## Старт: на решётке и сразу за линией ничего твёрдого.
static func _check_start(track: Track, objects: Array[Dictionary], issues: Array[Dictionary]) -> void:
	for o in objects:
		if o["kind"] != "solid" and o["kind"] != "ramp":
			continue
		var d := _wrap(float(o["offset"]), track.length)
		if d > -START_BACK and d < START_AHEAD:
			_add(issues, ERROR, float(o["offset"]), o["lateral"],
					"%s на стартовой решётке/разгоне (старт должен быть свободным)" % o["node"].name)


## Коробка предметов внутри твёрдого препятствия — её не взять.
static func _check_boxes(objects: Array[Dictionary], issues: Array[Dictionary]) -> void:
	for box in objects:
		if box["kind"] != "box":
			continue
		for o in objects:
			if o["kind"] != "solid":
				continue
			if absf(float(o["offset"]) - float(box["offset"])) < float(o["along"]) + 0.5 \
					and absf(float(o["lateral"]) - float(box["lateral"])) < float(o["across"]) + 0.5:
				_add(issues, WARNING, float(box["offset"]), box["lateral"],
						"коробка предметов внутри %s — её не взять" % o["node"].name)
