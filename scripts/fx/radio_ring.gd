class_name RadioRing
extends MultiMeshInstance3D
## Кольцо эквалайзера вокруг машины с играющей магнитолой (CarRadio): BARS столбиков из
## SEGMENTS блоков лучами наружу на земле, радуга по кругу (как пиксельные эквалайзеры —
## образец автора ремейка), высота столбика — громкость своей полосы частот (set_levels),
## кольцо медленно крутится. Один MultiMesh: блок — плоский квадрат, погашенный — прозрачный.
## Лежит по дороге: наклон — по нормали пола под машиной (луч вниз; у чужих машин в сети физики
## нет), иначе на подъёме часть кольца уходила под дорогу.

const BARS := 32
const SEGMENTS := 8
## Внутренний радиус (машина 3 м — снаружи неё), длина блока по радиусу и зазор, м.
const INNER := 2.4
const DEPTH := 0.3
const GAP := 0.1
## Доля дуги на блок (остальное — зазор между столбиками).
const WIDTH_SHARE := 0.62
const HEIGHT := 0.18
const SPIN_DEG := 25.0
## Луч вниз за полом: от столько выше машины до столько ниже, м; наклон догоняет с этой скоростью.
const PROBE_UP := 2.0
const PROBE_DOWN := 4.0
const TILT_SHARPNESS := 10.0
const LIT_ALPHA := 0.95

var _spin := 0.0
var _tilt := Quaternion.IDENTITY


func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = material
	var mesh := MultiMesh.new()
	mesh.transform_format = MultiMesh.TRANSFORM_3D
	mesh.use_colors = true
	mesh.mesh = quad
	mesh.instance_count = BARS * SEGMENTS
	for bar in BARS:
		var angle := float(bar) / BARS * TAU
		var direction := Vector3(sin(angle), 0.0, cos(angle))
		for segment in SEGMENTS:
			var radius := INNER + segment * (DEPTH + GAP) + DEPTH * 0.5
			var width := TAU * radius / BARS * WIDTH_SHARE
			var block := Basis(Vector3.UP, angle).scaled(Vector3(width, 1.0, DEPTH))
			mesh.set_instance_transform(bar * SEGMENTS + segment,
					Transform3D(block, direction * radius + Vector3.UP * HEIGHT))
			mesh.set_instance_color(bar * SEGMENTS + segment, Color(0, 0, 0, 0))
	multimesh = mesh


func _process(delta: float) -> void:
	_spin = wrapf(_spin + deg_to_rad(SPIN_DEG) * delta, 0.0, TAU)
	var target := Quaternion.IDENTITY
	var car := get_parent() as Node3D
	if car != null:
		var from := car.global_position + Vector3.UP * PROBE_UP
		var query := PhysicsRayQueryParameters3D.create(from, car.global_position + Vector3.DOWN * PROBE_DOWN, 1)
		if car is CollisionObject3D:
			query.exclude = [(car as CollisionObject3D).get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			var local_normal := (car.global_basis.inverse() * (hit["normal"] as Vector3)).normalized()
			target = Quaternion(Vector3.UP, local_normal)
	_tilt = _tilt.slerp(target, minf(TILT_SHARPNESS * delta, 1.0))
	basis = Basis(_tilt) * Basis(Vector3.UP, _spin)


## Уровни столбиков 0..1 (BARS штук): сколько блоков горит, цвет — радуга по кругу,
## к краю чуть светлее.
func set_levels(levels: PackedFloat32Array) -> void:
	for bar in BARS:
		var lit := roundi(clampf(levels[bar], 0.0, 1.0) * SEGMENTS)
		var hue := float(bar) / BARS
		for segment in SEGMENTS:
			var color := Color(0, 0, 0, 0)
			if segment < lit:
				color = Color.from_hsv(hue, lerpf(0.9, 0.6, float(segment) / SEGMENTS), 1.0, LIT_ALPHA)
			multimesh.set_instance_color(bar * SEGMENTS + segment, color)
