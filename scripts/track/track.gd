@tool
class_name Track
extends Node3D
## Трасса по замкнутой кривой Path3D (дочерний узел «Path»).
##
## По кривой строятся дорога, кирпичные стены по краям, фон за стенами
## (только декорация), стартовая линия и арка (в узле «Generated», который не
## сохраняется в сцену). В редакторе трасса перестраивается при каждом
## изменении кривой.
##
## Как в оригинале, кирпич — это стена: по нему не ездят, с трассы не выехать.
## Видимая стена невысокая (в оригинале она вообще плоская), а невидимая стена
## коллизии по краю дороги высокая, чтобы её нельзя было перепрыгнуть.
##
## Точка 0 кривой — линия старта/финиша, направление кривой — направление гонки.
## Логика гонки берёт отсюда длину трассы, чекпоинты (равные отрезки, чекпоинт 0 —
## линия старта), стартовую решётку и проекцию позиции на центральную линию.

const PATH_NODE := ^"Path"
const LIQUID_SHADER := preload("res://assets/shaders/liquid.gdshader")
const GENERATED_NAME := "Generated"
## Холмы окружения: клетка сетки и ровная площадка у стены, м.
const HILLS_CELL := 1.5
## Длина плавного перехода ширины проезда: метров пути на метр сдвига стены с каждой стороны
## (сужение 12 -> 6 м — 12 м пути; раньше был скос под 45°, на глаз — резкая ступенька).
const WIDTH_TRANSITION := 4.0
## Шаг поперечных рядов ленты на переходе ширины, м (чтобы плавная кривая не ломалась).
const WIDTH_TRANSITION_ROW := 0.75
const HILLS_PLATEAU := 1.5

@export_group("Размеры")
## Ширина дороги, м (в оригинале 3–4 тайла по 3 м).
@export var road_width: float = 12.0:
	set(value):
		road_width = value
		_queue_rebuild()
## Ширина кирпичной стены с каждой стороны, м.
## Стены по краям дороги (кирпич + высокая невидимая стена коллизии). Выключить — край
## открыт, с дороги можно упасть (как Rainbow Road): машина вернётся на последний чекпоинт,
## когда упадёт на FALL_DEPTH ниже самой низкой точки трассы. Края дороги — бортик вниз.
@export var walls: bool = true:
	set(value):
		walls = value
		_queue_rebuild()
@export var wall_width: float = 3.0:
	set(value):
		wall_width = maxf(value, 0.1)
		_queue_rebuild()
## Высота видимой стены, м.
@export var wall_height: float = 0.5:
	set(value):
		wall_height = maxf(value, 0.0)
		_queue_rebuild()
## Высота невидимой стены коллизии по краю дороги, м.
@export var wall_collision_height: float = 4.0:
	set(value):
		wall_collision_height = maxf(value, 0.1)
		_queue_rebuild()
## Шаг сетки вдоль трассы, м.
@export var mesh_step: float = 2.0:
	set(value):
		mesh_step = maxf(value, 0.25)
		_queue_rebuild()
## Примерный размер плитки текстуры дороги, м (подгоняется, чтобы круг был без шва).
## Тайл оригинала — 24 px = 3 м.
@export var road_tile_size: float = 3.0:
	set(value):
		road_tile_size = maxf(value, 0.1)
		_queue_rebuild()
@export var wall_tile_size: float = 3.0:
	set(value):
		wall_tile_size = maxf(value, 0.1)
		_queue_rebuild()
## Размер фона вокруг трассы (декорация за стенами), м.
@export var background_size: float = 1500.0:
	set(value):
		background_size = value
		_queue_rebuild()
## Течение фона, м/с (в оригинале кислота и вода сдвигаются на 8 и −16 px/с = 1 и −2 м/с).
@export var background_scroll: Vector2 = Vector2.ZERO
## Отражения в жидком фоне (WaterReflection: эстакада, опоры и машины отражаются в воде).
## Вторая камера — мир рисуется ещё раз в половинном разрешении; только в игре.
@export var background_reflection: bool = false
## Своя картинка фона (вместо background_material): повторяется плиткой по миру (не одна на
## весь фон в 1500 м — иначе растянута в мутное пятно), пиксели чёткие (Nearest).
@export var background_texture: Texture2D:
	set(value):
		background_texture = value
		_queue_rebuild()
## Сколько метров занимает одна картинка своего фона.
@export var background_tile_size: float = 32.0:
	set(value):
		background_tile_size = maxf(value, 1.0)
		_queue_rebuild()
## Свой фон светится сам — без солнца и теней (космос, небо Rainbow Road).
@export var background_unshaded: bool = false:
	set(value):
		background_unshaded = value
		_queue_rebuild()

@export_group("Окружение")
## Полоса за стенами с каждой стороны, м (как в оригинале: песок пляжа, плитка бассейна,
## бетон завода вокруг дороги, дальше — фон). 0 — сразу фон.
@export var surround_width: float = 0.0:
	set(value):
		surround_width = maxf(value, 0.0)
		_queue_rebuild()
## Вид окружения: ровная полоса (плитка, бетон) или холмы — насыпь с буграми, на которой
## стоит трасса (песок Пляжа); склон уходит под фон, поэтому холмам нужен background_depth > 0.
enum SurroundStyle { BAND, HILLS }
@export var surround_style: SurroundStyle = SurroundStyle.BAND:
	set(value):
		surround_style = value
		_queue_rebuild()
## Высота бугров на склонах холмов, м.
@export var hills_height: float = 2.0:
	set(value):
		hills_height = maxf(value, 0.0)
		_queue_rebuild()
## Цвет дымки вдали и неба за краем карты (сцена гонки ставит его в Environment).
@export var haze_color: Color = Color(0.72, 0.82, 0.95)
## Освещение карты (сцена гонки ставит его солнцу и Environment). По умолчанию — как в сцене
## гонки (день); ночная карта («Хэллоуин») — голубая луна, тусклое небо, дымка ближе.
@export var sun_color: Color = Color.WHITE
@export var sun_energy: float = 0.85
@export var ambient_color: Color = Color(0.8, 0.85, 0.95)
@export var ambient_energy: float = 0.4
## Дымка: с какого и до какого расстояния, м.
@export var haze_begin: float = 60.0
@export var haze_end: float = 240.0
## Материал полосы; пусто — материал стены с текстурой по мировым координатам.
@export var surround_material: Material:
	set(value):
		surround_material = value
		_queue_rebuild()

@export_group("Эстакада")
## Насколько фон ниже дороги, м. Больше нуля — трасса-эстакада над фоном
## (как «Хим. зона» оригинала: колонны 6 м под дорогой).
@export var background_depth: float = 0.0:
	set(value):
		background_depth = maxf(value, 0.0)
		_queue_rebuild()
## Толщина настила под стенами, м (видна на эстакаде).
@export var deck_thickness: float = 0.6:
	set(value):
		deck_thickness = maxf(value, 0.0)
		_queue_rebuild()
## Опора эстакады; ставится автоматически по обоим краям, если задана и фон ниже дороги.
## Начало координат сцены опоры — верх опоры.
@export var support_scene: PackedScene:
	set(value):
		support_scene = value
		_queue_rebuild()
## Шаг опор вдоль трассы, м.
@export var support_spacing: float = 24.0:
	set(value):
		support_spacing = maxf(value, 4.0)
		_queue_rebuild()

## Форма трассы по точкам кривой.
enum Shape {
	## Ломаная со скруглёнными углами (как тайловые трассы оригинала: прямые и крутые повороты).
	ROUNDED_CORNERS,
	## Гладкая кривая (ручки точек — Catmull-Rom или вручную, см. auto_smooth).
	SMOOTH,
}

@export_group("Кривая")
@export var shape: Shape = Shape.ROUNDED_CORNERS:
	set(value):
		shape = value
		_queue_rebuild()
## Радиус скругления углов ломаной по центральной линии, м (режим ROUNDED_CORNERS).
## Не меньше половины дороги + ширины стены, иначе внутренний край в углу складывается.
@export var corner_radius: float = 10.0:
	set(value):
		corner_radius = maxf(value, 0.0)
		_queue_rebuild()
## Режим SMOOTH: ручки точек вычисляются автоматически по соседям (Catmull-Rom).
## Выключи, если хочешь править ручки кривой вручную.
@export var auto_smooth: bool = true:
	set(value):
		auto_smooth = value
		_queue_rebuild()
@export_range(0.0, 1.5) var smooth_tension: float = 1.0:
	set(value):
		smooth_tension = value
		_queue_rebuild()
## Разрывы для порталов: номер точки ломаной, от которой до следующей точки дороги нет —
## машину переносит портал (Portal в конце дороги перед разрывом, выход — после него).
## Углы у концов разрыва не скругляются, дорога у разрыва закрыта стеной.
@export var portal_gaps: PackedInt32Array = PackedInt32Array():
	set(value):
		portal_gaps = value
		_queue_rebuild()
## Ширина проезда по участкам ломаной, м: i-й элемент — участок от точки i до точки i+1
## (как в оригинале: проезд в 2 блока = 6 м, дальше в 4 = 12 м); 0 или нет элемента —
## road_width. Уже road_width — сама трасса (стены снаружи, окружение, опоры) прежней ширины,
## а стена утолщается внутрь, как кирпичные блоки на дороге оригинала; шире — трасса
## расширяется. Меняется у точки плавно (WIDTH_TRANSITION м пути на метр сужения с каждой
## стороны), поровну в обе стороны. Чтобы сменить ширину посреди прямой — добавь там точку.
@export var segment_widths: PackedFloat32Array = PackedFloat32Array():
	set(value):
		segment_widths = value
		_queue_rebuild()

@export_group("Редактор карт")
## Показывать в редакторе полосы (куда редактор ставит объекты) и отметки каждые 10 м.
@export var editor_guides: bool = true:
	set(value):
		editor_guides = value
		_queue_rebuild()

@export_group("Гонка")
## Число логических чекпоинтов на круг. Круг засчитывается, только если пройдены все по порядку.
@export_range(4, 128) var checkpoint_count: int = 16
## Стартовая решётка: расстояние от линии старта до первой машины, м.
@export var grid_first_offset: float = 8.0
## Расстояние между рядами решётки, м.
@export var grid_row_spacing: float = 7.0
## Сдвиг правой колонки назад относительно левой, м.
@export var grid_stagger: float = 3.5

@export_group("Материалы")
@export var road_material: Material:
	set(value):
		road_material = value
		_queue_rebuild()
@export var wall_material: Material:
	set(value):
		wall_material = value
		_queue_rebuild()
@export var background_material: Material:
	set(value):
		background_material = value
		_queue_rebuild()
@export var start_line_material: Material:
	set(value):
		start_line_material = value
		_queue_rebuild()
## Арка старта/финиша, ставится на линию старта (в оригинале — объект Start, не твёрдый).
@export var start_gate_scene: PackedScene:
	set(value):
		start_gate_scene = value
		_queue_rebuild()
## Ширина арки в её сцене, м; арка растягивается до ширины дороги.
@export var start_gate_width: float = 12.0:
	set(value):
		start_gate_width = maxf(value, 0.1)
		_queue_rebuild()

@export_group("Звук")
## Музыка карты: играет через 0.4 с после старта (у карт оригинала — своя: MapA GhostTown…).
@export var music: AudioStream

## Длина круга по центральной линии, м.
var length: float = 0.0

# Центральная линия в локальных координатах трассы; последняя точка совпадает с первой.
var _points: PackedVector3Array = PackedVector3Array()
## Сетка холмов окружения (origin, nx, nz, heights) — для декора на склонах.
var _hills: Dictionary = {}
var _distances: PackedFloat32Array = PackedFloat32Array()
# Разрывы (порталы): отрезки [от, до] расстояния от старта без дороги; отрезки центральной
# линии внутри разрыва (1) не участвуют в проекции.
var _gaps: Array[Vector2] = []
var _segment_in_gap: PackedByteArray = PackedByteArray()
## Ширина по участкам (segment_widths): начало участка (м от старта) и полуширина дороги.
## Пусто — ширина везде road_width.
var _width_offsets: PackedFloat32Array = PackedFloat32Array()
var _width_halves: PackedFloat32Array = PackedFloat32Array()
var _rebuild_queued: bool = false
var _updating_curve: bool = false
var _watched_curve: Curve3D


func _ready() -> void:
	rebuild()


## Полностью перестроить трассу по текущей кривой.
func rebuild() -> void:
	_rebuild_queued = false
	var path := get_node_or_null(PATH_NODE) as Path3D
	if path == null or path.curve == null or path.curve.point_count < 3:
		push_warning("Track: нужен дочерний Path3D «Path» с кривой минимум из 3 точек.")
		_clear_generated()
		length = 0.0
		return
	var curve := path.curve
	_watch_curve(curve)
	_updating_curve = true
	if not curve.closed:
		curve.closed = true
	if shape == Shape.SMOOTH and auto_smooth:
		_smooth_curve(curve)
	_updating_curve = false
	var effective := curve
	if shape == Shape.ROUNDED_CORNERS:
		# Кривая в редакторе остаётся ломаной, скругление строится отдельно.
		effective = _rounded_corners_curve(curve)
	_cache_center_line(effective, path.transform)
	_cache_gaps(curve, path.transform)
	_cache_widths(curve, path.transform)
	_build_geometry()


# --------------------------------------------------------------------------
# Запросы для гонки и ботов (глобальные координаты)
# --------------------------------------------------------------------------

## Точка центральной линии на расстоянии offset от старта (+ смещение вбок, м; плюс — вправо).
## Ширина полосы сетки дороги поперёк, м (_road_profile).
const ROAD_STRIP := 1.5
## Насколько ниже самой низкой точки трассы машина считается упавшей, м.
const FALL_DEPTH := 15.0


## Высота самой низкой точки центральной линии (мир).
func lowest_point_y() -> float:
	var lowest := INF
	for p in _points:
		lowest = minf(lowest, (global_transform * p).y if is_inside_tree() else p.y)
	return 0.0 if lowest == INF else lowest


## Высота, ниже которой машина упала с трассы (CarController.kill_height; ставит Race).
func fall_height() -> float:
	return lowest_point_y() - FALL_DEPTH


func get_point_at(offset: float, lateral: float = 0.0) -> Vector3:
	var local_dir := get_local_direction(offset)
	var right := _right_of(local_dir)
	return to_global(get_local_point(offset) + right * lateral)


## Направление гонки в точке offset (единичный вектор).
func get_direction_at(offset: float) -> Vector3:
	return (global_basis * get_local_direction(offset)).normalized()


## Трансформ для машины: на трассе, носом по ходу гонки, без крена.
func get_transform_at(offset: float, lateral: float = 0.0) -> Transform3D:
	var dir := get_direction_at(offset)
	dir.y = 0.0
	if dir.length_squared() < 1e-6:
		dir = Vector3.FORWARD
	var facing := Basis.looking_at(dir.normalized(), Vector3.UP)
	return Transform3D(facing, get_point_at(offset, lateral) + Vector3.UP * 0.1)


## Расстояние от старта до чекпоинта index.
func get_checkpoint_offset(index: int) -> float:
	return length * float(index) / float(checkpoint_count)


## Чекпоинт index начинается в разрыве (портал): проехать его нельзя, его засчитывают,
## когда машина оказалась дальше.
func is_checkpoint_in_gap(index: int) -> bool:
	return is_in_gap(get_checkpoint_offset(index))


## Расстояние offset приходится на разрыв дороги (портал).
func is_in_gap(offset: float) -> bool:
	var d := fposmod(offset, length) if length > 0.0 else 0.0
	for gap in _gaps:
		if d > gap.x and d < gap.y:
			return true
	return false


## Ближайшее место на дороге для машины: из разрыва и вплотную к его концу — за торцевую
## стену у выхода портала (машина длиной 3 м целиком на дороге).
func clamp_to_road(offset: float) -> float:
	const CLEAR := 3.0
	var d := fposmod(offset, length) if length > 0.0 else 0.0
	for gap in _gaps:
		if d > gap.x and d < gap.y + CLEAR:
			return gap.y + CLEAR
	return offset


## Разрывы дороги (порталы): [от, до] расстояния от старта.
func get_gaps() -> Array[Vector2]:
	return _gaps.duplicate()


## Сколько дороги (без разрывов) между расстояниями from и to (from ≤ to, можно через круг).
func road_length_between(from: float, to: float) -> float:
	var total := to - from
	for gap in _gaps:
		for lap_shift in [0.0, length]:
			var a := maxf(from, gap.x + lap_shift)
			var b := minf(to, gap.y + lap_shift)
			if b > a:
				total -= b - a
	return total


## Точка, куда смотреть на offset + ahead по дороге: перед разрывом — дальше по прямой
## подъезда к порталу (сам разрыв — прямая между входом и выходом, по ней не едут).
func get_road_point_ahead(offset: float, ahead: float, lateral: float = 0.0) -> Vector3:
	var d := fposmod(offset, length) if length > 0.0 else 0.0
	for gap in _gaps:
		var to_gap := gap.x - d
		if to_gap >= 0.0 and to_gap < ahead:
			var before := maxf(gap.x - 1.0, d)
			return get_point_at(before, lateral) + get_direction_at(before) * (ahead - (before - d))
	return get_point_at(offset + ahead, lateral)


## Длина одного отрезка между чекпоинтами.
func get_checkpoint_length() -> float:
	return length / float(checkpoint_count)


## Место на стартовой решётке: две колонки со сдвигом, ряды назад от линии старта.
func get_grid_transform(slot: int) -> Transform3D:
	var row := floori(slot / 2.0)
	var column := slot % 2
	var back := grid_first_offset + row * grid_row_spacing + column * grid_stagger
	var lateral := road_half_width_at(-back) * 0.44 * (-1.0 if column == 0 else 1.0)
	return get_transform_at(-back, lateral)


## Проекция точки на центральную линию.
## hint — номер отрезка с прошлого раза (-1 — искать по всей трассе),
## window — сколько метров в обе стороны от hint просматривать.
## Возвращает {offset: расстояние от старта, distance: до линии, segment: номер отрезка}.
func project(global_pos: Vector3, hint: int = -1, window: float = 40.0) -> Dictionary:
	var segments := _points.size() - 1
	if segments < 1:
		return {"offset": 0.0, "distance": 0.0, "segment": 0}
	var p := to_local(global_pos)
	var start := 0
	var count := segments
	if hint >= 0:
		var half := mini(int(window / maxf(length / segments, 0.01)) + 1, floori(segments / 2.0))
		start = hint - half
		count = half * 2 + 1
	var best_segment := 0
	var best_t := 0.0
	var best_d2 := INF
	var skip_gaps := _segment_in_gap.size() == segments
	for k in count:
		var i := posmod(start + k, segments)
		if skip_gaps and _segment_in_gap[i] == 1:
			continue
		var a := _points[i]
		var ab := _points[i + 1] - a
		var len2 := ab.length_squared()
		var t := 0.0 if len2 < 1e-9 else clampf((p - a).dot(ab) / len2, 0.0, 1.0)
		var d2 := p.distance_squared_to(a + ab * t)
		if d2 < best_d2:
			best_d2 = d2
			best_segment = i
			best_t = t
	var offset := lerpf(_distances[best_segment], _distances[best_segment + 1], best_t)
	return {"offset": offset, "distance": sqrt(best_d2), "segment": best_segment}


# --------------------------------------------------------------------------
# Центральная линия (локальные координаты)
# --------------------------------------------------------------------------

func get_local_point(offset: float) -> Vector3:
	if _points.size() < 2 or length <= 0.0:
		return Vector3.ZERO
	var d := fposmod(offset, length)
	var i := clampi(_distances.bsearch(d, false) - 1, 0, _points.size() - 2)
	var segment_length := _distances[i + 1] - _distances[i]
	var t := 0.0 if segment_length <= 0.0 else (d - _distances[i]) / segment_length
	return _points[i].lerp(_points[i + 1], t)


func get_local_direction(offset: float) -> Vector3:
	var dir := get_local_point(offset + 1.0) - get_local_point(offset - 1.0)
	return dir.normalized() if dir.length_squared() > 1e-8 else Vector3.FORWARD


func _direction_within(offset: float, d0: float, d1: float) -> Vector3:
	var dir := get_local_point(minf(offset + 1.0, d1)) - get_local_point(maxf(offset - 1.0, d0))
	return dir.normalized() if dir.length_squared() > 1e-8 else get_local_direction(offset)


func _right_of(dir: Vector3) -> Vector3:
	var right := dir.cross(Vector3.UP)
	return right.normalized() if right.length_squared() > 1e-8 else Vector3.RIGHT


## Ломаная по точкам curve (ручки игнорируются) со скруглёнными углами:
## прямые участки между точками, в каждом углу — дуга радиуса corner_radius
## (кубическая Безье, близкая к окружности). Если угол в точке 0 почти нулевой,
## линия старта стоит ровно в ней — ставь точку 0 на прямой.
func _rounded_corners_curve(source: Curve3D) -> Curve3D:
	var result := Curve3D.new()
	result.bake_interval = source.bake_interval
	var n := source.point_count
	for i in n:
		var p := source.get_point_position(i)
		var prev := source.get_point_position(posmod(i - 1, n))
		var next := source.get_point_position((i + 1) % n)
		var to_prev := prev - p
		var to_next := next - p
		if to_prev.length_squared() < 1e-6 or to_next.length_squared() < 1e-6:
			result.add_point(p)
			continue
		var d_in := -to_prev.normalized()
		var d_out := to_next.normalized()
		var turn := d_in.angle_to(d_out)
		var at_gap := portal_gaps.has(i) or portal_gaps.has(posmod(i - 1, n))
		if turn < deg_to_rad(1.0) or corner_radius <= 0.0 or at_gap:
			result.add_point(p)
			continue
		# Отступ от вершины до начала дуги; не больше 45 % каждого соседнего отрезка.
		var t := minf(corner_radius * tan(turn * 0.5),
				minf(to_prev.length(), to_next.length()) * 0.45)
		var radius := t / tan(turn * 0.5)
		# Длина ручек Безье для дуги окружности с углом turn.
		var handle := 4.0 / 3.0 * tan(turn * 0.25) * radius
		result.add_point(p - d_in * t, Vector3.ZERO, d_in * handle)
		result.add_point(p + d_out * t, -d_out * handle, Vector3.ZERO)
	result.closed = true
	return result


func _cache_center_line(curve: Curve3D, curve_transform: Transform3D) -> void:
	var baked := curve.get_baked_points()
	_points = PackedVector3Array()
	_distances = PackedFloat32Array()
	var total := 0.0
	for raw in baked:
		var p := curve_transform * raw
		if not _points.is_empty():
			var step := p.distance_to(_points[_points.size() - 1])
			if step < 1e-4:
				continue
			total += step
		_points.append(p)
		_distances.append(total)
	if _points.size() > 1 and _points[0].distance_to(_points[_points.size() - 1]) > 1e-3:
		total += _points[0].distance_to(_points[_points.size() - 1])
		_points.append(_points[0])
		_distances.append(total)
	length = total


## Разрывы portal_gaps -> отрезки расстояния: концы разрыва — вершины ломаной (не скруглены),
## они точно лежат на центральной линии.
func _cache_gaps(curve: Curve3D, curve_transform: Transform3D) -> void:
	_gaps.clear()
	_segment_in_gap = PackedByteArray()
	var n := curve.point_count
	for index in portal_gaps:
		if index < 0 or index >= n:
			continue
		var from := _offset_of_vertex(curve_transform * curve.get_point_position(index))
		var to := _offset_of_vertex(curve_transform * curve.get_point_position((index + 1) % n))
		if from < 0.0 or to < 0.0:
			continue
		if to <= from:
			to += length  # разрыв через линию старта не поддерживается — старт ставь не в разрыв
		if to - from < length * 0.5:
			_gaps.append(Vector2(from, to))
	if _gaps.is_empty():
		return
	_segment_in_gap.resize(_points.size() - 1)
	for i in _points.size() - 1:
		var middle := (_distances[i] + _distances[i + 1]) * 0.5
		_segment_in_gap[i] = 1 if is_in_gap(middle) else 0


func _offset_of_vertex(p: Vector3) -> float:
	var best := -1.0
	var best_d2 := 0.01
	for i in _points.size():
		var d2 := _points[i].distance_squared_to(p)
		if d2 < best_d2:
			best_d2 = d2
			best = _distances[i]
	return best


## Ширина по участкам: где начинается участок каждой точки ломаной (ближайшее место
## центральной линии — у скруглённого угла это середина дуги) и его полуширина.
func _cache_widths(curve: Curve3D, curve_transform: Transform3D) -> void:
	_width_offsets = PackedFloat32Array()
	_width_halves = PackedFloat32Array()
	var custom := false
	for width in segment_widths:
		if width > 0.0 and not is_equal_approx(width, road_width):
			custom = true
	if not custom:
		return
	var previous := -1.0
	for i in curve.point_count:
		var width := segment_widths[i] if i < segment_widths.size() and segment_widths[i] > 0.0 else road_width
		var offset := 0.0 if i == 0 else _nearest_offset(curve_transform * curve.get_point_position(i))
		if offset <= previous:
			continue
		_width_offsets.append(offset)
		_width_halves.append(width * 0.5)
		previous = offset


func _nearest_offset(p: Vector3) -> float:
	var best := 0.0
	var best_d2 := INF
	for i in _points.size():
		var d2 := _points[i].distance_squared_to(p)
		if d2 < best_d2:
			best_d2 = d2
			best = _distances[i]
	return best


## Полуширина проезда (дороги между стенами) в точке offset: segment_widths, между участками —
## плавный переход (smoothstep) длиной _transition_length.
func road_half_width_at(offset: float) -> float:
	if _width_offsets.is_empty() or length <= 0.0:
		return road_width * 0.5
	var d := fposmod(offset, length)
	var n := _width_offsets.size()
	var i := _width_offsets.bsearch(d, false) - 1
	if i < 0:
		i = n - 1
	var half := _width_halves[i]
	var span := _transition_length(i)
	var into := fposmod(d - _width_offsets[i], length)
	if span > 0.0 and into < span * 0.5:
		return lerpf(_width_halves[(i - 1 + n) % n], half, smoothstep(0.0, 1.0, 0.5 + into / span))
	var next := (i + 1) % n
	span = _transition_length(next)
	var left := fposmod(_width_offsets[next] - d, length)
	if span > 0.0 and left < span * 0.5:
		return lerpf(_width_halves[next], half, smoothstep(0.0, 1.0, 0.5 + left / span))
	return half


## Полуширина самой трассы (до внутренней стороны стен снаружи) в offset: не уже road_width —
## узкий проезд делают толстые стены, а не узкая трасса. По ней — окружение, холмы, опоры.
## Без стен (walls = false) утолщать нечего — сужается сама дорога.
func outline_half_width_at(offset: float) -> float:
	if not walls:
		return road_half_width_at(offset)
	return maxf(road_width * 0.5, road_half_width_at(offset))


## Длина перехода ширины в начале участка j (м пути): по WIDTH_TRANSITION, но не длиннее
## соседних участков — переходы не наползают друг на друга.
func _transition_length(j: int) -> float:
	var n := _width_offsets.size()
	var before := (j - 1 + n) % n
	var span := absf(_width_halves[j] - _width_halves[before]) * WIDTH_TRANSITION
	if span <= 0.0:
		return 0.0
	var own := fposmod(_width_offsets[(j + 1) % n] - _width_offsets[j], length)
	var previous := fposmod(_width_offsets[j] - _width_offsets[before], length)
	if n == 1:
		own = length
		previous = length
	return minf(span, minf(own, previous))


## Номер участка ломаной (от точки i до i+1) в месте offset — для segment_widths.
func segment_at(offset: float) -> int:
	var path := get_node_or_null(PATH_NODE) as Path3D
	if path == null or path.curve == null or length <= 0.0:
		return -1
	var d := fposmod(offset, length)
	var found := path.curve.point_count - 1
	var previous := -1.0
	for i in path.curve.point_count:
		var start := 0.0 if i == 0 else _nearest_offset(path.transform * path.curve.get_point_position(i))
		if start <= previous:
			continue
		previous = start
		if start <= d:
			found = i
	return found


## Ширина участка i (segment_widths или road_width), м.
func segment_width(i: int) -> float:
	return segment_widths[i] if i >= 0 and i < segment_widths.size() and segment_widths[i] > 0.0 else road_width


## Самая большая и самая маленькая ширина дороги на круге, м.
func max_road_width() -> float:
	var widest := road_width * 0.5
	for half in _width_halves:
		widest = maxf(widest, half)
	return widest * 2.0 if not _width_halves.is_empty() else road_width


func min_road_width() -> float:
	if _width_halves.is_empty():
		return road_width
	var narrowest := INF
	for half in _width_halves:
		narrowest = minf(narrowest, half)
	return narrowest * 2.0


## Места, где строить поперечный ряд ленты: равный шаг mesh_step + частые ряды на переходах
## ширины (иначе плавный переход размазался бы по шагу сетки ломаной).
func _row_offsets(d0: float, d1: float) -> PackedFloat32Array:
	var steps := maxi(1, ceili((d1 - d0) / mesh_step))
	var list: Array[float] = []
	for i in steps + 1:
		list.append(lerpf(d0, d1, float(i) / steps))
	var n := _width_offsets.size()
	for j in n:
		var span := _transition_length(j)
		if span <= 0.0:
			continue
		var count := maxi(2, ceili(span / WIDTH_TRANSITION_ROW))
		for r in count + 1:
			var at := _width_offsets[j] - span * 0.5 + span * r / count
			for lap in [-1.0, 0.0, 1.0]:
				var x: float = at + lap * length
				if x > d0 + 0.05 and x < d1 - 0.05:
					list.append(x)
	list.sort()
	var rows := PackedFloat32Array()
	for x in list:
		if rows.is_empty() or x - rows[rows.size() - 1] > 0.05:
			rows.append(x)
	return rows


## Участки с дорогой (без разрывов): [от, до] по порядку.
func _road_ranges() -> Array[Vector2]:
	var ranges: Array[Vector2] = []
	if _gaps.is_empty():
		ranges.append(Vector2(0.0, length))
		return ranges
	var sorted := _gaps.duplicate()
	sorted.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var cursor := 0.0
	for gap in sorted:
		if gap.x > cursor:
			ranges.append(Vector2(cursor, gap.x))
		cursor = gap.y
	if cursor < length:
		ranges.append(Vector2(cursor, length))
	return ranges


## Ручки точек по соседям (сплайн Catmull-Rom). Меняет только то, что отличается,
## чтобы не зацикливать перестройку в редакторе.
func _smooth_curve(curve: Curve3D) -> void:
	var n := curve.point_count
	for i in n:
		var prev := curve.get_point_position(posmod(i - 1, n))
		var next := curve.get_point_position((i + 1) % n)
		var handle := (next - prev) * (smooth_tension / 6.0)
		if not curve.get_point_out(i).is_equal_approx(handle):
			curve.set_point_out(i, handle)
		if not curve.get_point_in(i).is_equal_approx(-handle):
			curve.set_point_in(i, -handle)


func _watch_curve(curve: Curve3D) -> void:
	if not Engine.is_editor_hint() or curve == _watched_curve:
		return
	if _watched_curve != null and _watched_curve.changed.is_connected(_on_curve_changed):
		_watched_curve.changed.disconnect(_on_curve_changed)
	curve.changed.connect(_on_curve_changed)
	_watched_curve = curve


func _on_curve_changed() -> void:
	if not _updating_curve:
		_queue_rebuild()


func _queue_rebuild() -> void:
	if not is_inside_tree() or _rebuild_queued:
		return
	_rebuild_queued = true
	rebuild.call_deferred()


# --------------------------------------------------------------------------
# Геометрия
# --------------------------------------------------------------------------

func _clear_generated() -> void:
	var old := get_node_or_null(GENERATED_NAME)
	if old != null:
		remove_child(old)
		old.queue_free()


func _build_geometry() -> void:
	_clear_generated()
	if length <= 0.0:
		return
	var root := Node3D.new()
	root.name = GENERATED_NAME
	add_child(root)

	var half := road_width * 0.5
	var edge := half + wall_width

	# Дорога и стены — одно статическое тело.
	var body := StaticBody3D.new()
	body.name = "TrackBody"
	root.add_child(body)
	var road_tile := _fit_tile(road_tile_size)
	# Стены и полоса окружения — с текстурой по мировым координатам и плоскими нормалями:
	# на внутренней стороне поворотов лента складывается сама на себя (радиус скругления меньше
	# половины дороги + стены + полосы), и наложенные копии с разной разметкой или освещением
	# мерцали бы (Z-fighting); так они рисуют одно и то же.
	var wall_world := _world_material(wall_material)
	var wall_tile := _fit_tile(wall_tile_size)
	# Внешний бок стены уходит вниз на толщину настила (на эстакаде видно край «моста»).
	var bottom := -deck_thickness
	var ranges := _road_ranges()
	for r in ranges.size():
		# Без разрывов имена прежние (Road, WallLeft…), с разрывами — с номером участка.
		var suffix := "" if ranges.size() == 1 else str(r + 1)
		var d0 := ranges[r].x
		var d1 := ranges[r].y
		_add_ribbon(body, "Road" + suffix, _road_profile(half), d0, d1, road_tile, road_material, true)
		# Кирпичные стены: видимый П-образный профиль (бок к дороге, верх, внешний бок)
		# и высокая невидимая стена коллизии по краю дороги.
		# С полосой окружения внешний бок стены опускается до её уровня, а край «моста»
		# (настил на эстакаде) — уже у края полосы.
		var outer := edge + surround_width
		var band := surround_width > 0.0 and surround_style == SurroundStyle.BAND
		var wall_foot := 0.0 if band else bottom
		if not walls:
			# Без стен: только бортики дороги вниз на толщину настила (видно край «ленты»).
			_add_ribbon(body, "EdgeLeft" + suffix, [Vector2(-half, bottom), Vector2(-half, 0.03)],
					d0, d1, road_tile, road_material, false, true)
			_add_ribbon(body, "EdgeRight" + suffix, [Vector2(half, 0.03), Vector2(half, bottom)],
					d0, d1, road_tile, road_material, false, true)
			continue
		# Левые профили — в обратном порядке: зеркало правого с тем же порядком вывернуто
		# наизнанку (лицевая сторона внутрь), а материалы с мировой текстурой односторонние.
		_add_ribbon(body, "WallLeft" + suffix, [Vector2(-edge, wall_foot), Vector2(-edge, wall_height),
				Vector2(-half, wall_height), Vector2(-half, 0.0)],
				d0, d1, wall_tile, wall_world, false, true)
		_add_ribbon(body, "WallRight" + suffix, [Vector2(half, 0.0), Vector2(half, wall_height),
				Vector2(edge, wall_height), Vector2(edge, wall_foot)],
				d0, d1, wall_tile, wall_world, false, true)
		if band:
			var material := _surround_material()
			_add_ribbon(root, "SurroundLeft" + suffix, [Vector2(-outer, bottom), Vector2(-outer, 0.0),
					Vector2(-edge, 0.0)], d0, d1, wall_tile, material, false, true)
			_add_ribbon(root, "SurroundRight" + suffix, [Vector2(edge, 0.0), Vector2(outer, 0.0),
					Vector2(outer, bottom)], d0, d1, wall_tile, material, false, true)
		_add_collision_ribbon(body, "WallLeftCollision" + suffix,
				[Vector2(-half, -1.0), Vector2(-half, wall_collision_height)], d0, d1)
		_add_collision_ribbon(body, "WallRightCollision" + suffix,
				[Vector2(half, -1.0), Vector2(half, wall_collision_height)], d0, d1)
	# Концы дороги у разрыва закрыты кирпичной стеной поперёк.
	for g in _gaps.size():
		_add_end_wall(body, "GapWallIn%d" % (g + 1), _gaps[g].x, 1.0, outline_half_width_at(_gaps[g].x) + wall_width)
		_add_end_wall(body, "GapWallOut%d" % (g + 1), _gaps[g].y, -1.0, outline_half_width_at(_gaps[g].y) + wall_width)

	# Шахматная линия старта (метр в обе стороны от точки 0).
	_add_ribbon(root, "StartLine", [Vector2(-half, 0.04), Vector2(half, 0.04)],
			-1.0, 1.0, 2.0, start_line_material, false)

	_add_background(root)
	_hills.clear()
	if surround_width > 0.0 and surround_style == SurroundStyle.HILLS:
		_add_hills(root, edge)
		_settle_decor()
	# Опоры — под внешним краем: под стеной или под краем полосы окружения.
	if walls:
		_add_supports(root, half + wall_width * 0.5 + maxf(surround_width - 1.5, 0.0))
	else:
		_add_supports(root, half - 1.0)

	if start_gate_scene != null:
		var gate := start_gate_scene.instantiate() as Node3D
		gate.name = "StartGate"
		root.add_child(gate)
		var dir := get_local_direction(0.0)
		dir.y = 0.0
		gate.transform = Transform3D(Basis.looking_at(dir.normalized(), Vector3.UP), get_local_point(0.0))
		# Арка рассчитана на ширину start_gate_width — растягиваем по ширине дороги.
		gate.scale = Vector3(road_half_width_at(0.0) * 2.0 / start_gate_width, 1.0, 1.0)

	if Engine.is_editor_hint() and editor_guides:
		_add_editor_guides(root)


## Подсказки редактора карт (в игре их нет): линии полос, на которые редактор ставит
## объекты (шаг TrackLayout.lane_step), поперечные отметки каждые 10 м и подписи каждые 50 м.
func _add_editor_guides(root: Node3D) -> void:
	var lane := road_width / TrackLayout.LANE_DIVISIONS
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	var lane_color := Color(1.0, 0.85, 0.2, 0.45)
	var tick_color := Color(1.0, 1.0, 1.0, 0.6)
	var half := max_road_width() * 0.5
	var k := -floori(half / lane)
	while k * lane <= half + 0.01:
		var lateral := k * lane
		var d := 0.0
		while d < length:
			var next := minf(d + mesh_step, length)
			# Полоса — только там, где дорога достаточно широкая (ширина по участкам).
			if is_in_gap((d + next) * 0.5) or absf(lateral) > road_half_width_at((d + next) * 0.5) + 0.01:
				d = next
				continue
			st.set_color(lane_color)
			st.add_vertex(_guide_point(d, lateral))
			st.set_color(lane_color)
			st.add_vertex(_guide_point(next, lateral))
			d = next
		k += 1
	var mark := 0.0
	while mark < length:
		var mark_half := road_half_width_at(mark)
		st.set_color(tick_color)
		st.add_vertex(_guide_point(mark, -mark_half))
		st.set_color(tick_color)
		st.add_vertex(_guide_point(mark, mark_half))
		if is_zero_approx(fmod(mark, 50.0)):
			var label := Label3D.new()
			label.text = "%d м" % int(mark)
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.no_depth_test = true
			label.pixel_size = 0.03
			label.position = _guide_point(mark, mark_half + 1.5) + Vector3.UP
			root.add_child(label)
		mark += 10.0
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	st.set_material(material)
	var guides := MeshInstance3D.new()
	guides.name = "EditorGuides"
	guides.mesh = st.commit()
	guides.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(guides)


func _guide_point(offset: float, lateral: float) -> Vector3:
	var dir := get_local_direction(offset)
	return get_local_point(offset) + _right_of(dir) * lateral + Vector3.UP * 0.08


## Размер плитки, при котором на круг укладывается целое число плиток (нет шва на старте).
func _fit_tile(size: float) -> float:
	return length / maxf(1.0, roundf(length / size))


## Лента вдоль трассы от d0 до d1 (м от старта) с поперечным профилем profile:
## ломаная из точек (смещение вбок от центра, м, плюс — вправо; высота, м).
## UV: u — вдоль профиля, v — вдоль трассы, плитка размером tile метров.
## flat_normals — нормаль у каждого треугольника своя (без сглаживания): там, где лента на
## внутренней стороне тесного поворота складывается сама на себя, наложенные куски с мировой
## текстурой и одинаковой нормалью рисуются одинаково и не мерцают (сглаженные нормали
## у складки «гуляют», и куски освещались бы по-разному). Перевёрнутые треугольники складки
## не рисуются: материал с мировой текстурой односторонний (_world_material).
func _build_ribbon_mesh(profile: Array, d0: float, d1: float, tile: float, flat_normals := false) -> ArrayMesh:
	var offsets := _row_offsets(d0, d1)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var previous := PackedVector3Array()
	var previous_us := PackedFloat32Array()
	var previous_v := 0.0
	for i in offsets.size():
		var d := offsets[i]
		var center := get_local_point(d)
		# У разрыва (портал) направление берётся только внутри участка: иначе край ленты
		# повернулся бы к прямой разрыва.
		var right := _right_of(_direction_within(d, d0, d1) if not _gaps.is_empty() else get_local_direction(d))
		# Профили заданы для ширины road_width. На участке другой ширины дорога и внутренняя
		# сторона стен (|x| до края дороги) растягиваются под ширину проезда, а всё дальше
		# (верх и внешний бок стены, окружение) сдвигается по ширине трассы: на узком проезде
		# стена толще, сама трасса прежняя.
		var base_half := road_width * 0.5
		var squeeze := road_half_width_at(d) / base_half
		var widen := outline_half_width_at(d) - base_half
		var row := PackedVector3Array()
		# Координата u каждой точки профиля: начало + длина ломаной до неё.
		var us := PackedFloat32Array()
		var last := Vector2.ZERO
		var u := 0.0
		for k in profile.size():
			var point: Vector2 = profile[k]
			if absf(point.x) <= base_half + 0.001:
				point.x *= squeeze
			else:
				point.x += signf(point.x) * widen
			u = point.x if k == 0 else u + point.distance_to(last)
			last = point
			us.append(u / tile)
			row.append(center + right * point.x + Vector3.UP * point.y)
		var v := d / tile
		if i > 0:
			for k in profile.size() - 1:
				# Обход по часовой стрелке для ленты, идущей слева направо и вверх
				# (лицевая сторона в Godot): дорога видна сверху.
				if flat_normals:
					st.set_normal(Plane(previous[k], row[k], row[k + 1]).normal)
				_add_vertex(st, previous[k], Vector2(previous_us[k], previous_v))
				_add_vertex(st, row[k], Vector2(us[k], v))
				_add_vertex(st, row[k + 1], Vector2(us[k + 1], v))
				if flat_normals:
					st.set_normal(Plane(previous[k], row[k + 1], previous[k + 1]).normal)
				_add_vertex(st, previous[k], Vector2(previous_us[k], previous_v))
				_add_vertex(st, row[k + 1], Vector2(us[k + 1], v))
				_add_vertex(st, previous[k + 1], Vector2(previous_us[k + 1], previous_v))
		previous = row
		previous_us = us
		previous_v = v
	if not flat_normals:
		st.generate_normals()
	return st.commit()


func _add_ribbon(parent: Node3D, ribbon_name: String, profile: Array, d0: float, d1: float,
		tile: float, material: Material, collide: bool, flat_normals := false) -> void:
	var mesh := _build_ribbon_mesh(profile, d0, d1, tile, flat_normals)
	if material != null:
		mesh.surface_set_material(0, material)
	var instance := MeshInstance3D.new()
	instance.name = ribbon_name
	instance.mesh = mesh
	parent.add_child(instance)
	if collide:
		_add_trimesh_collision(parent, ribbon_name + "Collision", mesh)


## Профиль дороги поперёк: полосы по ROAD_STRIP м. Из двух точек (только края) на повороте
## с подъёмом ряды сходятся у внутреннего края, и треугольник через всю ширину наклонялся как
## этот край: на середине дороги в 31° выходила грань в 54° — стена для машины.
func _road_profile(half: float) -> Array:
	var strips := maxi(ceili(half * 2.0 / ROAD_STRIP), 1)
	var profile := []
	for i in strips + 1:
		profile.append(Vector2(lerpf(-half, half, float(i) / strips), 0.03))
	return profile


## Только коллизия, без видимой сетки.
func _add_collision_ribbon(parent: Node3D, ribbon_name: String, profile: Array,
		d0: float = 0.0, d1: float = -1.0) -> void:
	_add_trimesh_collision(parent, ribbon_name, _build_ribbon_mesh(profile, d0, length if d1 < 0.0 else d1, 1.0))


## Кирпичная стена поперёк дороги у разрыва: side = 1 — за концом дороги (вход портала),
## −1 — перед началом (выход). Видимая — высотой со стены, коллизия — высокая.
func _add_end_wall(parent: Node3D, wall_name: String, offset: float, side: float, edge: float) -> void:
	var dir := get_local_direction(offset - side * 1.5)
	dir.y = 0.0
	var facing := Basis.looking_at(dir.normalized(), Vector3.UP)
	var center := get_local_point(offset) + dir.normalized() * side * wall_width * 0.5
	var box := BoxMesh.new()
	box.size = Vector3(edge * 2.0, wall_height + deck_thickness, wall_width)
	box.material = _world_material(wall_material)
	var mesh := MeshInstance3D.new()
	mesh.name = wall_name
	mesh.mesh = box
	mesh.transform = Transform3D(facing, center + Vector3.UP * (wall_height - deck_thickness) * 0.5)
	parent.add_child(mesh)
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(edge * 2.0, wall_collision_height + 1.0, wall_width)
	var collision := CollisionShape3D.new()
	collision.name = wall_name + "Collision"
	collision.shape = box_shape
	collision.transform = Transform3D(facing, center + Vector3.UP * (wall_collision_height - 1.0) * 0.5)
	parent.add_child(collision)


func _add_trimesh_collision(parent: Node3D, collision_name: String, mesh: ArrayMesh) -> void:
	var trimesh := mesh.create_trimesh_shape()
	trimesh.backface_collision = true
	var collision := CollisionShape3D.new()
	collision.name = collision_name
	collision.shape = trimesh
	parent.add_child(collision)


func _add_vertex(st: SurfaceTool, point: Vector3, uv: Vector2) -> void:
	st.set_uv(uv)
	st.add_vertex(point)


## Материал полосы окружения: свой или материал стены с текстурой по мировым координатам
## (плитка ложится одинаково, поэтому полосы соседних участков на тесных поворотах,
## наложившись, не мерцают).
func _surround_material() -> Material:
	if surround_material != null:
		return surround_material
	return _world_material(wall_material)


## Копия материала с текстурой по мировым координатам (плитка wall_tile_size метров).
func _world_material(source: Material) -> Material:
	var base := source as StandardMaterial3D
	if base == null:
		return source
	var material := base.duplicate() as StandardMaterial3D
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_scale = Vector3.ONE / maxf(wall_tile_size, 0.1)
	# Односторонний: изнанка (перевёрнутые треугольники на складке ленты) не рисуется —
	# у двустороннего материала она освещалась бы «снизу» и темнела полосами.
	material.cull_mode = BaseMaterial3D.CULL_BACK
	return material


## Фон (кислота, снег, вода…) — только декорация за стенами, без коллизии (туда не попасть).
func _add_background(root: Node3D) -> void:
	var bounds := AABB(_points[0], Vector3.ZERO)
	for p in _points:
		bounds = bounds.expand(p)
	var center := bounds.get_center()
	# Чуть ниже нуля: на ровной карте полоса окружения лежит на нуле и не должна мерцать с фоном.
	center.y = bounds.position.y - background_depth - 0.05

	var plane := PlaneMesh.new()
	plane.size = Vector2(background_size, background_size)
	var material := background_material
	if background_texture != null:
		material = _texture_background()
	plane.material = material
	# Текущий фон (вода, кислота, масло) — шейдер жидкости: два слоя, волны, блики.
	var source := material as StandardMaterial3D
	if source != null and source.albedo_texture != null and background_scroll != Vector2.ZERO:
		var liquid := ShaderMaterial.new()
		liquid.shader = LIQUID_SHADER
		liquid.set_shader_parameter(&"albedo_texture", source.albedo_texture)
		liquid.set_shader_parameter(&"tile_size", 1.0 / maxf(source.uv1_scale.x, 0.001))
		liquid.set_shader_parameter(&"flow", background_scroll)
		plane.material = liquid
	var instance := MeshInstance3D.new()
	instance.name = "Background"
	instance.mesh = plane
	instance.position = center
	root.add_child(instance)
	if background_reflection and not Engine.is_editor_hint() and plane.material is ShaderMaterial:
		instance.layers = WaterReflection.LAYER
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var reflection := WaterReflection.new()
		reflection.name = "WaterReflection"
		reflection.material = plane.material as ShaderMaterial
		reflection.water_height = (root.global_transform * center).y if root.is_inside_tree() else center.y
		root.add_child(reflection)


## Материал своего фона из background_texture: плитка по мировым координатам.
func _texture_background() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_texture = background_texture
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_scale = Vector3.ONE / background_tile_size
	if background_unshaded:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


## Холмы окружения: рельеф по сетке (клетка HILLS_CELL). Каждая точка центральной линии даёт
## «гору» по расстоянию за край стены: под дорогой и стенами — ниже дороги, у стены ровная
## площадка HILLS_PLATEAU на высоте дороги, дальше склон с буграми (шум) на surround_width метров
## уходит на 1.5 м под фон. Высота клетки — самая высокая из гор (поверхность непрерывна, и где
## рядом участки разной высоты, склоны плавно сливаются), но не выше дороги, под которой клетка.
## Низ склона — от уровня фона, а не от своей дороги: на поднятых участках (Y > 0) склон раньше
## обрывался в воздухе, а клетки «ниже дороги на глубину фона» выбрасывались — дыры.
## В отличие от ленты сетка не складывается на тесных поворотах — нечему мерцать.
func _add_hills(root: Node3D, edge: float) -> void:
	# edge — край стены при ширине road_width; на участках другой ширины край свой.
	var reach := edge + max_road_width() * 0.5 - road_width * 0.5 + HILLS_PLATEAU + surround_width
	var bounds := AABB(_points[0], Vector3.ZERO)
	for point in _points:
		bounds = bounds.expand(point)
	# Уровень фона (как в _add_background) и низ склонов под ним.
	var water := bounds.position.y - background_depth
	var bottom := water - 1.5
	bounds = bounds.grow(reach + HILLS_CELL)
	var origin := Vector2(bounds.position.x, bounds.position.z)
	var nx := ceili(bounds.size.x / HILLS_CELL) + 1
	var nz := ceili(bounds.size.z / HILLS_CELL) + 1
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.07
	noise.seed = 7
	var bumps := PackedFloat32Array()
	bumps.resize(nx * nz)
	for k in nx * nz:
		bumps[k] = noise.get_noise_2d(origin.x + (k % nx) * HILLS_CELL, origin.y + floorf(float(k) / nx) * HILLS_CELL) 				* hills_height
	# heights — самая высокая гора над клеткой (без бугров; slope_t и tops — место на склоне
	# и высота дороги этой горы: бугры — по ним, как раньше от ближайшей точки);
	# cover — самая низкая дорога (со стенами) над клеткой.
	var heights := PackedFloat32Array()
	heights.resize(nx * nz)
	heights.fill(bottom)
	var slope_t := PackedFloat32Array()
	slope_t.resize(nx * nz)
	slope_t.fill(1.0)
	var tops := PackedFloat32Array()
	tops.resize(nx * nz)
	tops.fill(INF)
	var cover := PackedFloat32Array()
	cover.resize(nx * nz)
	cover.fill(INF)
	var radius := ceili(reach / HILLS_CELL) + 1
	var slope := maxf(surround_width, 0.1)
	var d := 0.0
	while d < length:
		if not is_in_gap(d):
			var p := get_local_point(d)
			var top := p.y - 0.02
			var outside := outline_half_width_at(d) + wall_width
			var ci := roundi((p.x - origin.x) / HILLS_CELL)
			var cj := roundi((p.z - origin.y) / HILLS_CELL)
			for j in range(maxi(cj - radius, 0), mini(cj + radius, nz - 1) + 1):
				var dz := origin.y + j * HILLS_CELL - p.z
				for i in range(maxi(ci - radius, 0), mini(ci + radius, nx - 1) + 1):
					var dx := origin.x + i * HILLS_CELL - p.x
					var dd := sqrt(dx * dx + dz * dz) - outside
					var k := j * nx + i
					if dd < 0.0:
						cover[k] = minf(cover[k], top - 0.3)
						continue
					var t := clampf((dd - HILLS_PLATEAU) / slope, 0.0, 1.0)
					var h := top - (top - bottom) * t * t * (3.0 - 2.0 * t)
					if h > heights[k]:
						heights[k] = h
						slope_t[k] = t
						tops[k] = top
		d += HILLS_CELL
	for k in nx * nz:
		# Под дорогой — чуть ниже неё (самой низкой, если над клеткой несколько: развязка).
		if cover[k] < INF:
			heights[k] = cover[k]
		else:
			heights[k] = minf(heights[k] + bumps[k] * sin(PI * slope_t[k]), tops[k])
	_hills = {"origin": origin, "nx": nx, "nz": nz, "heights": heights}

	# Клетки целиком под фоном не нужны.
	var hidden := water - 0.6
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in nz - 1:
		for i in nx - 1:
			var k := j * nx + i
			var corners := [k, k + 1, k + nx + 1, k + nx]
			if corners.all(func(c: int) -> bool: return heights[c] < hidden):
				continue
			var v: Array[Vector3] = []
			for c: int in corners:
				v.append(Vector3(origin.x + (c % nx) * HILLS_CELL, heights[c], origin.y + floorf(float(c) / nx) * HILLS_CELL))
			# Лицевая сторона — вверх (обход по часовой, если смотреть сверху).
			for index in [0, 1, 2, 0, 2, 3]:
				st.add_vertex(v[index])
	st.generate_normals()
	var mesh := st.commit()
	mesh.surface_set_material(0, _surround_material())
	var instance := MeshInstance3D.new()
	instance.name = "Hills"
	instance.mesh = mesh
	# Тень на себя не нужна: на пологих склонах она давала бы рябь (shadow acne).
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(instance)


## Высота холмов окружения в точке (локальные x, z); без холмов — 0.
func hills_height_at(x: float, z: float) -> float:
	if _hills.is_empty():
		return 0.0
	var origin: Vector2 = _hills["origin"]
	var nx: int = _hills["nx"]
	var nz: int = _hills["nz"]
	var heights: PackedFloat32Array = _hills["heights"]
	var fx := clampf((x - origin.x) / HILLS_CELL, 0.0, nx - 1.001)
	var fz := clampf((z - origin.y) / HILLS_CELL, 0.0, nz - 1.001)
	var i := floori(fx)
	var j := floori(fz)
	var tx := fx - i
	var tz := fz - j
	var top := lerpf(heights[j * nx + i], heights[j * nx + i + 1], tx)
	var bottom := lerpf(heights[(j + 1) * nx + i], heights[(j + 1) * nx + i + 1], tx)
	return lerpf(top, bottom, tz)


## Декор окружения (layout_map, мета layout_decor) — на поверхность холмов.
func _settle_decor() -> void:
	var decor := get_node_or_null(^"Decor") as Node3D
	if decor == null:
		return
	for child in decor.get_children():
		var node := child as Node3D
		# Тыквы-фонари на стенах (layout_map wall_row) стоят на стене, а не на склоне.
		if node == null or not node.has_meta(&"layout_decor") or node.has_meta(&"layout_on_wall"):
			continue
		var local := decor.transform * node.position
		local.y = hills_height_at(local.x, local.z)
		node.position = decor.transform.affine_inverse() * local


## Опоры эстакады по обоим краям через каждые support_spacing метров (только визуал).
## Высота опоры подгоняется под глубину фона (сцена рассчитана на 6 м).
func _add_supports(root: Node3D, lateral: float) -> void:
	if support_scene == null or background_depth <= 0.0:
		return
	var holder := Node3D.new()
	holder.name = "Supports"
	root.add_child(holder)
	var count := maxi(1, floori(length / support_spacing))
	for i in count:
		var d := (i + 0.5) * length / count
		if is_in_gap(d):
			continue
		var dir := get_local_direction(d)
		var right := _right_of(dir)
		var facing := Basis.looking_at(Vector3(dir.x, 0.0, dir.z).normalized(), Vector3.UP)
		for side in [-1.0, 1.0]:
			var support := support_scene.instantiate() as Node3D
			holder.add_child(support)
			# Верх опоры — под настилом (не вровень с дорогой или полосой окружения: мерцали бы).
			var deck := minf(deck_thickness, background_depth * 0.5)
			var at := lateral + outline_half_width_at(d) - road_width * 0.5
			support.transform = Transform3D(facing.scaled(Vector3(1.0, (background_depth - deck) / 6.0, 1.0)),
					get_local_point(d) + right * at * side + Vector3.DOWN * deck)
