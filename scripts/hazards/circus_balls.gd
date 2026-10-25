class_name CircusBalls
extends ParryHazard
## Цирковые шары оригинала (CircusBalls, Пляж — пляжный мяч): в оригинале коробка 3×3×2 м
## с картинкой мяча сверху, у нас — мяч диаметром 3 м. В оригинале ездит туда-обратно
## «пилой» (Sine forwards-backwards, треугольник, размах 96 px = 12 м, период 1 с) и прыгает
## тоже треугольником (16 ± 16 px за 0.3 с) — выглядело механически. У нас (просьба автора
## оригинала: «пусть мяч двигается натуральнее») — как настоящий мяч: катится туда-обратно
## плавно (синус: замедляется у краёв), прыгает по параболе (быстро у земли, зависает
## наверху), при ударе о землю сплющивается, под ним тень. Задевает, только когда у земли
## (ниже 0.625 м), один раз за касание: парирование или остановка + BassBubble + злость.

## Размах в оригинале, м; на узкой дороге инструмент переноса уменьшает sweep.
const DEFAULT_SWEEP := 12.0
## Период хода туда-обратно, с (в оригинале 1 с треугольником — для синуса быстро).
const MOVE_PERIOD := 2.2
## Высота прыжка (низ мяча), м, и время от касания до касания, с.
const BOUNCE_HEIGHT := 2.6
const BOUNCE_PERIOD := 0.62
## Сплющивание у земли: доля высоты и сколько длится (с) вокруг касания.
const SQUASH := 0.28
const SQUASH_TIME := 0.09
const HIT_HEIGHT := 0.625
const BALL_RADIUS := 1.5

## Размах движения туда-обратно, м.
@export var sweep: float = DEFAULT_SWEEP

var _origin: Vector3
var _time: float = 0.0
var _roll: float = 0.0
var _last_side: float = 0.0
var _touching: Array[CarController] = []
var _shadow: MeshInstance3D


func _ready() -> void:
	# Касание проверяется каждый кадр по высоте, а не по входу в зону.
	_origin = position
	add_to_group(ItemObject.PARRY_ITEMS_GROUP)
	# Мячи одной карты не прыгают в такт: фаза — от места.
	_time = fposmod(_origin.x * 0.37 + _origin.z * 0.23, MOVE_PERIOD)
	_last_side = _side(_time)
	_build_shadow()


func _physics_process(delta: float) -> void:
	_time += delta
	var height := bounce_height(_time)
	var side := _side(_time)
	position = _origin + basis.x.normalized() * side
	# Мяч катится: угол — по пройденному пути (не по смещению — так он не «отматывается»).
	_roll -= (side - _last_side) / BALL_RADIUS
	_last_side = side
	var visual := get_node_or_null(^"Visual") as Node3D
	if visual != null:
		var squash := _squash(_time)
		# Сплющивание — по вертикали мира (до вращения), низ мяча остаётся на земле.
		var stretch := 1.0 + squash * 0.5
		visual.basis = Basis.from_scale(Vector3(stretch, 1.0 - squash, stretch)) * Basis(Vector3.BACK, _roll)
		visual.position.y = height + BALL_RADIUS * (1.0 - squash)
	if _shadow != null:
		# Тень меньше и бледнее, когда мяч наверху.
		var up := clampf(height / BOUNCE_HEIGHT, 0.0, 1.0)
		var size := lerpf(1.0, 0.6, up)
		_shadow.scale = Vector3(size, 1.0, size)
		(_shadow.material_override as StandardMaterial3D).albedo_color.a = lerpf(0.4, 0.15, up)
	var low := height < HIT_HEIGHT
	var still: Array[CarController] = []
	for body in get_overlapping_bodies():
		var car := body as CarController
		if car == null or car.is_ghost or car.is_puppet:
			continue
		if low:
			still.append(car)
			if car not in _touching:
				if CarParry.resolve(car, self, hit_sounds):
					car_parried.emit(car)
				else:
					car_hit.emit(car)
	_touching = still


## Высота низа мяча над землёй в момент time: парабола от касания до касания.
static func bounce_height(time: float) -> float:
	var s := fposmod(time / BOUNCE_PERIOD, 1.0)
	return 4.0 * BOUNCE_HEIGHT * s * (1.0 - s)


## Смещение вбок: синус, у краёв мяч замедляется и катится обратно.
func _side(time: float) -> float:
	return sweep * sin(TAU * time / MOVE_PERIOD)


## Сплющивание 0..SQUASH: сильнее всего в момент касания, за SQUASH_TIME до и после — нет.
func _squash(time: float) -> float:
	var t := fposmod(time, BOUNCE_PERIOD)
	var from_touch := minf(t, BOUNCE_PERIOD - t)
	if from_touch >= SQUASH_TIME:
		return 0.0
	var k := 1.0 - from_touch / SQUASH_TIME
	return SQUASH * k * k


## Круглая тень на земле (простой диск, без текстуры).
func _build_shadow() -> void:
	var disc := CylinderMesh.new()
	disc.top_radius = BALL_RADIUS * 0.9
	disc.bottom_radius = BALL_RADIUS * 0.9
	disc.height = 0.01
	disc.radial_segments = 12
	disc.rings = 1
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.0, 0.0, 0.0, 0.4)
	_shadow = MeshInstance3D.new()
	_shadow.name = "Shadow"
	_shadow.mesh = disc
	_shadow.material_override = material
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shadow.position.y = 0.06
	add_child(_shadow)
