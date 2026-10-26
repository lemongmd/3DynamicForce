extends SceneTree
## Ручная расстановка объектов на карте по списку (scripts/tools/layouts/<карта>.gd).
## Форма трассы — из инструмента переноса (c3_extract_track.gd), объекты — только отсюда:
## каждый поставлен вручную, по образцу оригинала, ровно (полосы, ряды, по трассе).
##
## Запуск:
##   godot --headless --path . -s res://scripts/tools/layout_map.gd -- map_b
## Узел Props карты очищается (кроме порталов разрыва), ставятся объекты из списка,
## затем проверка TrackCheck; сцена перезаписывается.
##
## Запись списка — массив: [вид, расстояние от старта (м), смещение вбок (м, + вправо), …]:
##   ["boxes", d, [l1, l2, …]]            ряд коробок предметов
##   ["pads", d, l, count, kind, step?]   ускорители подряд вдоль трассы (kind: 0 +, 1 ++, 2 MAX;
##                                        шаг 3 м, на дуге — больше)
##   ["ramp", d, l]                       наш трамплин
##   [<проп>, d, l, rot]                  rot — поворот относительно трассы, градусы
##                                        (barrel, tire, crate, gravel, ring, crab, crab_parry,
##                                        wet, wet_parry, barrier, block; barrier/block/crab при 0 —
##                                        поперёк дороги)
##   ["ice", d, l, across, along]         лёд (цвет — TINT списка)
##   ["mud", d, along, l?, across?]       грязь (машина буксует): без l и across — на всю
##                                        ширину дороги, иначе пятно across м со смещением l
##   ["conveyor", d, l, across, along, dir]  лента: dir 1 — по ходу гонки, −1 — против
##   ["slider", d, along]                 аквагорка во всю ширину
##   ["turret", d, side]                  снежная турель на стене (side 1 — справа, −1 — слева)
##   ["balls", d]                         цирковые шары, ездят поперёк дороги
##   ["ghost", d]                         призрак («Хэллоуин»), плавает поперёк дороги
##                                        (pumpkin, pumpkin_parry, tombstone — тыквы и надгробие,
##                                        как обычные пропы)
##   ["music", d, "имя"]                  триггер музыки во всю ширину
## DECOR — окружение вручную: ["decor", вид, d, l, rot] или ["decor_row", вид, от, до, шаг,
## сторона ±1, дальше?, разброс?] (по середине полосы окружения; «дальше» — ещё столько метров
## от стены, «разброс» — до стольких метров вбок и вдоль, от места: ряд не по линейке) или
## ["wall_row", вид, от, до, шаг, сторона ±1] (на верху стены — тыквы-фонари); виды —
## DECOR_SCENES. SURROUND — ширина полосы окружения за стенами, м.
## Необязательные константы списка: PATH — ломаная трассы, поправленная вручную (Vector2 x, z
## в метрах или Vector3 x, высота, z — подъёмы и спуски), TINT — цвет льда, KEEP_DECOR — оставить декор из переноса (true / false / массив начал
## имён узлов, которые оставить).

const LAYOUTS_DIR := "res://scripts/tools/layouts/"
const TRACKS_DIR := "res://scenes/tracks/"
const SCENES := {
	"barrel": "res://scenes/props/barrel.tscn",
	"tire": "res://scenes/props/tire.tscn",
	"crate": "res://scenes/props/site_crate.tscn",
	"gravel": "res://scenes/props/gravel.tscn",
	"ring": "res://scenes/props/life_ring.tscn",
	"crab": "res://scenes/props/crab.tscn",
	"crab_parry": "res://scenes/hazards/crab_parry.tscn",
	"wet": "res://scenes/props/wet_floor.tscn",
	"wet_parry": "res://scenes/hazards/wet_floor_parry.tscn",
	"danger": "res://scenes/props/danger_sign.tscn",
	"danger_parry": "res://scenes/hazards/danger_sign_parry.tscn",
	"barrier": "res://scenes/hazards/barrier_parry.tscn",
	"block": "res://scenes/props/barrier_block.tscn",
	"ramp": "res://scenes/props/ramp.tscn",
	"pad": "res://scenes/objects/boost_pad.tscn",
	"zone": "res://scenes/objects/map_zone.tscn",
	"turret": "res://scenes/objects/snow_turret.tscn",
	"balls": "res://scenes/hazards/circus_balls.tscn",
	"music": "res://scenes/objects/music_trigger.tscn",
	"pumpkin": "res://scenes/props/pumpkin.tscn",
	"tombstone": "res://scenes/props/tombstone.tscn",
	"pumpkin_parry": "res://scenes/hazards/pumpkin_parry.tscn",
	"ghost": "res://scenes/hazards/ghost.tscn",
}
## Декор окружения (ставится в узел Decor, проверки и автопилот его не видят).
const DECOR_SCENES := {
	"palm": "res://scenes/decor/palm.tscn",
	"fence": "res://scenes/decor/fence.tscn",
	"crab": "res://scenes/props/crab.tscn",
	"ring": "res://scenes/props/life_ring.tscn",
	"tire": "res://scenes/props/tire.tscn",
	"crate": "res://scenes/props/site_crate.tscn",
	"gravel": "res://scenes/props/gravel.tscn",
	"tree": "res://scenes/decor/autumn_tree.tscn",
	"grave": "res://scenes/decor/grave.tscn",
	"lamp": "res://scenes/decor/pumpkin_lamp.tscn",
}
const PAD_STEP := 3.0
const ITEM_BOX_GROUP := &"item_box_spots"

var _counters := {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var map_name := OS.get_cmdline_user_args()[0]
	var layout: GDScript = load(LAYOUTS_DIR + map_name + ".gd")
	var scene_path := TRACKS_DIR + map_name + ".tscn"
	var track := (load(scene_path) as PackedScene).instantiate() as Track
	root.add_child(track)
	await process_frame
	var constants := layout.get_script_constant_map()
	# PATH — ломаная, поправленная вручную (точки x, z в метрах или x, высота, z; точка 0 — старт).
	if constants.has("PATH"):
		var curve := Curve3D.new()
		curve.bake_interval = 0.5
		for p: Variant in constants["PATH"]:
			curve.add_point(p if p is Vector3 else Vector3(p.x, 0.0, p.y))
		curve.closed = true
		(track.get_node("Path") as Path3D).curve = curve
		track.rebuild()
	var props := track.get_node("Props")
	for child in props.get_children():
		if not child is Portal:
			props.remove_child(child)
			child.free()
	# KEEP_DECOR: true — декор из переноса как есть, false — убрать, массив — оставить только
	# узлы, чьё имя начинается с этих слов (например, дом и забор, но не кучи щебня).
	var keep_decor = constants.get("KEEP_DECOR", true)
	# Декор, поставленный этим инструментом в прошлый раз (DECOR), — заново.
	if track.has_node(^"Decor"):
		for child in track.get_node("Decor").get_children():
			if child.has_meta(&"layout_decor"):
				child.get_parent().remove_child(child)
				child.free()
	if track.has_node(^"Decor") and not (keep_decor is bool and keep_decor):
		for child in track.get_node("Decor").get_children():
			var keep := keep_decor is Array and (keep_decor as Array).any(
					func(prefix: String) -> bool: return child.name.begins_with(prefix))
			if not keep:
				child.get_parent().remove_child(child)
				child.free()
	# DECOR_PEAKS: {начало имени узла декора: высота} — плоская картинка-вид сверху
	# становится объёмной горой (камни-горы Снежной).
	var peaks: Dictionary = constants.get("DECOR_PEAKS", {})
	if track.has_node(^"Decor"):
		for child in track.get_node("Decor").get_children():
			for prefix: String in peaks:
				if child.name.begins_with(prefix) and child.has_node(^"Visual"):
					child.get_node(^"Visual").set("peak", float(peaks[prefix]))
	# SURROUND — полоса окружения за стенами (песок, плитка, бетон), м.
	if constants.has("SURROUND"):
		track.surround_width = float(constants["SURROUND"])
		track.rebuild()
	var tint: Color = constants.get("TINT", Color.WHITE)
	for item: Array in constants["ITEMS"]:
		_place(track, props, item, tint)
	# DECOR — окружение вручную: ["decor", вид, d, l, rot] или ["decor_row", вид, от, до, шаг, сторона].
	var decor := track.get_node_or_null(^"Decor")
	if decor == null:
		decor = Node3D.new()
		decor.name = "Decor"
		track.add_child(decor)
		decor.owner = track
	var skipped := 0
	for item: Array in constants.get("DECOR", []):
		if item[0] == "decor":
			skipped += 0 if _place_decor(track, decor, item[1], float(item[2]), float(item[3]),
					float(item[4]) if item.size() > 4 else 0.0) else 1
		elif item[0] == "wall_row":
			var d := float(item[2])
			while d <= float(item[3]):
				skipped += 0 if _place_on_wall(track, decor, item[1], d, float(item[5])) else 1
				d += float(item[4])
		else:
			var side := float(item[5])
			var further := float(item[6]) if item.size() > 6 else 0.0
			var spread := float(item[7]) if item.size() > 7 else 0.0
			var d := float(item[2])
			var index := 0
			while d <= float(item[3]):
				# Разброс — от номера в ряду (одинаковый при каждом запуске).
				var jitter := Vector2(sin(index * 12.9898 + side * 3.1), cos(index * 78.233 + side * 1.7)) * spread
				var lateral := side * (track.road_width * 0.5 + track.wall_width + track.surround_width * 0.5
						+ further + absf(jitter.x))
				skipped += 0 if _place_decor(track, decor, item[1], d + jitter.y, lateral, 0.0) else 1
				d += float(item[4])
				index += 1
	if skipped > 0:
		print("  декор: не поставлено %d (задел бы дорогу или в разрыве)" % skipped)

	var check := TrackCheck.run(track)
	print("%s: %s" % [map_name, check["summary"]])
	for problem in check["problems"]:
		print("  ! ", problem)
	root.remove_child(track)
	var packed := PackedScene.new()
	var err := packed.pack(track)
	if err == OK:
		err = ResourceSaver.save(packed, scene_path)
	print("сохранено %s: %s" % [scene_path, error_string(err)])
	track.free()
	quit(0 if err == OK and (check["problems"] as PackedStringArray).is_empty() else 1)


func _place(track: Track, props: Node, item: Array, tint: Color) -> void:
	var kind: String = item[0]
	var d := float(item[1])
	var yaw := _track_yaw(track, d)
	match kind:
		"boxes":
			for lateral in item[2]:
				var marker := Marker3D.new()
				marker.add_to_group(ITEM_BOX_GROUP, true)
				_add(track, props, marker, "ItemBoxSpot", d, float(lateral), yaw)
		"pads":
			for k in int(item[3]):
				var pad := _scene("pad")
				pad.set("kind", int(item[4]))
				# Шаг вдоль трассы — 3 м (вплотную); на дуге можно больше (6-й элемент).
				var at := d + k * (float(item[5]) if item.size() > 5 else PAD_STEP)
				_add(track, props, pad, "BoostPad", at, float(item[2]), _track_yaw(track, at))
		"ice":
			var ice := _scene("zone") as MapZone
			ice.kind = MapZone.Kind.ICE
			ice.tint = tint
			ice.size = Vector2(float(item[3]), float(item[4]))
			_add(track, props, ice, "Ice", d, float(item[2]), yaw)
		"mud":
			var mud := _scene("zone") as MapZone
			mud.kind = MapZone.Kind.MUD
			var mud_lateral := float(item[3]) if item.size() > 4 else 0.0
			var across := float(item[4]) if item.size() > 4 else track.road_half_width_at(d) * 2.0
			mud.size = Vector2(across, float(item[2]))
			_add(track, props, mud, "Mud", d, mud_lateral, yaw)
		"conveyor":
			var belt := _scene("zone") as MapZone
			belt.kind = MapZone.Kind.CONVEYOR
			# Лента тянет по своей оси +X: по ходу гонки — поворот на +90°.
			belt.size = Vector2(float(item[4]), float(item[3]))
			_add(track, props, belt, "Conveyor", d, float(item[2]), yaw + PI * 0.5 * float(item[5]))
		"slider":
			var slider := _scene("zone") as MapZone
			slider.kind = MapZone.Kind.AQUA_SLIDER
			slider.size = Vector2(track.road_half_width_at(d) * 2.0, float(item[2]))
			_add(track, props, slider, "AquaSlider", d, 0.0, yaw)
		"turret":
			var side := float(item[2])
			var turret := _scene("turret")
			# Стреляет по оси +X — через дорогу к другой стене.
			_add(track, props, turret, "SnowTurret", d,
					side * (track.road_half_width_at(d) + track.wall_width * 0.5), yaw + (PI if side > 0.0 else 0.0))
		"balls":
			var balls := _scene("balls") as CircusBalls
			balls.sweep = track.road_half_width_at(d) - 2.0
			_add(track, props, balls, "CircusBalls", d, 0.0, yaw)
		"ghost":
			var ghost := _scene("ghost") as Ghost
			ghost.sweep = track.road_half_width_at(d) - 1.6
			_add(track, props, ghost, "Ghost", d, 0.0, yaw)
		"music":
			var trigger := _scene("music") as MusicTrigger
			trigger.music = load("res://assets/original/music/%s.ogg" % item[2])
			trigger.scale = Vector3(track.road_half_width_at(d), 1.0, 1.0)
			_add(track, props, trigger, "MusicTrigger", d, 0.0, yaw)
		"ramp":
			_add(track, props, _scene("ramp"), "Ramp", d, float(item[2]), yaw)
		_:
			var rot := deg_to_rad(float(item[3])) if item.size() > 3 else 0.0
			_add(track, props, _scene(kind), kind.capitalize().replace(" ", ""), d, float(item[2]), yaw + rot)


## Декор окружения: на своём месте, если не задевает дорогу (на тесных поворотах полоса
## одного участка ложится на дорогу другого) и не в разрыве трассы.
func _place_decor(track: Track, decor: Node, kind: String, d: float, lateral: float, rot_deg: float) -> bool:
	if track.is_in_gap(d):
		return false
	var at := track.get_point_at(d, lateral)
	var where := TrackLayout.locate(track, at)
	if absf(float(where["lateral"])) < track.outline_half_width_at(float(where["offset"])) + track.wall_width + 1.5:
		return false
	var node := (load(DECOR_SCENES[kind]) as PackedScene).instantiate() as Node3D
	_counters["decor_" + kind] = int(_counters.get("decor_" + kind, 0)) + 1
	node.name = "%s%d" % [kind.capitalize().replace(" ", ""), _counters["decor_" + kind]]
	node.set_meta(&"layout_decor", true)
	decor.add_child(node)
	node.owner = track
	node.position = at
	node.rotation.y = _track_yaw(track, d) + deg_to_rad(rot_deg)
	return true


## Декор на верху стены (тыквы-фонари вдоль трассы): посередине стены, на её высоте.
func _place_on_wall(track: Track, decor: Node, kind: String, d: float, side: float) -> bool:
	if track.is_in_gap(d) or not track.walls:
		return false
	var at := track.get_point_at(d, side * (track.outline_half_width_at(d) + track.wall_width * 0.5))
	at.y += track.wall_height
	var node := (load(DECOR_SCENES[kind]) as PackedScene).instantiate() as Node3D
	_counters["decor_" + kind] = int(_counters.get("decor_" + kind, 0)) + 1
	node.name = "%s%d" % [kind.capitalize().replace(" ", ""), _counters["decor_" + kind]]
	node.set_meta(&"layout_decor", true)
	node.set_meta(&"layout_on_wall", true)
	decor.add_child(node)
	node.owner = track
	node.position = at
	node.rotation.y = _track_yaw(track, d)
	return true


func _scene(kind: String) -> Node3D:
	return (load(SCENES[kind]) as PackedScene).instantiate() as Node3D


func _add(track: Track, props: Node, node: Node3D, base: String, d: float, lateral: float, yaw: float) -> void:
	_counters[base] = int(_counters.get(base, 0)) + 1
	node.name = "%s%d" % [base, _counters[base]]
	props.add_child(node)
	node.owner = track
	node.position = track.get_point_at(d, lateral)
	# На прямых по осям поворот ровно кратен 45° (тайлы оригинала); на дугах — по трассе.
	var snapped := snappedf(yaw, PI * 0.25)
	node.rotation.y = snapped if absf(wrapf(yaw - snapped, -PI, PI)) < deg_to_rad(4.0) else yaw
	# На подъёмах и спусках — по склону (иначе половина объекта в дороге).
	node.basis = TrackLayout.road_tilt(track, d) * node.basis


## Поворот вокруг Y, при котором −Z смотрит по ходу гонки.
func _track_yaw(track: Track, offset: float) -> float:
	var dir := track.get_direction_at(offset)
	return atan2(-dir.x, -dir.z)
