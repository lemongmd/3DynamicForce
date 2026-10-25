extends SceneTree
## Перенос трассы оригинала (уровень Construct 3) в сцену Track ремейка.
##
## Запуск из корня проекта:
##   godot --headless --path . -s res://scripts/tools/c3/c3_extract_track.gd -- "DF C3 project" MapB res://scenes/tracks/map_b.tscn auto
##   4-й аргумент — материал фона или «auto» (фон и стены — по таблице MAP_STYLE).
##   Если сцена уже есть, нужен --force в конце (карту могли поправить в редакторе карт).
##
## Как работает:
##   1. Тайлмапы уровня (их может быть несколько) -> сетка проходимости: тайл без коллизии —
##      дорога, с треугольной коллизией (диагональ) — полупроходим, кирпич — стена; пустая
##      клетка в оригинале тоже проезжая (фон — только картинка), её берём, если по тайлам
##      пути нет (поле «Стройки»), вместе с порталами (что короче).
##   2. Расстояние до ближайшей стены для каждой клетки.
##   3. Путь Дейкстры от Start через SubLapTrigger 1..N обратно к Start; цена шага растёт
##      у стен, поэтому путь идёт по середине дороги. Нет пути и по пустым клеткам — через
##      портал (Portal -> To): в этом месте у трассы разрыв (Track.portal_gaps).
##   4. Сглаживание + упрощение (Дуглас — Пекер) -> точки ломаной Path3D
##      (Track со скруглёнными углами), точка 0 — центр объекта Start.
##   5. Ширина дороги — медиана ширины вдоль пути.
##   6. Почти осевые отрезки выпрямляются (_straighten).
##   7. Объекты — ровно (полосы road_width / LANE_DIVISIONS, поворот по трассе кратно 90°,
##      ряды, без наложений; не влезает — не ставится, на ряд — не больше половины дороги):
##      бочки, ограждения, ускорители, коробки, цирковые шары, крабы, ящики, шины, круги,
##      таблички «мокрый пол», лёд, конвейеры, аквагорки, триггер музыки. Снежные турели —
##      на стене, стреляют поперёк дороги. Порталы — на концах разрыва.
##   8. Декор оригинала за дорогой (заборы, пальмы, кран, дом, камни) — на своих местах,
##      если не задевает нашу дорогу со стенами (на эстакаде декора нет: стоять не на чем).
##   Не переносятся: развороты Reverser (зигзаг и тупики не ложатся на ленту трассы),
##   порталы-пасхалки вне маршрута, ачивки, уровни высоты ZTrigger/ZBlock, картинки-подсветки.
## Масштаб: 8 px оригинала = 1 м; x -> x, y -> z; угол a -> поворот вокруг Y на -a.

const PX_PER_M := 8.0
const TRACK_SCRIPT := preload("res://scripts/track/track.gd")
const PROPS := {
	"Barrel": "res://scenes/props/barrel.tscn",
	"BarrierParry": "res://scenes/hazards/barrier_parry.tscn",
	"BarrierBlock": "res://scenes/props/barrier_block.tscn",
	"BoostPad": "res://scenes/objects/boost_pad.tscn",
	"CircusBalls": "res://scenes/hazards/circus_balls.tscn",
}
const ZONE_SCENE := "res://scenes/objects/map_zone.tscn"
## Наш трамплин — заполняет длинные пустые прямые.
const RAMP_SCENE := "res://scenes/props/ramp.tscn"
const ZONE_KINDS := {"Conveyor": MapZone.Kind.CONVEYOR, "AquaSlider": MapZone.Kind.AQUA_SLIDER, "Ice": MapZone.Kind.ICE}
const TURRET_SCENE := "res://scenes/objects/snow_turret.tscn"
const PORTAL_SCENE := "res://scenes/objects/portal.tscn"
const MUSIC_TRIGGER_SCENE := "res://scenes/objects/music_trigger.tscn"
const PARRY_HAZARD_SCRIPT := "res://scripts/hazards/parry_hazard.gd"
const BOX_VISUAL_SCRIPT := "res://scripts/props/c3_box_visual.gd"
## Коробки «3D shape» оригинала: папка картинок; solid — твёрдое препятствие на дороге,
## parry — парируемая опасность (звуки удара), decor — только декор за дорогой.
const SHAPES := {
	"Crabby": {"folder": "levelobj", "role": "solid"},
	"CrabbyParry": {"folder": "levelobj", "role": "parry", "sounds": ["stocksplat", "stockpain"]},
	"MapBox": {"folder": "levelobj", "role": "solid"},
	"MapScheben": {"folder": "levelobj", "role": "solid"},
	"MapPokrishka": {"folder": "levelobj", "role": "solid"},
	"MapLifeRing": {"folder": "levelobj", "role": "solid"},
	"MapHouseWall": {"folder": "levelobj", "role": "decor"},
	"MapHouseWindow": {"folder": "levelobj", "role": "decor"},
	"MapFence": {"folder": "levelobj", "role": "decor"},
	"MapKranBase": {"folder": "levelobj", "role": "decor"},
	"MapKranMetal": {"folder": "levelobj", "role": "decor"},
	"BeachDecor": {"folder": "levelobj", "role": "decor"},
}
## Плоские картинки оригинала (спрайты в 3D-слое): высота картинки над землёй, м.
const SPRITES := {
	"MapDecorWetFloor": {"role": "solid", "height": 1.0, "collision_height": 1.5},
	"MapDecorWetFloorParry": {"role": "parry", "height": 1.0, "collision_height": 1.5,
			"sounds": ["stocksplat", "stockpain"]},
	"MapDecor": {"role": "decor", "height": 0.05},
}
## Колонна оригинала (имя с кириллической «С»): отдельно не ставится — по её глубине
## трасса становится эстакадой с опорами support_scene, расставленными с ровным шагом.
const COLUMN_TYPE := "Сolumn"
const COLUMN_SCENE := "res://scenes/props/column.tscn"
## Размер пропа в сцене, px оригинала (для масштаба экземпляров другого размера).
const PROP_BASE_SIZE := {
	"Barrel": Vector2(16, 16),
	"BarrierParry": Vector2(48, 8),
	"BarrierBlock": Vector2(48, 8),
	"BoostPad": Vector2(24, 24),
}
## Анимация ускорителя оригинала -> вид BoostPad.
const BOOST_KINDS := {"PlusSpeed": 0, "SuperSpeed": 1, "MaxSpeed": 2}
## Места коробок предметов (ItemBox оригинала) — маркеры для Race.
const ITEM_BOX_GROUP := &"item_box_spots"
const ROAD_MATERIAL := "res://assets/materials/road.tres"
const START_LINE_MATERIAL := "res://assets/materials/checker.tres"
const START_GATE_SCENE := "res://scenes/props/start_gate.tscn"
## Фон и стены карт: стена — тайл оригинала, который чаще всего граничит с дорогой.
const MAP_STYLE := {
	"MapA": {"background": "background_acid", "wall": "wall"},
	"MapB": {"background": "background_snow", "wall": "wall_snow"},
	"MapD": {"background": "background_water", "wall": "wall_sand"},
	"MapE": {"background": "background_dirt", "wall": "wall"},
	"MapF": {"background": "background_oil", "wall": "wall_concrete"},
	"MapG": {"background": "background_water", "wall": "wall_pool"},
}
## Музыка карт оригинала (LevelS: через 0.4 с после старта).
const MAP_MUSIC := {"MapA": "ghosttown", "MapB": "sylvaniacastle", "MapC": "circusmusic",
		"MapD": "dragonvalley", "MapE": "jojo", "MapF": "lolizoneact2", "MapG": "junglerush"}
## Упрощение ломаной: допустимое отклонение, px.
const SIMPLIFY_EPSILON_PX := 14.0
## Отрезки ломаной, отклонённые от оси меньше чем на столько градусов, выпрямляются.
const STRAIGHTEN_DEG := 15.0
## Игровые объекты ставятся на полосы: шаг поперёк дороги = road_width / LANE_DIVISIONS.
const LANE_DIVISIONS := 6
## Объекты ближе этого вдоль трассы (м) и на разных полосах — один ряд поперёк дороги.
const ROW_TOLERANCE := 2.0
## Коробки предметов в ряду — через столько метров.
const ITEM_BOX_SPACING := 4.0
## Коробки оригинала ближе этого друг к другу (м) — одна группа (ряд).
const BOX_GROUP_DISTANCE := 6.0
## Ускоритель — плитка PAD_SIZE × PAD_SIZE, м (тайл оригинала 24 px).
const PAD_SIZE := 3.0
## Цена шага по пустой клетке (фон оригинала проезжий, но путь по тайлам дороги лучше).
const EMPTY_COST := 1.5
## Твёрдые препятствия и опасности в окне ±DENSITY_WINDOW м занимают не больше
## DENSITY_MAX доли ширины дороги — проезд остаётся.
const DENSITY_WINDOW := 6.0
const DENSITY_MAX := 0.5
## Возле ленты (м по ходу и против хода от её краёв) твёрдых препятствий нет.
const CONVEYOR_CLEARANCE := 6.0
## Портал: вход — за столько метров до разрыва, выход — через столько после.
const PORTAL_IN_OFFSET := 2.0
const PORTAL_OUT_OFFSET := 2.5

var _cols := 0
var _rows := 0
var _tile := 24
var _tiles := PackedInt32Array()       # тайл клетки (-1 — пусто), все тайлмапы вместе
var _cost_strict := PackedFloat32Array()  # 0 — стена (и пусто), иначе множитель цены шага
var _cost_open := PackedFloat32Array()    # то же, пустые клетки проезжие
var _dist_strict := PackedFloat32Array()  # расстояние до стены, клеток
var _dist_open := PackedFloat32Array()
var _reachable := PackedByteArray()    # 1 — клетка, куда в оригинале можно доехать от старта
var _portal_links := {}                # клетка входа портала -> клетка выхода


func _initialize() -> void:
	# Трасса строится в дереве сцены, а оно готово только после _initialize.
	_run.call_deferred()


func _run() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() < 3:
		push_error("Аргументы: <папка проекта C3> <уровень> <res://сцена.tscn> [res://материал_фона.tres | auto] [--force]")
		quit(1)
		return
	var c3_dir: String = a[0]
	var layout_name: String = a[1]
	var out_path: String = a[2]
	var background_arg := a[3] if a.size() > 3 and not a[3].begins_with("--") else "auto"
	# Карту после переноса правят в редакторе карт — не затирать её молча.
	if ResourceLoader.exists(out_path) and not a.has("--force"):
		push_error("%s уже есть (её могли править в редакторе). Перезаписать: добавь --force в конце." % out_path)
		quit(1)
		return
	var style: Dictionary = MAP_STYLE.get(layout_name, {"background": "background_water", "wall": "wall"})
	var background_path := background_arg if background_arg != "auto" \
			else "res://assets/materials/%s.tres" % style["background"]
	var wall_path := "res://assets/materials/%s.tres" % style["wall"]

	var data = JSON.parse_string(FileAccess.get_file_as_string("%s/layouts/%s.json" % [c3_dir, layout_name]))
	var instances: Array = []
	for layer in data["layers"]:
		_collect(layer, instances)
	var by_uid := {}
	for inst in instances:
		if inst.has("uid"):
			by_uid[int(inst["uid"])] = inst

	var tilemaps := instances.filter(func(i): return i["type"] == "Tilemap")
	if tilemaps.is_empty():
		push_error("В уровне нет Tilemap")
		quit(1)
		return
	_build_grid(tilemaps, _tile_costs(c3_dir))
	_dist_strict = _build_distance(_cost_strict)
	_dist_open = _build_distance(_cost_open)

	# Чекпоинты по порядку: Start, затем SubLapTrigger по SetTo.
	var start = _find_first(instances, "Start")
	var sublaps: Array = instances.filter(func(i): return i["type"] == "SubLapTrigger")
	sublaps.sort_custom(func(x, y): return int(x["instanceVariables"]["SetTo"]) < int(y["instanceVariables"]["SetTo"]))
	var checkpoints: Array[Vector2] = [_center_px(start)]
	for s in sublaps:
		checkpoints.append(_center_px(s))
	_reachable = _flood(_nearest_open(_px_to_cell(checkpoints[0]), _cost_open))
	# Порталы: клетка входа -> клетка выхода (парный портал по UID).
	for inst in instances:
		if inst["type"] != "Portal":
			continue
		var to := int(inst["instanceVariables"].get("To", 0))
		if to == 0 or not by_uid.has(to):
			continue
		var entry := _nearest_open(_px_to_cell(_center_px(inst)), _cost_open)
		var exit := _nearest_open(_px_to_cell(_center_px(by_uid[to])), _cost_open)
		_portal_links[entry.y * _cols + entry.x] = exit

	var cells: Array[Vector2i] = []
	for i in checkpoints.size():
		var segment: Array[Vector2i] = []
		# Сначала только по тайлам дороги, потом и по пустым клеткам с порталами (что короче).
		for mode in 2:
			var cost := _cost_strict if mode == 0 else _cost_open
			var from := _nearest_open(_px_to_cell(checkpoints[i]), cost)
			var to := _nearest_open(_px_to_cell(checkpoints[(i + 1) % checkpoints.size()]), cost)
			segment = _dijkstra(from, to, cost, _dist_strict if mode == 0 else _dist_open, mode == 1)
			if not segment.is_empty():
				break
		if segment.is_empty():
			push_error("Нет пути между чекпоинтами %d и %d" % [i, (i + 1) % checkpoints.size()])
			quit(1)
			return
		if not cells.is_empty():
			segment.remove_at(0)
		cells.append_array(segment)
	cells.remove_at(cells.size() - 1)  # последняя клетка — снова Start

	# Прыжки через порталы — соседние клетки пути, которые не рядом.
	var jumps: Array[int] = []
	for i in cells.size():
		if Vector2(cells[i]).distance_to(Vector2(cells[(i + 1) % cells.size()])) > 1.5:
			jumps.append(i)

	var points: Array[Vector2] = []
	for c in cells:
		points.append((Vector2(c) + Vector2(0.5, 0.5)) * _tile)
	# Ширина дороги — медиана поперечных сечений по тайлам дороги (не через порталы).
	var widths := PackedFloat32Array()
	for i in points.size():
		var near_jump := jumps.any(func(j: int) -> bool: return absi(i - j) <= 2 or absi(i - j - 1) <= 2)
		var c := _px_to_cell(points[i])
		if near_jump or _cost_strict[c.y * _cols + c.x] == 0.0:
			continue
		var dir := (points[(i + 2) % points.size()] - points[posmod(i - 2, points.size())]).normalized()
		widths.append(_cross_section_px(points[i], dir.orthogonal()) / PX_PER_M)
	widths.sort()
	var road_width := clampf(snappedf(widths[widths.size() / 2], 0.5), 6.0, 18.0) if not widths.is_empty() else 12.0

	var result := _closed_polyline(points, checkpoints[0]) if jumps.is_empty() \
			else _polyline_with_jumps(points, jumps, checkpoints[0])
	var simplified: Array[Vector2] = result["points"]
	var gaps: PackedInt32Array = result["gaps"]
	if gaps.is_empty():
		# Две полосы дороги со стенами по 3 м не должны налезать друг на друга.
		simplified = _cut_zigzags(simplified, (road_width + 2.0 * 3.0) * PX_PER_M)

	var report := {}
	var scene_root := _build_scene(layout_name, simplified, gaps, road_width, instances, by_uid,
			background_path, wall_path, report)
	var packed := PackedScene.new()
	var err := packed.pack(scene_root)
	if err == OK:
		err = ResourceSaver.save(packed, out_path)
	if err != OK:
		push_error("Не удалось сохранить %s: %s" % [out_path, error_string(err)])
		quit(1)
		return
	var length := 0.0
	for i in simplified.size():
		if not gaps.has(i):
			length += simplified[i].distance_to(simplified[(i + 1) % simplified.size()]) / PX_PER_M
	print("%s -> %s: точек %d (из %d клеток), разрывов %d, длина ломаной %.0f м, ширина дороги %.1f м, объектов %d, декора %d" % [
		layout_name, out_path, simplified.size(), cells.size(), gaps.size(), length, road_width,
		scene_root.get_node("Props").get_child_count(), scene_root.get_node("Decor").get_child_count()])
	if not report.is_empty():
		print("  не поставлены (не влезли / вне дороги / не переносятся): ", report)
	scene_root.free()
	quit(0)


# --------------------------------------------------------------------------
# Чтение уровня
# --------------------------------------------------------------------------

func _collect(layer: Dictionary, out: Array) -> void:
	out.append_array(layer.get("instances", []))
	for sub in layer.get("subLayers", []):
		_collect(sub, out)


func _find_first(instances: Array, type_name: String):
	for inst in instances:
		if inst["type"] == type_name:
			return inst
	return null


## Центр объекта в px с учётом точки привязки и поворота.
func _center_px(inst: Dictionary) -> Vector2:
	var w: Dictionary = inst["world"]
	var offset := Vector2((0.5 - float(w.get("originX", 0.5))) * float(w["width"]),
			(0.5 - float(w.get("originY", 0.5))) * float(w["height"]))
	return Vector2(float(w["x"]), float(w["y"])) + offset.rotated(float(w.get("angle", 0.0)))


## Индекс тайла -> множитель цены: 1 — дорога, 3 — диагональ, 0 — стена.
func _tile_costs(c3_dir: String) -> Dictionary:
	var result := {}
	var path := c3_dir + "/objectTypes/Main/Tilemap.json"
	var tm = JSON.parse_string(FileAccess.get_file_as_string(path))
	var polys: Dictionary = tm.get("tile-collision-polys", {})
	for key in polys:
		result[int(key)] = 3.0 if bool(polys[key].get("useCollisionPoly", true)) else 1.0
	return result


## Тайлмапы -> одна сетка: в клетке — первый непустой тайл.
func _build_grid(tilemaps: Array, tile_costs: Dictionary) -> void:
	_tiles = PackedInt32Array()
	for tilemap in tilemaps:
		var tm: Dictionary = tilemap["ownData"]["tilemapData"]
		_tile = int(tilemap["properties"]["tile-width"])
		var cols := int(tm["width"])
		var rows := int(tm["height"])
		if _tiles.is_empty():
			_cols = cols
			_rows = rows
			_tiles.resize(_cols * _rows)
			_tiles.fill(-1)
		var raw := PackedInt32Array()
		for part in str(tm["data"]).split(","):
			if part.is_empty():
				continue
			var count := 1
			var value := part
			if "x" in part:
				count = int(part.get_slice("x", 0))
				value = part.get_slice("x", 1)
			var digits := ""
			for ch in value:
				if ch >= "0" and ch <= "9":
					digits += ch
			var tile := int(digits) - 1  # 0 в данных — пусто
			for i in count:
				raw.append(tile)
		# Данные по столбцам: max-width столбцов по (total / max-width) клеток.
		var stride := raw.size() / int(tm["max-width"])
		for x in mini(cols, _cols):
			for y in mini(rows, _rows):
				var tile := raw[x * stride + y]
				if tile >= 0 and _tiles[y * _cols + x] < 0:
					_tiles[y * _cols + x] = tile
	_cost_strict.resize(_cols * _rows)
	_cost_open.resize(_cols * _rows)
	for i in _tiles.size():
		var tile := _tiles[i]
		_cost_strict[i] = float(tile_costs.get(tile, 0.0)) if tile >= 0 else 0.0
		_cost_open[i] = _cost_strict[i] if tile >= 0 else EMPTY_COST


func _build_distance(cost: PackedFloat32Array) -> PackedFloat32Array:
	var dist := PackedFloat32Array()
	dist.resize(_cols * _rows)
	var queue: Array[Vector2i] = []
	for y in _rows:
		for x in _cols:
			var i := y * _cols + x
			if cost[i] == 0.0:
				dist[i] = 0.0
				queue.append(Vector2i(x, y))
			elif x == 0 or y == 0 or x == _cols - 1 or y == _rows - 1:
				dist[i] = 1.0
				queue.append(Vector2i(x, y))
			else:
				dist[i] = INF
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		var d := dist[c.y * _cols + c.x]
		for n in _neighbors(c):
			var ni := n.y * _cols + n.x
			if dist[ni] > d + 1.0:
				dist[ni] = d + 1.0
				queue.append(n)
	return dist


## Куда в оригинале можно доехать от старта: заливка по дороге и пустым клеткам
## (4 соседа; диагональные тайлы у стен — граница, дальше них не идём).
func _flood(from: Vector2i) -> PackedByteArray:
	var seen := PackedByteArray()
	seen.resize(_cols * _rows)
	var queue: Array[Vector2i] = [from]
	seen[from.y * _cols + from.x] = 1
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		if _cost_open[c.y * _cols + c.x] > 1.5 and _tiles[c.y * _cols + c.x] >= 0:
			continue
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if n.x < 0 or n.y < 0 or n.x >= _cols or n.y >= _rows:
				continue
			var ni := n.y * _cols + n.x
			if seen[ni] == 1 or _cost_open[ni] == 0.0:
				continue
			seen[ni] = 1
			queue.append(n)
	return seen


func _neighbors(c: Vector2i) -> Array[Vector2i]:
	var res: Array[Vector2i] = []
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			var n := Vector2i(c.x + dx, c.y + dy)
			if n.x >= 0 and n.y >= 0 and n.x < _cols and n.y < _rows:
				res.append(n)
	return res


## Ширина дороги через точку p поперёк направления (normal — единичный), px.
## Диагональные тайлы у стен проходимы наполовину, поэтому берётся среднее между
## шириной чистой дороги и шириной вместе с диагоналями.
func _cross_section_px(p: Vector2, normal: Vector2) -> float:
	return (_cross_section_until(p, normal, true) + _cross_section_until(p, normal, false)) * 0.5


func _cross_section_until(p: Vector2, normal: Vector2, road_only: bool) -> float:
	var step := _tile * 0.25
	var total := 0.0
	for side in [1.0, -1.0]:
		var d := 0.0
		while d < _tile * 20.0:
			var c := _px_to_cell(p + normal * side * (d + step))
			var cost := _cost_strict[c.y * _cols + c.x]
			if cost == 0.0 or (road_only and cost != 1.0):
				break
			d += step
		total += d
	return total


func _px_to_cell(p: Vector2) -> Vector2i:
	return Vector2i(clampi(floori(p.x / _tile), 0, _cols - 1), clampi(floori(p.y / _tile), 0, _rows - 1))


func _cell_reachable(p: Vector2) -> bool:
	var c := _px_to_cell(p)
	return _reachable[c.y * _cols + c.x] == 1


func _nearest_open(c: Vector2i, cost: PackedFloat32Array) -> Vector2i:
	if cost[c.y * _cols + c.x] > 0.0:
		return c
	var best := c
	var best_d := INF
	for y in _rows:
		for x in _cols:
			if cost[y * _cols + x] > 0.0:
				var d := Vector2(c).distance_squared_to(Vector2(x, y))
				if d < best_d:
					best_d = d
					best = Vector2i(x, y)
	return best


# --------------------------------------------------------------------------
# Поиск пути по середине дороги
# --------------------------------------------------------------------------

func _dijkstra(from: Vector2i, to: Vector2i, cost_grid: PackedFloat32Array, dist: PackedFloat32Array,
		use_portals: bool) -> Array[Vector2i]:
	var n := _cols * _rows
	var best := PackedFloat32Array()
	best.resize(n)
	best.fill(INF)
	var came := PackedInt32Array()
	came.resize(n)
	came.fill(-1)
	var start := from.y * _cols + from.x
	var goal := to.y * _cols + to.x
	best[start] = 0.0
	var heap_cost := PackedFloat32Array([0.0])
	var heap_node := PackedInt32Array([start])
	while not heap_node.is_empty():
		var cur_cost := heap_cost[0]
		var cur := heap_node[0]
		_heap_pop(heap_cost, heap_node)
		if cur == goal:
			break
		if cur_cost > best[cur]:
			continue
		var c := Vector2i(cur % _cols, cur / _cols)
		var next: Array[Vector2i] = _neighbors(c)
		if use_portals and _portal_links.has(cur):
			next.append(_portal_links[cur])
		for nb in next:
			var ni := nb.y * _cols + nb.x
			if cost_grid[ni] == 0.0:
				continue
			var jump := absi(nb.x - c.x) > 1 or absi(nb.y - c.y) > 1
			var step := 1.0 if jump else (1.4142 if (nb.x != c.x and nb.y != c.y) else 1.0)
			var wall_penalty := 1.0 + 6.0 / (dist[ni] * dist[ni])
			var total := cur_cost + step * wall_penalty * cost_grid[ni]
			if total < best[ni]:
				best[ni] = total
				came[ni] = cur
				_heap_push(heap_cost, heap_node, total, ni)
	var path: Array[Vector2i] = []
	if came[goal] == -1 and goal != start:
		return path
	var node := goal
	while node != -1:
		path.push_front(Vector2i(node % _cols, node / _cols))
		if node == start:
			break
		node = came[node]
	return path


func _heap_push(costs: PackedFloat32Array, nodes: PackedInt32Array, cost: float, node: int) -> void:
	costs.append(cost)
	nodes.append(node)
	var i := costs.size() - 1
	while i > 0:
		var parent := (i - 1) / 2
		if costs[parent] <= costs[i]:
			break
		_heap_swap(costs, nodes, i, parent)
		i = parent


func _heap_pop(costs: PackedFloat32Array, nodes: PackedInt32Array) -> void:
	var last := costs.size() - 1
	costs[0] = costs[last]
	nodes[0] = nodes[last]
	costs.resize(last)
	nodes.resize(last)
	var i := 0
	while true:
		var l := i * 2 + 1
		var r := l + 1
		var smallest := i
		if l < costs.size() and costs[l] < costs[smallest]:
			smallest = l
		if r < costs.size() and costs[r] < costs[smallest]:
			smallest = r
		if smallest == i:
			break
		_heap_swap(costs, nodes, i, smallest)
		i = smallest


func _heap_swap(costs: PackedFloat32Array, nodes: PackedInt32Array, a: int, b: int) -> void:
	var tc := costs[a]
	costs[a] = costs[b]
	costs[b] = tc
	var tn := nodes[a]
	nodes[a] = nodes[b]
	nodes[b] = tn


# --------------------------------------------------------------------------
# Сглаживание и упрощение
# --------------------------------------------------------------------------

## Замкнутый путь без порталов -> ломаная: {points, gaps (пусто)}.
func _closed_polyline(points: Array[Vector2], start: Vector2) -> Dictionary:
	var smooth := _smooth_closed(_smooth_closed(points, 2), 2)
	smooth[0] = start
	var simplified := _simplify_closed(smooth, SIMPLIFY_EPSILON_PX)
	# Линия старта должна стоять на прямой, а не в углу ломаной: точку 0 переносим
	# на отрезок между её соседями (сдвиг не больше допуска упрощения).
	simplified[0] = Geometry2D.get_closest_point_to_segment(simplified[0],
			simplified[simplified.size() - 1], simplified[1])
	simplified = _straighten(simplified, true, [0])
	return {"points": simplified, "gaps": PackedInt32Array()}


## Путь с прыжками через порталы: куски между прыжками обрабатываются отдельно
## (концы кусков — вход и выход порталов — сохраняются), затем склеиваются так,
## чтобы точка 0 была стартом. gaps — номера точек, после которых разрыв.
func _polyline_with_jumps(points: Array[Vector2], jumps: Array[int], start: Vector2) -> Dictionary:
	var n := points.size()
	jumps.sort()
	# Куски: от клетки после прыжка до клетки перед следующим прыжком (по кругу).
	var pieces: Array = []
	for k in jumps.size():
		var first := (jumps[posmod(k - 1, jumps.size())] + 1) % n
		var last := jumps[k]
		var piece: Array[Vector2] = []
		var i := first
		var start_pos := -1
		while true:
			if i == 0:
				start_pos = piece.size()
			piece.append(points[i])
			if i == last:
				break
			i = (i + 1) % n
		pieces.append({"points": piece, "start": start_pos})
	var processed: Array = []
	var start_piece := 0
	for k in pieces.size():
		var piece: Array[Vector2] = pieces[k]["points"]
		var start_pos: int = pieces[k]["start"]
		var smooth := _smooth_open(_smooth_open(piece, 2), 2)
		var pinned: Array[int] = [0, smooth.size() - 1]
		if start_pos >= 0:
			smooth[start_pos] = start
			pinned.append(start_pos)
			start_piece = k
		var kept := _simplify_open(smooth, SIMPLIFY_EPSILON_PX, pinned)
		var simple: Array[Vector2] = []
		var new_pinned: Array[int] = []
		var new_start := -1
		for index in kept:
			if index in pinned:
				new_pinned.append(simple.size())
			if index == start_pos:
				new_start = simple.size()
			simple.append(smooth[index])
		var straight := _straighten_open(simple, new_pinned, new_start)
		processed.append(straight)
	# Склейка: хвост куска со стартом (от старта), остальные куски, голова куска со стартом.
	var result: Array[Vector2] = []
	var gaps := PackedInt32Array()
	var first_piece: Dictionary = processed[start_piece]
	var first_points: Array[Vector2] = first_piece["points"]
	var s: int = first_piece["start"]
	result.append_array(first_points.slice(s))
	gaps.append(result.size() - 1)
	for step in range(1, processed.size()):
		var piece: Dictionary = processed[(start_piece + step) % processed.size()]
		result.append_array(piece["points"] as Array[Vector2])
		gaps.append(result.size() - 1)
	if s > 0:
		result.append_array(first_points.slice(0, s))
		# Голова идёт к старту без разрыва — линию старта ставим на прямую между соседями.
		if first_points.size() - s > 1:
			result[0] = Geometry2D.get_closest_point_to_segment(result[0], result[result.size() - 1], result[1])
	return {"points": result, "gaps": gaps}


## Змейка (дорога поворачивает туда-обратно, полосы ближе clearance px — например,
## «змейка» с разворотами Reverser на Снежной) на ленту трассы не ложится: стены полос
## налезают друг на друга. Такой участок заменяется прямой. Шпильки (выезд в обратную
## сторону) не трогаются. Точка 0 (старт) сохраняется.
func _cut_zigzags(points: Array[Vector2], clearance: float) -> Array[Vector2]:
	var res: Array[Vector2] = points.duplicate()
	var changed := true
	while changed and res.size() > 4:
		changed = false
		var n := res.size()
		for i in n:
			var a0 := res[i]
			var a1 := res[(i + 1) % n]
			var in_dir := (a1 - a0).normalized()
			for k in range(2, mini(7, n - 2)):
				var j := (i + k) % n
				var b0 := res[j]
				var b1 := res[(j + 1) % n]
				if _segments_distance(a0, a1, b0, b1) >= clearance:
					continue
				var out_dir := (b1 - b0).normalized()
				if in_dir.dot(out_dir) <= 0.0:
					continue  # шпилька — выезд назад
				# Змейка: поворачивает туда-обратно (сумма поворотов намного больше итогового).
				var turning := 0.0
				var removes_start := false
				for m in range(1, k + 1):
					var p := (i + m) % n
					if p == 0:
						removes_start = true
					var before := res[p] - res[posmod(p - 1, n)]
					var after := res[(p + 1) % n] - res[p]
					turning += absf(before.angle_to(after))
				if removes_start or turning - absf(in_dir.angle_to(out_dir)) < deg_to_rad(120.0):
					continue
				# Убрать точки i+1..j: дорога идёт прямо от i к j+1 (точка 0 остаётся первой).
				var keep: Array[Vector2] = []
				for q in n:
					var rel := posmod(q - i, n)
					if rel < 1 or rel > k:
						keep.append(res[q])
				res = keep
				changed = true
				break
			if changed:
				break
	return res


func _segments_distance(a0: Vector2, a1: Vector2, b0: Vector2, b1: Vector2) -> float:
	if Geometry2D.segment_intersects_segment(a0, a1, b0, b1) != null:
		return 0.0
	return minf(minf(_point_segment_distance(a0, b0, b1), _point_segment_distance(a1, b0, b1)),
			minf(_point_segment_distance(b0, a0, a1), _point_segment_distance(b1, a0, a1)))


func _smooth_closed(points: Array[Vector2], radius: int) -> Array[Vector2]:
	var res: Array[Vector2] = []
	var n := points.size()
	for i in n:
		var sum := Vector2.ZERO
		for k in range(-radius, radius + 1):
			sum += points[posmod(i + k, n)]
		res.append(sum / (radius * 2 + 1))
	return res


## Сглаживание открытой линии: у концов окно прижимается к концу (концы на месте).
func _smooth_open(points: Array[Vector2], radius: int) -> Array[Vector2]:
	var res: Array[Vector2] = []
	var n := points.size()
	for i in n:
		var r := mini(radius, mini(i, n - 1 - i))
		var sum := Vector2.ZERO
		for k in range(-r, r + 1):
			sum += points[i + k]
		res.append(sum / (r * 2 + 1))
	return res


## Дуглас — Пекер для замкнутой линии: точка 0 сохраняется.
func _simplify_closed(points: Array[Vector2], epsilon: float) -> Array[Vector2]:
	var open: Array[Vector2] = points.duplicate()
	open.append(points[0])
	var keep := PackedByteArray()
	keep.resize(open.size())
	keep[0] = 1
	keep[open.size() - 1] = 1
	_dp(open, 0, open.size() - 1, epsilon, keep)
	var res: Array[Vector2] = []
	for i in open.size() - 1:
		if keep[i] == 1:
			res.append(open[i])
	return res


## Дуглас — Пекер для открытой линии: концы и pinned сохраняются. Возвращает номера точек.
func _simplify_open(points: Array[Vector2], epsilon: float, pinned: Array[int]) -> Array[int]:
	var keep := PackedByteArray()
	keep.resize(points.size())
	var fixed: Array[int] = pinned.duplicate()
	fixed.sort()
	for index in fixed:
		keep[index] = 1
	for k in fixed.size() - 1:
		_dp(points, fixed[k], fixed[k + 1], epsilon, keep)
	var res: Array[int] = []
	for i in points.size():
		if keep[i] == 1:
			res.append(i)
	return res


func _dp(points: Array[Vector2], first: int, last: int, epsilon: float, keep: PackedByteArray) -> void:
	if last <= first + 1:
		return
	var a := points[first]
	var b := points[last]
	var best := -1.0
	var index := -1
	for i in range(first + 1, last):
		var d := _point_segment_distance(points[i], a, b)
		if d > best:
			best = d
			index = i
	if best > epsilon:
		keep[index] = 1
		_dp(points, first, index, epsilon, keep)
		_dp(points, index, last, epsilon, keep)


## Почти горизонтальные и почти вертикальные отрезки (отклонение до STRAIGHTEN_DEG)
## делаются ровными, лишние точки на одной прямой убираются (кроме pinned). Тайловые
## трассы оригинала состоят из прямых по осям, а путь Дейкстры по ним «гуляет» на полклетки.
func _straighten(points: Array[Vector2], closed: bool, pinned: Array[int]) -> Array[Vector2]:
	var res: Array[Vector2] = points.duplicate()
	var n := res.size()
	var segments := n if closed else n - 1
	var tolerance := tan(deg_to_rad(STRAIGHTEN_DEG))
	# Вид отрезка i -> i+1: 0 — вертикальный (общий x), 1 — горизонтальный (общий y), -1 — другой.
	var kinds := PackedInt32Array()
	for i in segments:
		var d := res[(i + 1) % n] - res[i]
		kinds.append(0 if absf(d.x) <= absf(d.y) * tolerance else (1 if absf(d.y) <= absf(d.x) * tolerance else -1))
	# Цепочка подряд идущих отрезков одного вида — одна прямая: общая координата — среднее.
	var done := PackedByteArray()
	done.resize(segments)
	for s in segments:
		if kinds[s] < 0 or done[s] == 1:
			continue
		var axis := kinds[s]
		var first := s
		var steps := 0
		if closed:
			while kinds[posmod(first - 1, n)] == axis and steps < n:
				first = posmod(first - 1, n)
				steps += 1
		else:
			while first > 0 and kinds[first - 1] == axis:
				first -= 1
		var vertices: Array[int] = [first]
		var k := first
		while k < segments and kinds[k] == axis and done[k] == 0:
			done[k] = 1
			k = (k + 1) % n if closed else k + 1
			vertices.append(k)
			if closed and k >= segments:
				break
		var mean := 0.0
		for v in vertices:
			mean += res[v][axis]
		mean /= vertices.size()
		for v in vertices:
			res[v][axis] = mean
	# Точки, где направление почти не меняется, лишние (pinned — старт, концы у порталов — нет).
	var keep := PackedByteArray()
	keep.resize(n)
	for p in pinned:
		keep[p] = 1
	var i := 1
	var last := res.size() if closed else res.size() - 1
	while i < last and res.size() > 3:
		var a := res[i - 1]
		var b := res[(i + 1) % res.size()]
		if keep[i] == 0 and (res[i].distance_to(a) < 1.0 or absf((res[i] - a).angle_to(b - res[i])) < deg_to_rad(3.0)):
			res.remove_at(i)
			keep.remove_at(i)
			last -= 1
		else:
			i += 1
	return res


## Открытая линия: выпрямить, вернуть {points, start} (новый номер точки старта или -1).
func _straighten_open(points: Array[Vector2], pinned: Array[int], start_index: int) -> Dictionary:
	# Номер старта после удаления точек: метим его заранее особой точкой.
	var marker := points[start_index] if start_index >= 0 else Vector2.INF
	var res := _straighten(points, false, pinned)
	var start := -1
	if start_index >= 0:
		var best := INF
		for k in res.size():
			var d := res[k].distance_squared_to(marker)
			if d < best:
				best = d
				start = k
	return {"points": res, "start": maxi(start, 0) if start_index >= 0 else 0}


func _point_segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 < 1e-6:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


# --------------------------------------------------------------------------
# Сцена
# --------------------------------------------------------------------------

func _build_scene(layout_name: String, points: Array[Vector2], gaps: PackedInt32Array, road_width: float,
		instances: Array, by_uid: Dictionary, background_path: String, wall_path: String,
		report: Dictionary) -> Node3D:
	var track := TRACK_SCRIPT.new() as Track
	track.name = layout_name
	track.road_width = road_width
	track.road_material = load(ROAD_MATERIAL)
	track.wall_material = load(wall_path)
	track.background_material = load(background_path)
	track.start_line_material = load(START_LINE_MATERIAL)
	track.start_gate_scene = load(START_GATE_SCENE)
	track.portal_gaps = gaps
	if MAP_MUSIC.has(layout_name):
		track.music = load("res://assets/original/music/%s.ogg" % MAP_MUSIC[layout_name])

	var curve := Curve3D.new()
	curve.bake_interval = 0.5
	for p in points:
		curve.add_point(Vector3(p.x / PX_PER_M, 0.0, p.y / PX_PER_M))
	curve.closed = true
	var path := Path3D.new()
	path.name = "Path"
	path.curve = curve
	track.add_child(path)
	path.owner = track

	var props := Node3D.new()
	props.name = "Props"
	track.add_child(props)
	props.owner = track
	# Декор оригинала за дорогой: не игровые объекты (автопилот и проверки их не видят).
	var decor := Node3D.new()
	decor.name = "Decor"
	track.add_child(decor)
	decor.owner = track
	# Колонны оригинала уходят ниже дороги — значит, трасса — эстакада над фоном.
	# Сами колонны не переносим: опоры ставит Track с ровным шагом вдоль краёв.
	var depth := 0.0
	for inst in instances:
		if inst["type"] == COLUMN_TYPE:
			depth = maxf(depth, -float(inst["world"].get("zElevation", 0.0)) / PX_PER_M)
	track.background_depth = depth
	if depth > 0.0:
		track.support_scene = load(COLUMN_SCENE)
	# Кислота, вода и масло в оригинале «текут»: смещение 8 и −16 px/с.
	for inst in instances:
		if inst["type"] in ["AcidBg", "WaterBg", "OilBg"]:
			track.background_scroll = Vector2(8.0, -16.0) / PX_PER_M

	# Трасса строится в дереве, чтобы ставить объекты относительно её центральной линии.
	root.add_child(track)
	var lane := road_width / LANE_DIVISIONS
	var entries: Array[Dictionary] = []
	var counters := {}
	for inst in instances:
		var type_name := str(inst["type"])
		var center := _center_px(inst)
		var p := Vector3(center.x / PX_PER_M, 0.0, center.y / PX_PER_M)
		var made := _make_object(type_name, inst, track, _cell_reachable(center))
		if made.is_empty():
			if type_name not in ["Tilemap", "Start", "SubLapTrigger", COLUMN_TYPE, "Portal"] and not type_name.ends_with("Bg"):
				report[type_name] = int(report.get(type_name, 0)) + 1
			continue
		var node: Node3D = made["node"]
		var role: String = made["role"]
		counters[type_name] = int(counters.get(type_name, 0)) + 1
		node.name = "%s%d" % ["ItemBoxSpot" if type_name == "ItemBox" else type_name, counters[type_name]]
		var w: Dictionary = inst["world"]
		if role == "decor":
			if not _place_decor(track, node, p, w):
				node.free()
				report[type_name] = int(report.get(type_name, 0)) + 1
				continue
			decor.add_child(node)
			_set_owner_recursive(node, track)
			continue
		props.add_child(node)
		_set_owner_recursive(node, track)
		if PROP_BASE_SIZE.has(type_name):
			var base: Vector2 = PROP_BASE_SIZE[type_name]
			node.scale = Vector3(float(w["width"]) / base.x, 1.0, float(w["height"]) / base.y)
		if type_name == "BoostPad":
			node.set("kind", BOOST_KINDS.get(str(inst["properties"].get("initial-animation", "")), 0))
		# Положение — в координатах трассы: расстояние от старта и смещение вбок.
		var offset: float = track.project(p)["offset"]
		var lateral := (p - track.get_point_at(offset)).dot(_track_right(track, offset))
		# Поворот — относительно направления трассы, кратно 90° (ограждения — поперёк или вдоль).
		var relative := snappedf(wrapf(-float(w.get("angle", 0.0)) - _track_yaw(track, offset), -PI, PI), PI * 0.5)
		if role == "wall":
			_place_on_wall(track, node, offset, lateral)
			continue
		if role == "across":
			# Во всю ширину дороги, поперёк (триггер музыки).
			node.position = track.get_point_at(offset)
			node.rotation.y = _track_yaw(track, offset)
			node.scale = Vector3(road_width / 2.0, 1.0, 1.0)
			continue
		if node is CircusBalls:
			# Шары ездят поперёк дороги (ось X узла), по центру, не заезжая на стены.
			relative = 0.0
			lateral = 0.0
			(node as CircusBalls).sweep = minf(CircusBalls.DEFAULT_SWEEP, road_width * 0.5 - 1.5)
		if node is MapZone:
			_fit_zone(node as MapZone, w, relative, road_width)
		var half := TrackLayout.half_width_across(node, relative)
		var limit := maxf(floorf((road_width * 0.5 - half - 0.3) / lane) * lane, 0.0)
		entries.append({"node": node, "type": type_name, "role": role, "world": p, "offset": offset, "raw": lateral,
				"lateral": clampf(snappedf(lateral, lane), -limit, limit), "relative": relative, "limit": limit})

	var portals := _place_portals(track, props, instances, by_uid)

	# Коробки предметов, стоявшие в оригинале кучкой, — один ровный ряд поперёк дороги.
	var boxes := entries.filter(func(e: Dictionary) -> bool: return e["type"] == "ItemBox")
	for g in _group_by_distance(boxes, BOX_GROUP_DISTANCE):
		_align_box_row(g)

	# Ускорители оригинала лежат плитками вплотную — каждый блок ставится целиком.
	var pads := entries.filter(func(e: Dictionary) -> bool: return e["type"] == "BoostPad")
	for g in _group_by_distance(pads, PAD_SIZE * 1.2):
		_place_pad_block(track, g, road_width, lane)

	# Остальные объекты рядом вдоль трассы — один ряд; если полоса уже занята,
	# объект встаёт на соседнюю (с той стороны, где стоял в оригинале).
	var others := entries.filter(func(e: Dictionary) -> bool: return e["type"] not in ["ItemBox", "BoostPad"] and e["role"] != "zone")
	others.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x["offset"] < y["offset"])
	var i := 0
	while i < others.size():
		var row: Array = [others[i]]
		var j := i + 1
		while j < others.size() and others[j]["offset"] - others[i]["offset"] < ROW_TOLERANCE:
			var e: Dictionary = others[j]
			if _lane_taken(row, e["lateral"]):
				var shifted: float = e["lateral"] + (lane if e["raw"] >= e["lateral"] else -lane)
				if absf(shifted) > e["limit"] + 0.01 or _lane_taken(row, shifted):
					break
				e["lateral"] = shifted
			row.append(e)
			j += 1
		var offset := 0.0
		for e in row:
			offset += e["offset"]
		offset /= row.size()
		for e in row:
			e["offset"] = offset
		i = j

	# На дугах внутренние полосы короче: объекты из соседних рядов могут сойтись.
	# Наложившийся объект (проверка редактора карт TrackCheck) переезжает на ближайшую
	# свободную полосу; не нашлось места или ряд уже перегорожен больше чем наполовину —
	# объект не ставится (в оригинале дорога местами шире нашей).
	var placed: Array[Node3D] = portals.duplicate()
	var blocking: Array[Dictionary] = []
	# Ускорители: плитка, налезающая на соседнюю (диагональные блоки оригинала сходятся
	# в одну клетку) или на стену (блок прямой, а дорога на дуге), не ставится.
	for e in pads:
		_apply_entry(e)
		var pad := e["node"] as Node3D
		var where := TrackLayout.locate(track, pad.global_position)
		var on_wall := absf(float(where["lateral"])) + PAD_SIZE * 0.5 > road_width * 0.5 - 0.05
		if on_wall or placed.any(func(other: Node3D) -> bool: return TrackCheck.footprints_overlap(pad, other)):
			report["BoostPad"] = int(report.get("BoostPad", 0)) + 1
			pad.get_parent().remove_child(pad)
			pad.free()
			continue
		placed.append(pad)
	# Зоны (лёд, ленты, горки) — первыми. Лента, толкающая поперёк дороги, у нас прижимала бы
	# машину к стене (в оригинале она лежала на широкой площадке) — не ставится. Возле лент
	# (по ходу и против хода) твёрдых препятствий нет: лента против хода прижимала бы к ним.
	var conveyor_ranges: Array[Vector2] = []
	for e in entries:
		if e["role"] != "zone":
			continue
		var zone := e["node"] as MapZone
		e["yaw"] = snappedf(_track_yaw(track, e["offset"]) + float(e["relative"]), PI * 0.25)
		e["position"] = track.get_point_at(e["offset"], e["lateral"])
		_apply_entry(e)
		if zone.kind != MapZone.Kind.CONVEYOR:
			continue
		var along := absf(zone.global_basis.x.dot(track.get_direction_at(e["offset"])))
		if along < 0.7:
			report["Conveyor (поперёк дороги)"] = int(report.get("Conveyor (поперёк дороги)", 0)) + 1
			zone.get_parent().remove_child(zone)
			zone.free()
			continue
		var half_along := zone.size.x * 0.5 + CONVEYOR_CLEARANCE
		conveyor_ranges.append(Vector2(e["offset"] - half_along, e["offset"] + half_along))
	for e in entries:
		if e["type"] == "BoostPad" or e["role"] == "zone":
			continue
		var node := e["node"] as Node3D
		# Абсолютный поворот кратен 45° — как тайлы оригинала (на дугах объекты не «косят»).
		e["yaw"] = snappedf(_track_yaw(track, e["offset"]) + float(e["relative"]), PI * 0.25)
		var near_conveyor := conveyor_ranges.any(func(r: Vector2) -> bool:
				return float(e["offset"]) > r.x and float(e["offset"]) < r.y)
		if near_conveyor and (e["role"] in ["solid", "parry"] or node is StaticBody3D or node is ParryHazard):
			report[e["type"]] = int(report.get(e["type"], 0)) + 1
			node.get_parent().remove_child(node)
			node.free()
			continue
		var side := 1.0 if e["raw"] >= e["lateral"] else -1.0
		# Сначала соседние полосы, потом сдвиг вдоль трассы (поперёк дороги могут стоять
		# ограждения во всю ширину).
		var candidates: Array[Vector2] = [Vector2(e["lateral"], 0.0)]
		for step in [1, -1, 2, -2]:
			candidates.append(Vector2(e["lateral"] + side * step * lane, 0.0))
		for shift in [1.5, -1.5, 3.0, -3.0, 4.5, -4.5]:
			candidates.append(Vector2(e["lateral"], shift))
		var chosen := Vector2.INF
		var base_offset: float = e["offset"]
		for candidate in candidates:
			if absf(candidate.x) > e["limit"] + 0.01:
				continue
			e["position"] = track.get_point_at(base_offset + candidate.y, candidate.x)
			_apply_entry(e)
			if not placed.any(func(other: Node3D) -> bool: return TrackCheck.footprints_overlap(node, other)):
				chosen = candidate
				break
		var across := TrackLayout.half_width_across(node, e["relative"]) * 2.0
		var blocks: bool = e["role"] in ["solid", "parry"] or node is ParryHazard or node is StaticBody3D
		var crowded := false
		if blocks and chosen != Vector2.INF:
			var occupied := across
			for b in blocking:
				if absf(float(b["offset"]) - (base_offset + chosen.y)) < DENSITY_WINDOW:
					occupied += float(b["across"])
			crowded = occupied > road_width * DENSITY_MAX
		if chosen == Vector2.INF or crowded:
			report[e["type"]] = int(report.get(e["type"], 0)) + 1
			node.get_parent().remove_child(node)
			node.free()
			continue
		e["lateral"] = chosen.x
		e["offset"] = base_offset + chosen.y
		e["position"] = track.get_point_at(e["offset"], chosen.x)
		_apply_entry(e)
		placed.append(node)
		if blocks:
			blocking.append({"offset": e["offset"], "across": across})
	_fill_empty_stretches(track, props, placed, report)
	root.remove_child(track)
	return track


## Карты заполнены (правило автора ремейка): участок дороги длиннее TrackCheck.MAX_GAP без
## игровых объектов получает наш трамплин (на прямой) или ряд коробок предметов (на дуге).
func _fill_empty_stretches(track: Track, props: Node3D, placed: Array[Node3D], report: Dictionary) -> void:
	var added := 0
	for attempt in 8:
		var offsets: Array[float] = []
		for child in props.get_children():
			if TrackLayout.is_gameplay(child):
				offsets.append(float(TrackLayout.locate(track, (child as Node3D).global_position)["offset"]))
		offsets.sort()
		if offsets.is_empty():
			return
		var worst := 0.0
		var from := 0.0
		for i in offsets.size():
			var next := offsets[(i + 1) % offsets.size()] + (track.length if i == offsets.size() - 1 else 0.0)
			var empty := track.road_length_between(offsets[i], next)
			if empty > worst:
				worst = empty
				from = offsets[i]
		if worst <= TrackCheck.MAX_GAP - 2.0:
			break
		# Середина пустого участка по дороге (разрыв портала пропускается).
		var middle := from
		var walked := 0.0
		while walked < worst * 0.5:
			middle += 1.0
			if not track.is_in_gap(middle):
				walked += 1.0
		var bend := track.get_direction_at(middle - 12.0).angle_to(track.get_direction_at(middle + 12.0))
		var yaw := snappedf(_track_yaw(track, middle), PI * 0.25)
		if bend < deg_to_rad(8.0):
			var ramp := (load(RAMP_SCENE) as PackedScene).instantiate() as Node3D
			ramp.name = "FillRamp%d" % (added + 1)
			props.add_child(ramp)
			ramp.owner = track
			ramp.position = track.get_point_at(middle)
			ramp.rotation.y = yaw
			placed.append(ramp)
		else:
			for k in [-1, 0, 1]:
				var marker := Marker3D.new()
				marker.name = "FillItemBox%d_%d" % [added + 1, k + 2]
				marker.add_to_group(ITEM_BOX_GROUP, true)
				props.add_child(marker)
				marker.owner = track
				marker.position = track.get_point_at(middle, k * ITEM_BOX_SPACING)
				marker.rotation.y = yaw
		added += 1
	if added > 0:
		report["добавлено (заполнение)"] = added


## Объект оригинала -> узел ремейка и его роль: road (на дороге, по полосам), solid/parry
## (коробки и таблички на дороге), zone (плоская зона), wall (на стене), across (во всю
## ширину), decor (за дорогой). {} — не переносится.
func _make_object(type_name: String, inst: Dictionary, track: Track, reachable: bool) -> Dictionary:
	var w: Dictionary = inst["world"]
	if type_name == "ItemBox":
		var marker := Marker3D.new()
		marker.add_to_group(ITEM_BOX_GROUP, true)
		return {"node": marker, "role": "road"}
	if PROPS.has(type_name):
		return {"node": (load(PROPS[type_name]) as PackedScene).instantiate(), "role": "road"}
	if ZONE_KINDS.has(type_name):
		var zone := (load(ZONE_SCENE) as PackedScene).instantiate() as MapZone
		zone.kind = ZONE_KINDS[type_name]
		# Цвет экземпляра (лёд белый, оригинал красит его: голубой, оранжевые лужи…).
		var color: Array = w.get("color", [1, 1, 1, 1])
		zone.tint = Color(color[0], color[1], color[2], color[3])
		return {"node": zone, "role": "zone"}
	if type_name == "SnowTurret":
		return {"node": (load(TURRET_SCENE) as PackedScene).instantiate(), "role": "wall"}
	if type_name == "Trigger":
		var act := str(inst["instanceVariables"].get("Act", ""))
		var music_path := "res://assets/original/music/%s.ogg" % act.get_slice(" ", 1).to_lower()
		if not act.begins_with("Music ") or not ResourceLoader.exists(music_path):
			return {}
		var trigger := (load(MUSIC_TRIGGER_SCENE) as PackedScene).instantiate() as MusicTrigger
		trigger.music = load(music_path)
		return {"node": trigger, "role": "across"}
	var size_px := Vector3(float(w["width"]), float(inst["properties"].get("z-height", 0.0)), float(w["height"]))
	if SHAPES.has(type_name):
		var spec: Dictionary = SHAPES[type_name]
		var role: String = spec["role"]
		if role != "decor" and not reachable:
			role = "decor"
		var size := size_px / PX_PER_M
		var visual := _box_visual(size, spec["folder"], type_name.to_lower(), false)
		visual.position.y = float(w.get("zElevation", 0.0)) / PX_PER_M if role == "decor" else 0.0
		return {"node": _wrap(visual, role, size, spec.get("sounds", [])), "role": role}
	if SPRITES.has(type_name):
		var spec: Dictionary = SPRITES[type_name]
		var role: String = spec["role"]
		if role != "decor" and not reachable:
			return {}
		var size := Vector3(size_px.x, 0.0, size_px.z) / PX_PER_M
		var visual := _box_visual(size, "levelobj", type_name.to_lower(), true)
		visual.position.y = float(spec["height"])
		visual.set("frame", int(inst["properties"].get("initial-frame", 0)))
		size.y = float(spec.get("collision_height", 0.0))
		return {"node": _wrap(visual, role, size, spec.get("sounds", [])), "role": role}
	return {}


func _box_visual(size: Vector3, folder: String, base_name: String, flat: bool) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.name = "Visual"
	visual.set_script(load(BOX_VISUAL_SCRIPT))
	visual.set("size", size)
	visual.set("folder", folder)
	visual.set("base_name", base_name)
	visual.set("flat", flat)
	return visual


## Корень объекта по роли: твёрдое — StaticBody3D, парируемое — ParryHazard (Area3D),
## декор — Node3D без коллизии.
func _wrap(visual: MeshInstance3D, role: String, size: Vector3, sounds: Array) -> Node3D:
	var node: Node3D
	match role:
		"solid":
			node = StaticBody3D.new()
		"parry":
			var area := Area3D.new()
			area.set_script(load(PARRY_HAZARD_SCRIPT))
			area.collision_layer = 4
			area.collision_mask = 2
			area.monitorable = false
			var streams: Array[AudioStream] = []
			for s in sounds:
				streams.append(load("res://assets/original/sounds/%s.wav" % s))
			area.set("hit_sounds", streams)
			node = area
		_:
			node = Node3D.new()
	node.add_child(visual)
	if role in ["solid", "parry"]:
		var shape := BoxShape3D.new()
		shape.size = Vector3(size.x, maxf(size.y, 1.0), size.z)
		var collision := CollisionShape3D.new()
		collision.name = "Collision"
		collision.shape = shape
		collision.position.y = shape.size.y * 0.5
		node.add_child(collision)
	return node


func _set_owner_recursive(node: Node, owner_node: Node) -> void:
	node.owner = owner_node
	# Узлы внутри инстанцированных сцен принадлежат своей сцене.
	if not node.scene_file_path.is_empty():
		return
	for child in node.get_children():
		_set_owner_recursive(child, owner_node)


## Декор на месте из оригинала, если не задевает нашу дорогу со стенами.
## На эстакаде (фон ниже дороги) и над «текущим» фоном декор не ставится.
func _place_decor(track: Track, node: Node3D, p: Vector3, w: Dictionary) -> bool:
	# Фон — вода, кислота или масло: в оригинале декор стоял на песке/плитке у дороги,
	# у нас этой полосы нет — в жидкости он смотрится мусором.
	if track.background_depth > 0.0 or track.background_scroll != Vector2.ZERO:
		return false
	var angle := -float(w.get("angle", 0.0))
	var where := track.project(p)
	var offset := float(where["offset"])
	var visual := node.get_node(^"Visual") as Node3D
	var size: Vector3 = visual.get("size")
	var relative := wrapf(angle - _track_yaw(track, offset), -PI, PI)
	var across := absf(cos(relative)) * size.x * 0.5 + absf(sin(relative)) * size.z * 0.5
	if float(where["distance"]) - across < track.road_width * 0.5 + track.wall_width + 0.5:
		return false
	node.position = p
	node.rotation.y = angle
	return true


## Снежная турель: на стене с той стороны, где стояла, стреляет поперёк дороги.
func _place_on_wall(track: Track, node: Node3D, offset: float, lateral: float) -> void:
	var side := 1.0 if lateral >= 0.0 else -1.0
	var edge := track.road_width * 0.5 + track.wall_width * 0.5
	node.position = track.get_point_at(offset, side * edge)
	# Ось +X узла (направление выстрела) — к другой стороне дороги.
	var right := _track_right(track, offset)
	var shoot := -right * side
	node.rotation.y = snappedf(atan2(-shoot.z, shoot.x), PI * 0.25)


## Зона (лёд, лента, горка): размер из оригинала, поперёк дороги — не шире дороги.
func _fit_zone(zone: MapZone, w: Dictionary, relative: float, road_width: float) -> void:
	var size := Vector2(float(w["width"]), float(w["height"])) / PX_PER_M
	# relative кратен 90°: при ±90° ось X узла идёт вдоль дороги.
	var x_along := absf(sin(relative)) > 0.5
	if x_along:
		size.y = minf(size.y, road_width)
	else:
		size.x = minf(size.x, road_width)
	zone.size = size


## Порталы на концах разрывов трассы: вход перед разрывом, выход после, оба носом по ходу
## гонки; цвет — из оригинала (вход — по ближайшему порталу, выход — его пара).
func _place_portals(track: Track, props: Node3D, instances: Array, by_uid: Dictionary) -> Array[Node3D]:
	var result: Array[Node3D] = []
	var portals := instances.filter(func(i): return i["type"] == "Portal" and int(i["instanceVariables"].get("To", 0)) != 0)
	var k := 0
	for gap in track.get_gaps():
		k += 1
		var entry_point := track.get_point_at(gap.x - 0.5)
		var source: Dictionary = {}
		var best := INF
		for inst in portals:
			var c := _center_px(inst)
			var d := Vector3(c.x / PX_PER_M, 0.0, c.y / PX_PER_M).distance_to(entry_point)
			if d < best:
				best = d
				source = inst
		var entry := (load(PORTAL_SCENE) as PackedScene).instantiate() as Portal
		var exit := (load(PORTAL_SCENE) as PackedScene).instantiate() as Portal
		entry.name = "PortalIn%d" % k
		exit.name = "PortalOut%d" % k
		props.add_child(entry)
		props.add_child(exit)
		entry.owner = track
		exit.owner = track
		var in_offset: float = gap.x - PORTAL_IN_OFFSET
		var out_offset: float = gap.y + PORTAL_OUT_OFFSET
		entry.position = track.get_point_at(in_offset)
		entry.rotation.y = _track_yaw(track, in_offset)
		exit.position = track.get_point_at(out_offset)
		exit.rotation.y = _track_yaw(track, out_offset)
		entry.target = NodePath("../" + exit.name)
		result.append(entry)
		result.append(exit)
		if not source.is_empty():
			var color: Array = source["world"].get("color", [1, 1, 1, 1])
			entry.color = Color(color[0], color[1], color[2])
			var pair: Dictionary = by_uid.get(int(source["instanceVariables"]["To"]), {})
			var pair_color: Array = pair.get("world", {}).get("color", color)
			exit.color = Color(pair_color[0], pair_color[1], pair_color[2])
	return result


func _apply_entry(e: Dictionary) -> void:
	var node := e["node"] as Node3D
	node.position = e["position"]
	node.rotation.y = e["yaw"]


## Группы объектов, связанных цепочкой «ближе distance» (по положению в оригинале).
func _group_by_distance(items: Array, distance: float) -> Array[Array]:
	var groups: Array[Array] = []
	for e in items:
		var joined: Array = []
		for g in groups:
			if g.any(func(o: Dictionary) -> bool: return o["world"].distance_to(e["world"]) < distance):
				joined = g
				break
		if joined.is_empty():
			groups.append([e])
		else:
			joined.append(e)
	return groups


## Блок ускорителей: сетка с шагом PAD_SIZE, повёрнутая по трассе (кратно 45°),
## на ближайшей полосе, целиком на дороге.
func _place_pad_block(track: Track, pads: Array, road_width: float, lane: float) -> void:
	var center := Vector3.ZERO
	for e in pads:
		center += e["world"]
	center /= pads.size()
	var offset: float = track.project(center)["offset"]
	var yaw := snappedf(_track_yaw(track, offset), PI * 0.25)
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	# Клетки сетки относительно первого ускорителя, затем — относительно середины блока.
	var origin: Vector3 = pads[0]["world"]
	var cells: Array[Vector2] = []
	var middle := Vector2.ZERO
	for e in pads:
		var d: Vector3 = e["world"] - origin
		var cell := Vector2(snappedf(d.dot(right), PAD_SIZE), snappedf(d.dot(forward), PAD_SIZE))
		cells.append(cell)
		middle += cell
	middle /= pads.size()
	var half_width := 0.0
	for k in cells.size():
		cells[k] -= middle
		half_width = maxf(half_width, absf(cells[k].x) + PAD_SIZE * 0.5)
	var raw := (center - track.get_point_at(offset)).dot(_track_right(track, offset))
	var limit := maxf(road_width * 0.5 - 0.3 - half_width, 0.0)
	var lateral := clampf(snappedf(raw, lane), -limit, limit)
	var base := track.get_point_at(offset, lateral)
	for k in pads.size():
		var e: Dictionary = pads[k]
		e["position"] = base + right * cells[k].x + forward * cells[k].y
		# Стрелки — по ходу гонки (толкает ускоритель всё равно по носу машины): участок
		# оригинала мог быть выпрямлен (змейка), и стрелки «назад» сбивали бы с толку.
		e["yaw"] = yaw


func _lane_taken(row: Array, lateral: float) -> bool:
	return row.any(func(o: Dictionary) -> bool: return absf(o["lateral"] - lateral) < 0.1)


## Ряд коробок: общее расстояние от старта, через ITEM_BOX_SPACING около их середины.
func _align_box_row(boxes: Array) -> void:
	var offset := 0.0
	var center := 0.0
	for e in boxes:
		offset += e["offset"]
		center += e["raw"]
	offset /= boxes.size()
	center /= boxes.size()
	boxes.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x["raw"] < y["raw"])
	var half_span := (boxes.size() - 1) * 0.5 * ITEM_BOX_SPACING
	var limit: float = boxes[0]["limit"]
	center = clampf(snappedf(center, ITEM_BOX_SPACING * 0.5), -limit + half_span, limit - half_span) \
			if half_span <= limit else 0.0
	for k in boxes.size():
		boxes[k]["offset"] = offset
		boxes[k]["lateral"] = center + (k - (boxes.size() - 1) * 0.5) * ITEM_BOX_SPACING

## Поворот вокруг Y, при котором −Z смотрит по ходу гонки.
func _track_yaw(track: Track, offset: float) -> float:
	var dir := track.get_direction_at(offset)
	return atan2(-dir.x, -dir.z)


func _track_right(track: Track, offset: float) -> Vector3:
	return track.get_direction_at(offset).cross(Vector3.UP).normalized()
