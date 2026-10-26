class_name TrackLayout
extends RefCounted
## Ровная расстановка объектов на трассе (редактор карт, проверки).
##
## Положение объекта считается в координатах трассы: offset — расстояние от старта
## вдоль центральной линии, lateral — смещение вбок (плюс — вправо по ходу гонки).
## «Ровно» = offset кратен шагу, lateral — на полосе (шаг road_width / LANE_DIVISIONS),
## поворот — по направлению трассы плюс 0/90/180/270°, объект целиком на дороге.

## Полос поперёк дороги (13.5 м -> шаг 2.25 м).
const LANE_DIVISIONS := 6
## Зазор между объектом и стеной, м.
const WALL_CLEARANCE := 0.3
## Полуразмер объекта без коллизии (маркер коробки), м.
const DEFAULT_HALF_SIZE := 1.0
## Группы, по которым узнаются объекты.
const ITEM_BOX_GROUP := &"item_box_spots"
const RAMP_GROUP := &"ramps"


static func lane_step(track: Track) -> float:
	return track.road_width / LANE_DIVISIONS


## Где объект на трассе: {"offset", "lateral", "distance"} (distance — до центральной линии).
static func locate(track: Track, global_pos: Vector3) -> Dictionary:
	var result := track.project(global_pos)
	var offset := float(result["offset"])
	var lateral := (global_pos - track.get_point_at(offset)).dot(track_right(track, offset))
	return {"offset": offset, "lateral": lateral, "distance": float(result["distance"])}


## Вправо по ходу гонки в точке offset (в плоскости земли).
static func track_right(track: Track, offset: float) -> Vector3:
	var dir := track.get_direction_at(offset)
	dir.y = 0.0
	return dir.cross(Vector3.UP).normalized()


## Поворот вокруг Y, при котором −Z объекта смотрит по ходу гонки.
static func track_yaw(track: Track, offset: float) -> float:
	var dir := track.get_direction_at(offset)
	return atan2(-dir.x, -dir.z)


## Поворот объекта относительно трассы, округлённый до 90° (0 — по ходу гонки).
static func relative_yaw(track: Track, global_yaw: float, offset: float) -> float:
	return snappedf(wrapf(global_yaw - track_yaw(track, offset), -PI, PI), PI * 0.5)


## Полуразмер объекта по его осям X и Z (по коллизии, с учётом масштаба), м.
static func half_extents(node: Node3D) -> Vector2:
	var box := AABB()
	var found := false
	for child in node.get_children():
		var shape_node := child as CollisionShape3D
		if shape_node == null or shape_node.shape == null:
			continue
		var local := AABB()
		if shape_node.shape is BoxShape3D:
			var size := (shape_node.shape as BoxShape3D).size
			local = AABB(-size * 0.5, size)
		elif shape_node.shape is CylinderShape3D:
			var cylinder := shape_node.shape as CylinderShape3D
			var extent := Vector3(cylinder.radius, cylinder.height * 0.5, cylinder.radius)
			local = AABB(-extent, extent * 2.0)
		elif shape_node.shape is ConvexPolygonShape3D:
			var points := (shape_node.shape as ConvexPolygonShape3D).points
			if points.is_empty():
				continue
			local = AABB(points[0], Vector3.ZERO)
			for p in points:
				local = local.expand(p)
		else:
			continue
		local = shape_node.transform * local
		box = local if not found else box.merge(local)
		found = true
	if not found:
		return Vector2(DEFAULT_HALF_SIZE, DEFAULT_HALF_SIZE)
	var scale := node.scale.abs()
	var half_x := maxf(absf(box.position.x), absf(box.end.x)) * scale.x
	var half_z := maxf(absf(box.position.z), absf(box.end.z)) * scale.z
	return Vector2(half_x, half_z)


## Полуширина объекта поперёк дороги при повороте relative относительно трассы.
static func half_width_across(node: Node3D, relative: float) -> float:
	var half := half_extents(node)
	return absf(cos(relative)) * half.x + absf(sin(relative)) * half.y


## Ровный глобальный трансформ для объекта node, который стоит в global_pos с поворотом
## global_yaw. along_step — шаг вдоль трассы (0 — не округлять), snap_lanes — на полосы.
## Масштаб берётся из node.scale (узел может быть ещё не в дереве).
static func snapped_transform(track: Track, node: Node3D, global_pos: Vector3, global_yaw: float,
		along_step: float = 1.0, snap_lanes: bool = true) -> Transform3D:
	var where := locate(track, global_pos)
	var offset := float(where["offset"])
	if along_step > 0.0:
		offset = snappedf(offset, along_step)
	var relative := relative_yaw(track, global_yaw, offset)
	var limit := maxf(track.road_half_width_at(offset) - half_width_across(node, relative) - WALL_CLEARANCE, 0.0)
	var lateral := float(where["lateral"])
	if snap_lanes:
		var lane := lane_step(track)
		var lane_limit := floorf(limit / lane) * lane
		lateral = clampf(snappedf(lateral, lane), -lane_limit, lane_limit)
	else:
		lateral = clampf(lateral, -limit, limit)
	var basis := road_tilt(track, offset) * Basis(Vector3.UP, track_yaw(track, offset) + relative) 			* Basis.from_scale(node.scale)
	return Transform3D(basis, track.get_point_at(offset, lateral))


## Наклон объекта по склону дороги: его верх — нормаль дороги в offset (поперёк дорога не
## наклонена). Без него на подъёме задняя половина объекта уходила под асфальт, а с ней
## свечи и пятна света. На ровном месте — без поворота (сцены ровных карт не меняются).
static func road_tilt(track: Track, offset: float) -> Basis:
	var dir := track.get_direction_at(offset)
	var right := dir.cross(Vector3.UP)
	if right.length_squared() < 1e-8:
		return Basis.IDENTITY
	var up := right.normalized().cross(dir).normalized()
	if up.angle_to(Vector3.UP) < deg_to_rad(0.5):
		return Basis.IDENTITY
	return Basis(Quaternion(Vector3.UP, up))


## Трансформ для декора на стене (знак): на середине стены с той стороны, где global_pos.
static func wall_transform(track: Track, node: Node3D, global_pos: Vector3, along_step: float = 1.0) -> Transform3D:
	var where := locate(track, global_pos)
	var offset := float(where["offset"])
	if along_step > 0.0:
		offset = snappedf(offset, along_step)
	var side := 1.0 if float(where["lateral"]) >= 0.0 else -1.0
	var lateral := side * (track.road_half_width_at(offset) + track.wall_width * 0.5)
	var basis := Basis(Vector3.UP, track_yaw(track, offset)) * Basis.from_scale(node.scale)
	return Transform3D(basis, track.get_point_at(offset, lateral))


## Игровой объект на дороге (а не декор): твёрдое препятствие, опасность, ускоритель,
## трамплин, место коробки.
static func is_gameplay(node: Node) -> bool:
	return node is StaticBody3D or node is ParryHazard or node is BoostPad \
			or node is MapZone or node is Portal or node is Reverser or node.is_in_group(ITEM_BOX_GROUP)


## Объект стоит на стене намеренно (снежная турель стреляет поперёк дороги).
static func is_wall_object(node: Node) -> bool:
	return node is SnowTurret


## Плоская зона на дороге (лента, горка, лёд): поверх неё можно ставить другие объекты.
static func is_surface(node: Node) -> bool:
	return node is MapZone
