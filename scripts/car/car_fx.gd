class_name CarFx
extends Node3D
## Эффекты машины (узел «Fx», дочерний у CarController; только визуал, на физику не влияет):
##   * следы шин — тёмные полосы от задних колёс, пока машину заносит (дрифт, боковое
##     скольжение, резкое торможение); живут как след PlayerWheelTrail оригинала:
##     появляются за 0.1 с, держатся 0.5 с, тают 0.4 с; цвет (0.11, 0.11, 0.11) и 50 %;
##   * дым из-под задних колёс в дрифте, искры — когда занос «заряжен» (отпусти — ускорение):
##     цвет по стадии (синие, оранжевые, фиолетовые), ретро-вид Nintendo 64 / SNES;
##   * пламя из выхлопа, пока машина быстрее своего обычного предела (ускорение после дрифта,
##     нитро, ускорители, водка);
##   * пыль, искры и взрывная волна при жёстком приземлении (трамплин) + лёгкая тряска камеры;
##   * искры об стену; звёздочки «бонк», когда машину остановило (промах парирования);
##   * рывок (Dash): «шлейф» — полупрозрачные голубые копии машины тают позади, пыль сзади
##     и лёгкая тряска (в оригинале у рывка только звук).
## В оригинале из этого есть только след машины — остальное наше дополнение.

## Задние колёса в координатах машины (машина смотрит в −Z), м.
const REAR_WHEELS: Array[Vector3] = [Vector3(-0.65, 0.0, 1.0), Vector3(0.65, 0.0, 1.0)]
## Выхлоп (центр задней части), м.
const EXHAUST := Vector3(0.0, 0.45, 1.55)
## След шин: высота над дорогой (дорога — 0.03 м), ширина полосы, шаг точек, время жизни.
const SKID_HEIGHT := 0.045
const SKID_WIDTH := 0.32
const SKID_STEP := 0.4
const SKID_FADE_IN := 0.1
const SKID_HOLD := 0.5
const SKID_FADE_OUT := 0.4
const SKID_COLOR := Color(0.11, 0.11, 0.11, 0.5)
## Шлейф рывка: копия машины каждые DASH_GHOST_STEP с, тает за DASH_GHOST_LIFE с.
const DASH_GHOST_STEP := 0.05
const DASH_GHOST_LIFE := 0.3
const DASH_GHOST_COLOR := Color(0.55, 0.85, 1.0, 0.5)
## Боковое скольжение больше этого угла (°) на скорости выше SKID_MIN_SPEED — следы.
const SKID_SLIDE_DEG := 12.0
const SKID_MIN_SPEED := 7.5

## Приземление жёстче этой вертикальной скорости (м/с) — пыль, искры, волна, тряска.
@export var landing_min_fall_speed: float = 7.0
## Размах тряски камеры при жёстком приземлении, м.
@export var landing_shake: float = 0.35

var _car: CarController
var _smoke: CPUParticles3D
var _sparks: CPUParticles3D
var _flame: CPUParticles3D
var _mud: CPUParticles3D
var _skid_mesh: ImmediateMesh
var _skid_instance: MeshInstance3D
var _skid_material: StandardMaterial3D
## Точки следов: по массиву на колесо, элемент — {pos, time, joined}.
var _tracks: Array = [[], []]
var _time: float = 0.0
var _fall_speed: float = 0.0
## Стадия дрифта, под которую раскрашены искры.
var _spark_stage: int = 0


func _ready() -> void:
	_car = get_parent() as CarController
	if _car == null:
		push_warning("CarFx: родитель не CarController, эффекты отключены.")
		return
	_smoke = Fx.emitter(&"drift_smoke")
	_smoke.position = Vector3(0.0, 0.25, 1.2)
	add_child(_smoke)
	_sparks = Fx.emitter(&"drift_sparks")
	_sparks.position = Vector3(0.0, 0.2, 1.2)
	add_child(_sparks)
	_flame = Fx.emitter(&"boost_flame")
	_flame.position = EXHAUST
	add_child(_flame)
	_mud = Fx.emitter(&"mud_spray")
	_mud.position = Vector3(0.0, 0.2, 1.2)
	add_child(_mud)

	_skid_mesh = ImmediateMesh.new()
	_skid_material = StandardMaterial3D.new()
	_skid_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_skid_material.vertex_color_use_as_albedo = true
	_skid_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_skid_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_skid_instance = MeshInstance3D.new()
	_skid_instance.name = "Skids"
	_skid_instance.mesh = _skid_mesh
	_skid_instance.top_level = true
	_skid_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_skid_instance)
	_skid_instance.global_transform = Transform3D.IDENTITY

	_car.landed.connect(_on_landed)
	_car.wall_hit.connect(_on_wall_hit)
	_car.respawned.connect(_clear_tracks)
	var parry := CarParry.of(_car)
	if parry != null:
		parry.hit.connect(_on_stopped)


func _physics_process(delta: float) -> void:
	if _car == null:
		return
	_time += delta
	var on_floor := _car.is_grounded()
	if not on_floor:
		_fall_speed = maxf(-_car.velocity.y, 0.0)
	var speed := absf(_car.forward_speed)
	_smoke.emitting = _car.is_drifting and on_floor
	var stage := _car.get_drift_stage()
	_sparks.emitting = on_floor and stage > 0
	if stage > 0 and stage != _spark_stage:
		_spark_stage = stage
		_sparks.color_ramp = Fx._gradient(Fx.DRIFT_STAGE_COLORS[stage - 1] + [Color(0, 0, 0, 0)], true)
	_flame.emitting = _car.forward_speed > _car.max_speed + 0.5 or _car.is_boosting()
	# В грязи колёса буксуют — летят комья (зона MUD ставит счётчик в мета машины).
	_mud.emitting = on_floor and int(_car.get_meta(MapZone.MUD_COUNT_META, 0)) > 0 			and (speed > 1.0 or _car.current_input.throttle > 0.1)
	_update_skids(on_floor and speed > SKID_MIN_SPEED and _is_skidding())
	_draw_skids()


## Машину заносит: дрифт, боковое скольжение или резкое торможение на ходу.
func _is_skidding() -> bool:
	if _car.is_drifting:
		return true
	if absf(_car.get_slide_angle()) > deg_to_rad(SKID_SLIDE_DEG):
		return true
	return _car.current_input.throttle < -0.5 and _car.forward_speed > SKID_MIN_SPEED


func _update_skids(skidding: bool) -> void:
	var lifetime := SKID_FADE_IN + SKID_HOLD + SKID_FADE_OUT
	for i in REAR_WHEELS.size():
		var track: Array = _tracks[i]
		while not track.is_empty() and _time - float(track[0]["time"]) > lifetime:
			track.pop_front()
		if not skidding:
			if not track.is_empty():
				track.back()["open"] = false
			continue
		var wheel := _car.global_transform * REAR_WHEELS[i]
		wheel.y = _car.global_position.y + SKID_HEIGHT
		var last: Dictionary = track.back() if not track.is_empty() else {}
		var joined: bool = not last.is_empty() and bool(last.get("open", false))
		if joined and (last["pos"] as Vector3).distance_to(wheel) < SKID_STEP:
			continue
		track.append({"pos": wheel, "time": _time, "joined": joined, "open": true})


func _draw_skids() -> void:
	_skid_mesh.clear_surfaces()
	var has_quads := false
	for track in _tracks:
		for k in range(1, track.size()):
			if bool(track[k]["joined"]):
				has_quads = true
				break
	if not has_quads:
		return
	_skid_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _skid_material)
	for track in _tracks:
		for k in range(1, track.size()):
			var b: Dictionary = track[k]
			if not bool(b["joined"]):
				continue
			var a: Dictionary = track[k - 1]
			var pa: Vector3 = a["pos"]
			var pb: Vector3 = b["pos"]
			var dir := pb - pa
			dir.y = 0.0
			if dir.length_squared() < 1e-6:
				continue
			var side := dir.normalized().cross(Vector3.UP) * SKID_WIDTH * 0.5
			var ca := _skid_color(float(a["time"]))
			var cb := _skid_color(float(b["time"]))
			_skid_vertex(pa - side, ca)
			_skid_vertex(pa + side, ca)
			_skid_vertex(pb + side, cb)
			_skid_vertex(pa - side, ca)
			_skid_vertex(pb + side, cb)
			_skid_vertex(pb - side, cb)
	_skid_mesh.surface_end()


func _skid_vertex(position_: Vector3, color: Color) -> void:
	_skid_mesh.surface_set_color(color)
	_skid_mesh.surface_add_vertex(position_)


## Прозрачность точки следа по возрасту (как Fade у PlayerWheelTrail оригинала).
func _skid_color(born: float) -> Color:
	var age := _time - born
	var fade := 1.0
	if age < SKID_FADE_IN:
		fade = age / SKID_FADE_IN
	elif age > SKID_FADE_IN + SKID_HOLD:
		fade = 1.0 - (age - SKID_FADE_IN - SKID_HOLD) / SKID_FADE_OUT
	var color := SKID_COLOR
	color.a *= clampf(fade, 0.0, 1.0)
	return color


func _clear_tracks() -> void:
	_tracks = [[], []]
	_fall_speed = 0.0


func _on_landed() -> void:
	var fall := _fall_speed
	_fall_speed = 0.0
	if fall < landing_min_fall_speed:
		return
	var parent := _car.get_parent()
	var at := _car.global_position
	Fx.burst([&"landing_dust", &"landing_sparks"], parent, at + Vector3.UP * 0.3)
	Fx.ring(parent, at, 4.0)
	Fx.shake(_car, at, landing_shake)


func _on_wall_hit() -> void:
	var collision := _car.get_last_slide_collision()
	if collision == null or absf(_car.forward_speed) < 4.0:
		return
	var normal := collision.get_normal()
	normal.y = 0.0
	Fx.burst([&"wall_sparks"], _car.get_parent(), collision.get_position() + Vector3.UP * 0.4,
			(normal.normalized() + Vector3.UP * 0.6).normalized())


## Эффект предмета (ItemSelfEffect.use_fx) на duration секунд.
func play_item_fx(fx_name: StringName, duration: float) -> void:
	if _car == null:
		return
	if fx_name == &"dash":
		var parent := _car.get_parent()
		Fx.burst([&"landing_dust"], parent, _car.global_position + _car.global_basis.z * 1.5 + Vector3.UP * 0.3)
		Fx.shake(_car, _car.global_position, 0.12)
		var copies := maxi(int(duration / DASH_GHOST_STEP), 1)
		for i in copies:
			get_tree().create_timer(i * DASH_GHOST_STEP, false).timeout.connect(_dash_ghost)


## Полупрозрачная копия машины на её месте: тает за DASH_GHOST_LIFE.
func _dash_ghost() -> void:
	if _car == null or not _car.is_inside_tree():
		return
	var visual := _car.get_node_or_null(^"Visual") as Node3D
	if visual == null:
		return
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = DASH_GHOST_COLOR
	var ghost := Node3D.new()
	ghost.name = "DashGhost"
	ghost.top_level = true
	_car.get_parent().add_child(ghost)
	for node in visual.find_children("*", "MeshInstance3D", true, false):
		var source := node as MeshInstance3D
		var copy := MeshInstance3D.new()
		copy.mesh = source.mesh
		copy.material_override = material
		copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ghost.add_child(copy)
		copy.global_transform = source.global_transform
	var tween := ghost.create_tween()
	tween.tween_property(material, ^"albedo_color:a", 0.0, DASH_GHOST_LIFE)
	tween.tween_callback(ghost.queue_free)


func _on_stopped(_hazard: Node) -> void:
	Fx.burst([&"bonk"], _car.get_parent(), _car.global_position + Vector3.UP * 1.6)
	Fx.shake(_car, _car.global_position, 0.2)
