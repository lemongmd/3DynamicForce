class_name TrackCheck
extends RefCounted
## Проверка карты (редактор карт и map_test.gd):
##   * нет «лысых» участков — между соседними игровыми объектами не больше MAX_GAP м;
##   * объекты не заходят на стену;
##   * объекты не наезжают друг на друга;
##   * на трассе есть коробки предметов.
## Объекты — игровые узлы из «Props» трассы (TrackLayout.is_gameplay).

## Самый длинный допустимый участок дороги без игровых объектов, м.
## Самый крутой допустимый склон, ° (машина держится на полу до 45°), и окно замера, м.
const MAX_SLOPE_DEG := 44
const SLOPE_WINDOW := 4.0
const MAX_GAP := 60.0
## Допуск на касание (объекты вплотную — не наложение), м.
const TOUCH_TOLERANCE := 0.05


## Проверить трассу (она должна быть в дереве сцены).
## Возвращает {"problems": PackedStringArray, "summary": String, "max_gap": float, "counts": Dictionary}.
static func run(track: Track) -> Dictionary:
	var problems := PackedStringArray()
	var props := track.get_node_or_null(^"Props")
	var objects: Array[Dictionary] = []
	var counts := {}
	if props != null:
		for child in props.get_children():
			var node := child as Node3D
			if node == null or not TrackLayout.is_gameplay(node):
				continue
			var where := TrackLayout.locate(track, node.global_position)
			var offset := float(where["offset"])
			var relative := TrackLayout.relative_yaw(track, node.global_basis.orthonormalized().get_euler().y, offset)
			var half := TrackLayout.half_extents(node)
			var across := absf(cos(relative)) * half.x + absf(sin(relative)) * half.y
			objects.append({"node": node, "offset": offset, "lateral": float(where["lateral"]),
					"across": across})
			var kind := kind_name(node)
			counts[kind] = int(counts.get(kind, 0)) + 1

	# Заполненность.
	var offsets := PackedFloat32Array()
	for o in objects:
		offsets.append(o["offset"])
	offsets.sort()
	var max_gap := track.length
	var gap_at := 0.0
	if not offsets.is_empty():
		max_gap = 0.0
		for i in offsets.size():
			var next := offsets[(i + 1) % offsets.size()] + (track.length if i == offsets.size() - 1 else 0.0)
			# Разрыв дороги (портал) пустым участком не считается.
			var empty := track.road_length_between(offsets[i], next)
			if empty > max_gap:
				max_gap = empty
				gap_at = offsets[i]
	if max_gap > MAX_GAP:
		problems.append("пустой участок %.0f м после отметки %.0f м (допустимо %.0f)" % [max_gap, gap_at, MAX_GAP])

	# На стене.
	for o in objects:
		if TrackLayout.is_wall_object(o["node"]):
			continue
		# Ширина дороги — в месте объекта (segment_widths: участки уже и шире).
		var edge: float = track.road_half_width_at(o["offset"])
		if absf(o["lateral"]) + o["across"] > edge + TOUCH_TOLERANCE:
			problems.append("%s заходит на стену (отметка %.0f м)" % [o["node"].name, o["offset"]])

	# Наложения: повёрнутые прямоугольники (по коллизии) в плоскости земли.
	for i in objects.size():
		for j in range(i + 1, objects.size()):
			var a: Dictionary = objects[i]
			var b: Dictionary = objects[j]
			if TrackLayout.is_surface(a["node"]) or TrackLayout.is_surface(b["node"]):
				continue
			if footprints_overlap(a["node"], b["node"]):
				problems.append("%s и %s наезжают друг на друга (отметка %.0f м)" % [a["node"].name, b["node"].name, a["offset"]])

	# Корень трассы случайно сдвигают в редакторе целиком: в игре почти незаметно, но
	# объекты карты и редактор считают от него.
	if not track.transform.is_equal_approx(Transform3D.IDENTITY):
		problems.append("корень трассы сдвинут или повёрнут (%s) — верните Transform в ноль" % track.transform.origin)

	# Тесные углы со склоном: скругление не длиннее 45 % соседних отрезков, на коротком отрезке
	# радиус выходит меньше половины дороги — внутренний край складывается; на ровном месте куски
	# лежат на одной высоте (безвредно), а на склоне складка — ступенька, машина в неё упирается.
	for corner in folded_corners(track):
		problems.append("угол у точки %d: скругление %.1f м меньше половины дороги (%.1f м) — внутренний край сложится; удлините соседние отрезки (сейчас короче %.0f м) или сделайте угол положе" % [
				corner["point"], corner["radius"], corner["half"], corner["need"]])

	# Подъёмы (по ходу гонки): круче MAX_SLOPE_DEG машина не заедет — пол для неё до 45°
	# (проверено автопилотом: 43° проезжает). Спуски не мешают: с гребня машина не взлетает.
	for steep in steep_slopes(track):
		problems.append("подъём круче %d° (%.0f° у отметки %.0f м) — машина не заедет; растяните участок или опустите точку" % [
				MAX_SLOPE_DEG, steep["deg"], steep["offset"]])

	if int(counts.get("коробка", 0)) == 0:
		problems.append("нет коробок предметов (маркеры группы item_box_spots)")

	var parts := PackedStringArray()
	for kind in counts:
		parts.append("%s: %d" % [kind, counts[kind]])
	var width := "%.1f м" % track.road_width
	if not is_equal_approx(track.min_road_width(), track.max_road_width()):
		width = "%.1f–%.1f м" % [track.min_road_width(), track.max_road_width()]
	var summary := "длина круга %.0f м, ширина дороги %s; %s; самый длинный пустой участок %.0f м" % [
			track.length, width, ", ".join(parts) if not parts.is_empty() else "объектов нет", max_gap]
	return {"problems": problems, "summary": summary, "max_gap": max_gap, "counts": counts}


## Углы ломаной со склоном рядом, где радиус скругления меньше половины дороги
## (как _rounded_corners_curve):
## [{point, radius, half, need — какой длины нужны соседние отрезки}].
static func folded_corners(track: Track) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var path := track.get_node_or_null(^"Path") as Path3D
	if path == null or path.curve == null or track.shape != Track.Shape.ROUNDED_CORNERS:
		return result
	var curve := path.curve
	var n := curve.point_count
	for i in n:
		if track.portal_gaps.has(i) or track.portal_gaps.has(posmod(i - 1, n)):
			continue
		var p := curve.get_point_position(i)
		var to_prev := curve.get_point_position(posmod(i - 1, n)) - p
		var to_next := curve.get_point_position((i + 1) % n) - p
		if to_prev.length_squared() < 1e-6 or to_next.length_squared() < 1e-6:
			continue
		if absf(to_prev.y) < 0.1 and absf(to_next.y) < 0.1:
			continue
		# Складывается только поворот в плане: подъём/спуск ширину не сужает.
		var flat_in := Vector3(-to_prev.x, 0.0, -to_prev.z)
		var flat_out := Vector3(to_next.x, 0.0, to_next.z)
		if flat_in.length_squared() < 1e-6 or flat_out.length_squared() < 1e-6:
			continue
		var turn_flat := flat_in.angle_to(flat_out)
		if turn_flat < deg_to_rad(20.0):
			continue
		var turn := (-to_prev.normalized()).angle_to(to_next.normalized())
		var t := minf(track.corner_radius * tan(turn * 0.5), minf(to_prev.length(), to_next.length()) * 0.45)
		var radius := t / tan(turn_flat * 0.5)
		var half := maxf(track.segment_width(posmod(i - 1, n)), track.segment_width(i)) * 0.5
		if radius < half:
			result.append({"point": i, "radius": radius, "half": half,
					"need": half * tan(turn_flat * 0.5) / 0.45})
	return result


## Все подъёмы (по ходу гонки) круче MAX_SLOPE_DEG: самая крутая точка каждого.
static func steep_slopes(track: Track) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var current := {}
	var d := 0.0
	while d < track.length:
		var deg := 0.0
		if not track.is_in_gap(d) and not track.is_in_gap(d + SLOPE_WINDOW):
			# Середина и края дороги (у края — 1 м внутрь): на повороте с подъёмом внутренний
			# край короче середины и круче её.
			var edge := maxf(track.road_half_width_at(d) - 1.0, 0.0)
			for lateral in [0.0, -edge, edge]:
				var a := track.get_point_at(d, lateral)
				var b := track.get_point_at(d + SLOPE_WINDOW, lateral)
				var slope := rad_to_deg(atan2(absf(b.y - a.y), maxf(Vector2(b.x - a.x, b.z - a.z).length(), 0.001)))
				if b.y > a.y and slope > deg:
					deg = slope
		if deg > MAX_SLOPE_DEG:
			if current.is_empty() or deg > current["deg"]:
				current = {"deg": deg, "offset": d}
		elif not current.is_empty():
			result.append(current)
			current = {}
		d += 1.0
	if not current.is_empty():
		result.append(current)
	return result


## Самый крутой участок дороги: {deg, offset, up} по окнам SLOPE_WINDOW м вдоль трассы.
static func steepest_slope(track: Track) -> Dictionary:
	var result := {"deg": 0.0, "offset": 0.0, "up": true}
	var d := 0.0
	while d < track.length:
		if not track.is_in_gap(d) and not track.is_in_gap(d + SLOPE_WINDOW):
			var a := track.get_point_at(d)
			var b := track.get_point_at(d + SLOPE_WINDOW)
			var run := Vector2(b.x - a.x, b.z - a.z).length()
			var deg := rad_to_deg(atan2(absf(b.y - a.y), maxf(run, 0.001)))
			if deg > result["deg"]:
				result = {"deg": deg, "offset": d, "up": b.y > a.y}
		d += 1.0
	return result


## Пересекаются ли «следы» объектов на земле (прямоугольники по коллизии с поворотом).
## Теорема о разделяющей оси: проверяются оси обоих прямоугольников.
static func footprints_overlap(a: Node3D, b: Node3D) -> bool:
	var rect_a := _footprint(a)
	var rect_b := _footprint(b)
	for axis in [rect_a[1], rect_a[2], rect_b[1], rect_b[2]]:
		var n: Vector2 = axis.normalized()
		var d := absf((rect_b[0] - rect_a[0]).dot(n))
		if d >= _projected_radius(rect_a, n) + _projected_radius(rect_b, n) - TOUCH_TOLERANCE:
			return false
	return true


## [центр, ось X * полуразмер, ось Z * полуразмер] на плоскости XZ.
static func _footprint(node: Node3D) -> Array[Vector2]:
	var half := TrackLayout.half_extents(node)
	var basis := node.global_basis.orthonormalized()
	var x := Vector2(basis.x.x, basis.x.z).normalized()
	var z := Vector2(basis.z.x, basis.z.z).normalized()
	return [Vector2(node.global_position.x, node.global_position.z), x * half.x, z * half.y]


static func _projected_radius(rect: Array[Vector2], axis: Vector2) -> float:
	var n := axis.normalized()
	return absf(rect[1].dot(n)) + absf(rect[2].dot(n))


static func kind_name(node: Node) -> String:
	if node.is_in_group(TrackLayout.RAMP_GROUP):
		return "трамплин"
	if node.is_in_group(TrackLayout.ITEM_BOX_GROUP):
		return "коробка"
	if node is ParryHazard:
		return "ограждение"
	if node is BoostPad:
		return "ускоритель"
	if node is MapZone:
		return ["лента", "горка", "лёд"][(node as MapZone).kind]
	if node is Portal:
		return "портал"
	if node is Reverser:
		return "разворот"
	if node is SnowTurret:
		return "турель"
	return "препятствие"
