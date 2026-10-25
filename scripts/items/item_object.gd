class_name ItemObject
extends Area3D
## Объект, который предмет оставляет на трассе: луч лазера, полоса шипов, банан,
## бумеранг, бомба, пятно льда (InstantBulletTrail, SpineTrail, DroppedBanana,
## Bumerang, Bomb, Ice оригинала).
##
## Как в оригинале:
##   * живёт по поведению Fade: появляется за fade_in_time, ждёт wait_time, тает за
##     fade_out_time и исчезает; задевает всё это время (и пока тает);
##   * хозяина не задевает (IsMy), призраков тоже (у них нет слоя машин);
##   * свой объект свой игрок видит другим кадром (без розовой обводки «опасно») или
##     полупрозрачным (своя бомба — 0.5);
##   * попадание: parryable — через CarParry.resolve (окно открыто — проезд, иначе полная
##     остановка), иначе — эффект effect_multipliers на effect_time в стеке CarEffects
##     (шипы, бомба: макс. скорость ×0.5 на 1.2 с) и звук effect_end_sound в конце.
## Создаётся через ItemObject.spawn(): рядом с машиной-хозяином в том же родителе.

signal car_hit(car: CarController)
signal car_parried(car: CarController)

## Группа машины игрока, за которым следит этот экран (её ставит Race).
const LOCAL_PLAYER_GROUP := &"local_player"
## Группа парируемых объектов предметов (по ней автопилот тестов жмёт парирование).
const PARRY_ITEMS_GROUP := &"parry_items"
const WORLD_MASK := 1

@export_group("Время жизни (Fade оригинала)")
@export var fade_in_time: float = 0.0
@export var wait_time: float = 0.0
@export var fade_out_time: float = 0.2

@export_group("Попадание")
@export var parryable: bool = true
## Звуки удара (если не парировал / при эффекте).
@export var hit_sounds: Array[AudioStream] = []
## Эффект на пострадавшего (не парируемые объекты): id, время, множители.
@export var effect_id: StringName = &"item_hit"
@export var effect_time: float = 0.0
@export var effect_multipliers: Dictionary = {}
## Звук, когда эффект кончился (Hang у шипов и бомбы).
@export var effect_end_sound: AudioStream
## Исчезнуть после первого попадания (бомба).
@export var destroy_on_hit: bool = false
## Эффекты при попадании (пресеты Fx: взрыв бомбы) и сила тряски камеры, м.
@export var hit_fx: Array[StringName] = []
@export var hit_shake: float = 0.0

@export_group("Вид")
## Sprite3D, которому подставляется текстура «чужой»/«свой».
@export var visual_path: NodePath = ^"Visual"
## Как объект видят остальные (в оригинале — кадр 0, часто с розовой обводкой).
@export var other_texture: Texture2D
## Как свой объект видит его хозяин (кадр 1); пусто — как остальные.
@export var own_texture: Texture2D
## Непрозрачность своего объекта для хозяина (своя бомба — 0.5).
@export_range(0.0, 1.0) var own_alpha: float = 1.0
## «Протыкание»: вид за stab_time с вылетает от середины на всю длину (ось X вида) с небольшим
## перелётом и возвращается — резкий выпад (шило «Шипов»). 0 — сразу целиком.
@export var stab_time: float = 0.0
## Вращение вида, °/с (бумеранг — 180).
@export var spin_speed_deg: float = 0.0

@export_group("Движение")
## Положить на землю под точкой появления (банан, бомба, лёд).
@export var drop_to_ground: bool = false
## Полёт вперёд и обратно (бумеранг): расстояние, м, и время в одну сторону, с.
@export var travel_distance: float = 0.0
@export var travel_time: float = 1.0

## Метаданные машины: peer id её игрока в сети (ставит Race; в одиночной игре 1)
## и сколько объектов предметов она уже оставила.
const NET_PEER_META := &"net_peer"
const OBJECT_COUNT_META := &"item_objects"

## Машина, которая применила предмет (её объект не задевает).
var owner_car: CarController
## Номер объекта, одинаковый на всех компьютерах сети.
var object_id: int = 0

var _age: float = 0.0
var _base_alpha: float = 1.0
var _visual: Node3D
var _geometry: Array[GeometryInstance3D] = []
## Цвет спрайтов из сцены: прозрачность Fade умножается на их альфу.
var _sprite_colors: Dictionary = {}


## Создать объект scene от машины car в трансформе xform (глобальном).
static func spawn(scene: PackedScene, car: CarController, xform: Transform3D) -> ItemObject:
	return spawn_prepared(scene.instantiate() as ItemObject, car, xform)


## То же для уже созданного экземпляра (ThrownObject.prepare — с дальностью броска).
static func spawn_prepared(item_object: ItemObject, car: CarController, xform: Transform3D) -> ItemObject:
	item_object.owner_car = car
	# Одинаковый id у всех в сети: игрок-хозяин + номер его объекта по порядку
	# (применения предметов приходят надёжно и по порядку).
	var count := int(car.get_meta(OBJECT_COUNT_META, 0)) + 1
	car.set_meta(OBJECT_COUNT_META, count)
	item_object.object_id = int(car.get_meta(NET_PEER_META, 1)) * 100000 + count
	car.get_parent().add_child(item_object)
	item_object.global_transform = xform
	item_object._on_spawned()
	return item_object


func _ready() -> void:
	_visual = get_node_or_null(visual_path) as Node3D
	for node in find_children("*", "GeometryInstance3D", true, false):
		_geometry.append(node as GeometryInstance3D)
		if node is SpriteBase3D:
			_sprite_colors[node] = (node as SpriteBase3D).modulate
	if parryable:
		add_to_group(PARRY_ITEMS_GROUP)
	body_entered.connect(_on_body_entered)


func _exit_tree() -> void:
	Network.session().unregister_object(self)


## Сколько всего живёт объект, с.
func get_lifetime() -> float:
	return fade_in_time + wait_time + fade_out_time


func _on_spawned() -> void:
	Network.session().register_object(self)
	if drop_to_ground:
		_drop_to_ground()
	var own_view := owner_car != null and owner_car.is_in_group(LOCAL_PLAYER_GROUP)
	var sprite := _visual as Sprite3D
	if sprite != null:
		var texture := own_texture if own_view and own_texture != null else other_texture
		if texture != null:
			sprite.texture = texture
	_base_alpha = own_alpha if own_view else 1.0
	_apply_alpha()
	if stab_time > 0.0 and _visual != null:
		var full := _visual.scale
		_visual.scale = Vector3(full.x * 0.05, full.y, full.z)
		var stab := create_tween()
		stab.tween_property(_visual, ^"scale", Vector3(full.x * 1.12, full.y, full.z), stab_time * 0.6) \
				.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		stab.tween_property(_visual, ^"scale", full, stab_time * 0.4) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if travel_distance > 0.0:
		var forward := -global_basis.z
		forward.y = 0.0
		var start := global_position
		var tween := create_tween()
		tween.tween_property(self, ^"global_position", start + forward.normalized() * travel_distance, travel_time) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween.tween_property(self, ^"global_position", start, travel_time) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= get_lifetime():
		queue_free()
		return
	if _visual != null and spin_speed_deg != 0.0:
		_visual.rotate_y(deg_to_rad(spin_speed_deg) * delta)
	_apply_alpha()


## Непрозрачность по времени жизни (как Fade): нарастает, держится, тает.
func get_fade() -> float:
	if fade_in_time > 0.0 and _age < fade_in_time:
		return _age / fade_in_time
	var fade_start := fade_in_time + wait_time
	if _age > fade_start and fade_out_time > 0.0:
		return clampf(1.0 - (_age - fade_start) / fade_out_time, 0.0, 1.0)
	return 1.0


func _apply_alpha() -> void:
	var alpha := _base_alpha * get_fade()
	for geometry in _geometry:
		# Спрайты — через цвет: GeometryInstance3D.transparency в Compatibility не рисуется
		# (лазер и шипы появлялись и пропадали рывком, без Fade оригинала).
		if _sprite_colors.has(geometry):
			var color: Color = _sprite_colors[geometry]
			(geometry as SpriteBase3D).modulate = Color(color, color.a * alpha)
		else:
			geometry.transparency = 1.0 - alpha


func _drop_to_ground() -> void:
	var from := global_position + Vector3.UP * 0.5
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 30.0, WORLD_MASK)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		global_position = hit["position"]
		# На склоне лежит под наклоном дороги (по нормали), поворот по трассе сохраняется.
		var normal: Vector3 = hit["normal"]
		var forward := -global_basis.z
		forward.y = 0.0
		if normal.y > 0.5 and forward.length_squared() > 1e-6:
			var flat := Basis.looking_at(forward.normalized(), Vector3.UP)
			global_basis = Basis(Quaternion(Vector3.UP, normal.normalized())) * flat


func _on_body_entered(body: Node3D) -> void:
	var car := body as CarController
	if car == null or car == owner_car or car.is_ghost or car.is_puppet:
		return
	_hit(car)


func _hit(car: CarController) -> void:
	# Сетевая игра: свою машину задело — исход решает хост (по окну парирования этой
	# машины на момент касания), сам удар — когда он подтвердит (apply_hit).
	if Network.session().is_online():
		var parry := CarParry.of(car)
		Network.session().report_hit(self, parryable and parry != null and parry.is_window_open())
		return
	var parried := false
	if parryable:
		var parry := CarParry.of(car)
		parried = parry != null and parry.is_window_open()
	apply_hit(car, parried)


## Исход попадания по машине car (parried — успела парировать). В сети зовётся у всех
## по подтверждению хоста: у хозяина машины — удар и звуки, у остальных — эмоция и эффекты.
func apply_hit(car: CarController, parried: bool) -> void:
	if parryable:
		if CarParry.resolve_as(car, self, hit_sounds, parried):
			car_parried.emit(car)
			return
	else:
		for sound in hit_sounds:
			Sfx.play(car, sound)
		car.emote(&"rage", 1.5)
		var effects := CarEffects.of(car)
		if effects != null and effect_time > 0.0 and not car.is_puppet:
			effects.add(effect_id, effect_time, effect_multipliers.duplicate())
			if effect_end_sound != null:
				_schedule_sound(car, effect_end_sound, effect_time)
	car_hit.emit(car)
	if not hit_fx.is_empty():
		Fx.burst(hit_fx, get_parent(), global_position + Vector3.UP * 0.5)
		Fx.ring(get_parent(), global_position, 5.0)
	if hit_shake > 0.0:
		Fx.shake(self, global_position, hit_shake)
	if destroy_on_hit:
		queue_free()


## Звук машине через seconds секунд. Статическая (лямбда без self) — звук прозвучит
## и после исчезновения объекта (бомба исчезает сразу).
static func _schedule_sound(car: CarController, sound: AudioStream, seconds: float) -> void:
	car.get_tree().create_timer(seconds, false, true).timeout.connect(func() -> void:
		if is_instance_valid(car):
			Sfx.play(car, sound))
