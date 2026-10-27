class_name Warmup
extends SubViewport
## Прогрев перед первой гонкой (идёт во время интро). Тестеры: «на Хэллоуине с начала заезда
## какая-то прогрузка, игра зависает на 2–3 секунды». Две причины:
##   * загрузка сцены карты с диска (картинки, музыка) — «Хэллоуин» ~0.9 с: все карты и общие
##     сцены грузятся в фоне (load_threaded_request) и остаются в памяти (мета корня дерева
##     CACHE_META) — потом load() отдаёт их сразу;
##   * компиляция шейдеров при первом показе материала (Compatibility компилирует при первой
##     отрисовке, ~0.25 с на первом кадре «Хэллоуина» и рывки, когда в кадр впервые попадают
##     призрак, грязь, эффект…): в этом невидимом окне один раз рисуется всё — «витрина» из
##     пропсов, опасностей, декора, объектов, предметов, эффектов, машин всех кузовов и зон
##     всех видов, потом по очереди каждая карта целиком. Свет, дымка и свечение — как в гонке.
## Тяжёлые шаги (карта строится 0.1–0.3 с) интро делает, пока экран чёрный (между картинками).

const TRACKS_DIR := "res://scenes/tracks/"
const SCENE_DIRS: Array[String] = [
	"res://scenes/props/", "res://scenes/hazards/", "res://scenes/decor/",
	"res://scenes/objects/", "res://scenes/items/", "res://scenes/fx/",
]
const RACE_SCENE := "res://scenes/race/race.tscn"
const CAR_SCENE := "res://scenes/car/car.tscn"
const ZONE_SCENE := "res://scenes/objects/map_zone.tscn"
## Загруженные сцены — в мете корня дерева: живут, пока работает игра.
const CACHE_META := &"warm_scenes"
## Машины витрины — все кузова с разными рисунками и колёсами (строки CarSkin).
const CAR_SKINS: Array[String] = ["31200110", "13201501", "22302802", "33303903"]
const GRID_STEP := 7.0
const GRID_COLUMNS := 8

var _paths: Array[String] = []
var _tracks: Array[String] = []
## Шаги: «витрина», потом карты по одной.
var _steps: Array[Callable] = []
var _content: Node3D
var _camera: Camera3D
var _sun: DirectionalLight3D


func _ready() -> void:
	own_world_3d = true
	size = Vector2i(320, 180)
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_build_world()
	_request_loads()
	_steps.append(_show_showcase)
	for path in _tracks:
		_steps.append(_show_track.bind(path))


## Сколько шагов осталось.
func remaining() -> int:
	return _steps.size()


## Следующий шаг: убрать прошлое, поставить новое (отрисуется в ближайших кадрах).
## Может занять заметное время (загрузка, постройка карты) — вызывать на чёрном экране.
func step() -> void:
	if _content != null:
		_content.free()
		_content = null
	if _steps.is_empty():
		return
	_content = Node3D.new()
	_content.name = "Content"
	add_child(_content)
	var next: Callable = _steps.pop_front()
	next.call()


## Всё убрать (интро закончилось).
func clear() -> void:
	if _content != null:
		_content.free()
		_content = null


func _request_loads() -> void:
	for raw in DirAccess.get_files_at(TRACKS_DIR):
		var file := raw.trim_suffix(".remap")
		if file.ends_with(".tscn") and not file.begins_with("_") and not _tracks.has(TRACKS_DIR + file):
			_tracks.append(TRACKS_DIR + file)
	_paths.append_array(_tracks)
	for dir in SCENE_DIRS:
		for raw in DirAccess.get_files_at(dir):
			var file := raw.trim_suffix(".remap")
			if file.ends_with(".tscn") and not _paths.has(dir + file):
				_paths.append(dir + file)
	_paths.append_array([RACE_SCENE, CAR_SCENE])
	for path in _paths:
		ResourceLoader.load_threaded_request(path)


## Загруженная сцена (если ещё грузится — ждём её); сохраняется в кэше.
func _scene(path: String) -> PackedScene:
	var scene := ResourceLoader.load_threaded_get(path) as PackedScene
	if scene == null:
		scene = load(path) as PackedScene
	var root := get_tree().root
	var cache: Array = root.get_meta(CACHE_META, [])
	if scene != null and not cache.has(scene):
		cache.append(scene)
		root.set_meta(CACHE_META, cache)
	return scene


## Свет и окружение — как в сцене гонки (тот же набор шейдеров: тени, дымка, свечение).
func _build_world() -> void:
	var race := (load(RACE_SCENE) as PackedScene).instantiate()
	var world := race.get_node(^"WorldEnvironment") as WorldEnvironment
	var race_sun := race.get_node(^"Sun") as DirectionalLight3D
	var environment := WorldEnvironment.new()
	environment.environment = world.environment
	add_child(environment)
	_sun = race_sun.duplicate() as DirectionalLight3D
	# Тени на всю витрину и карту (на шейдеры не влияет, только чтобы все попали в проход теней).
	_sun.directional_shadow_max_distance = 2000.0
	add_child(_sun)
	race.free()
	_camera = Camera3D.new()
	_camera.fov = 95.0
	_camera.near = 1.0
	_camera.far = 4000.0
	add_child(_camera)
	_camera.current = true


## Витрина: всё, что бывает на картах и в гонке, рядами.
func _show_showcase() -> void:
	var items: Array[Node] = []
	for path in _paths:
		if path.begins_with(TRACKS_DIR) or path == RACE_SCENE or path == CAR_SCENE:
			continue
		var scene := _scene(path)
		if scene != null:
			items.append(scene.instantiate())
	# Зоны всех видов (лёд и грязь — свои шейдеры; грязь — лужей и на всю дорогу).
	var zones := [[MapZone.Kind.AQUA_SLIDER, Vector2(5.0, 5.0)], [MapZone.Kind.ICE, Vector2(5.0, 5.0)],
			[MapZone.Kind.MUD, Vector2(5.0, 8.0)], [MapZone.Kind.MUD, Vector2(12.0, 8.0)]]
	for kind_size: Array in zones:
		var zone := _scene(ZONE_SCENE).instantiate() as MapZone
		zone.kind = kind_size[0]
		zone.size = kind_size[1]
		items.append(zone)
	# Машины всех кузовов; без ввода и физики (только вид).
	for code in CAR_SKINS:
		var car := _scene(CAR_SCENE).instantiate() as CarController
		(car.get_node(^"Visual") as CarVisual).skin = CarSkin.from_code(code)
		car.process_mode = Node.PROCESS_MODE_DISABLED
		items.append(car)
	# Все эффекты частиц (дым, искры, пламя, грязь…) — сразу летят.
	for preset: StringName in Fx.PRESETS:
		var emitter := Fx.emitter(preset)
		emitter.one_shot = false
		items.append(emitter)
	for i in items.size():
		_content.add_child(items[i])
		var node := items[i] as Node3D
		if node != null:
			@warning_ignore("integer_division")
			node.position = Vector3((i % GRID_COLUMNS) * GRID_STEP, 0.0, (i / GRID_COLUMNS) * GRID_STEP)
		# Частицы включаются уже в дереве (emitting берёт глобальное положение).
		if node is CPUParticles3D:
			(node as CPUParticles3D).emitting = true
	# Экранные эффекты (полосы скорости, «пьяный» экран): показать всё сразу.
	for layer in _content.find_children("*", "CanvasLayer", true, false):
		for canvas in (layer as CanvasLayer).find_children("*", "CanvasItem", true, false):
			(canvas as CanvasItem).visible = true
	@warning_ignore("integer_division")
	var rows := items.size() / GRID_COLUMNS + 1
	var center := Vector3((GRID_COLUMNS - 1) * GRID_STEP * 0.5, 0.0, (rows - 1) * GRID_STEP * 0.5)
	_look_at(center, maxf(GRID_COLUMNS, rows) * GRID_STEP)


## Карта целиком: строится (как в гонке) и видна сверху вся.
func _show_track(path: String) -> void:
	var scene := _scene(path)
	if scene == null:
		return
	var track := scene.instantiate() as Node3D
	_content.add_child(track)
	var bounds := AABB()
	var path_node := track.get_node_or_null(^"Path") as Path3D
	if path_node != null and path_node.curve != null and path_node.curve.point_count > 0:
		bounds = AABB(path_node.curve.get_point_position(0), Vector3.ZERO)
		for i in path_node.curve.point_count:
			bounds = bounds.expand(path_node.curve.get_point_position(i))
	_look_at(bounds.get_center(), maxf(bounds.size.x, bounds.size.z) + 60.0)


## Камера сверху с наклоном, как в игре, чтобы влезло span метров.
func _look_at(center: Vector3, span: float) -> void:
	var height := span * 0.55 + 10.0
	_camera.look_at_from_position(center + Vector3(0.0, height, height * 0.35), center)
