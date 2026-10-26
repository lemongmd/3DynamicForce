@tool
class_name MapZone
extends Area3D
## Плоская зона карты оригинала — пока машина на ней:
##   * CONVEYOR (Conveyor, Шинозавод): тянет 128 px/с = 16 м/с по своей оси +X
##     (move-at-angle по углу объекта); лента «едет» 128 px/с; звук Conveyor по кругу;
##   * AQUA_SLIDER (AquaSlider, Аквапарк): тянет 96 px/с = 12 м/с по своей оси −Z
##     (угол − 90°), скользко: drift-recover ÷3, торможение ÷5; вода течёт 64 px/с;
##     звук AquaSliderRiver по кругу;
##   * ICE (Ice, Снежная/Шинозавод/Аквапарк): лёд — то же, что пятно мороженого
##     (IceSpot: разгон, торможение и сцепление ÷2.5, пятна не складываются);
##   * MUD (наша, мини-кладбище «Хэллоуина»): раскисшая земля — машина буксует: предел
##     скорости ×0.55, разгон ×0.45, руль ×0.85, из-под колёс летят комья (CarFx).
## Размер — size (м, по осям X и Z узла); картинка и коллизия строятся при загрузке.
## Звук — только для своей машины (IsMe), как в оригинале: появляется за 0.1 с, гаснет за 0.2 с.

enum Kind { CONVEYOR, AQUA_SLIDER, ICE, MUD }

const PX_PER_M := 8.0
const CONVEYOR_PUSH := 16.0
const SLIDER_PUSH := 12.0
const SLIDER_EFFECT_ID := &"aqua_slider"
const SLIDER_COUNT_META := &"aqua_sliders"
const SLIDER_EFFECT_META := &"aqua_slider_effect"
const MUD_EFFECT_ID := &"mud"
## Сколько зон грязи под машиной (CarFx по нему бросает комья из-под колёс).
const MUD_COUNT_META := &"mud_zones"
const MUD_EFFECT_META := &"mud_effect"
## Грязь шире этого, м, — «на всю дорогу» (почти прямоугольная), уже — овальное пятно.
const MUD_FULL_WIDTH := 9.0
const MUD_MULTIPLIERS := {&"max_speed": 0.55, &"acceleration": 0.45, &"steering": 0.85}
## Сдвиг картинки, px/с (Conveyor: ImageOffsetX + 128·dt; AquaSlider: ImageOffsetY − 64·dt).
const CONVEYOR_SCROLL := Vector2(128.0, 0.0)
const SLIDER_SCROLL := Vector2(0.0, -64.0)
const LOUD_DB := 0.0
const SILENT_DB := -50.0

@export var kind: Kind = Kind.CONVEYOR:
	set(value):
		kind = value
		_rebuild()
## Размер зоны, м: x — по оси X узла, y — по оси Z.
@export var size: Vector2 = Vector2(6.0, 6.0):
	set(value):
		size = value
		_rebuild()
## Подкраска картинки с прозрачностью (цвет экземпляра в оригинале: лёд Снежной — голубой,
## лужи Шинозавода — жёлто-оранжевые 50 %, Аквапарка — синие).
@export var tint: Color = Color.WHITE:
	set(value):
		tint = value
		_rebuild()
@export var conveyor_texture: Texture2D
@export var slider_texture: Texture2D
@export var ice_texture: Texture2D
@export var mud_texture: Texture2D
@export var mud_shader: Shader
@export var conveyor_sound: AudioStream
@export var slider_sound: AudioStream

var _material: StandardMaterial3D
var _cars_inside: Array[CarController] = []
var _loop: AudioStreamPlayer
var _loop_tween: Tween


func _ready() -> void:
	_rebuild()
	if Engine.is_editor_hint():
		return
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return
	for car in _cars_inside:
		if is_instance_valid(car):
			_leave(car)
	_cars_inside.clear()


func _process(delta: float) -> void:
	if _material == null or kind == Kind.ICE or kind == Kind.MUD:
		return
	var scroll := CONVEYOR_SCROLL if kind == Kind.CONVEYOR else SLIDER_SCROLL
	var texture := _texture()
	if texture == null:
		return
	# uv1_offset — в долях плитки: px/с ÷ размер картинки.
	_material.uv1_offset -= Vector3(scroll.x / texture.get_width(), scroll.y / texture.get_height(), 0.0) * delta


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or kind == Kind.ICE or kind == Kind.MUD:
		return
	var push := global_basis.x * CONVEYOR_PUSH if kind == Kind.CONVEYOR else -global_basis.z * SLIDER_PUSH
	for car in _cars_inside:
		if is_instance_valid(car) and not car.is_puppet:
			car.add_push(push)


func _on_body_entered(body: Node3D) -> void:
	var car := body as CarController
	if car == null or car.is_puppet or car in _cars_inside:
		return
	_cars_inside.append(car)
	_enter(car)


func _on_body_exited(body: Node3D) -> void:
	var car := body as CarController
	if car != null and car in _cars_inside:
		_cars_inside.erase(car)
		_leave(car)


func _enter(car: CarController) -> void:
	match kind:
		Kind.ICE:
			IceSpot._enter(car)
		Kind.AQUA_SLIDER:
			var count := int(car.get_meta(SLIDER_COUNT_META, 0)) + 1
			car.set_meta(SLIDER_COUNT_META, count)
			var effects := CarEffects.of(car)
			if count == 1 and effects != null:
				car.set_meta(SLIDER_EFFECT_META, effects.add(SLIDER_EFFECT_ID, INF,
						{&"drift_recover": 1.0 / 3.0, &"deceleration": 1.0 / 5.0}))
		Kind.MUD:
			var count := int(car.get_meta(MUD_COUNT_META, 0)) + 1
			car.set_meta(MUD_COUNT_META, count)
			var effects := CarEffects.of(car)
			if count == 1 and effects != null:
				car.set_meta(MUD_EFFECT_META, effects.add(MUD_EFFECT_ID, INF, MUD_MULTIPLIERS))
	if car.is_in_group(ItemObject.LOCAL_PLAYER_GROUP):
		_set_loop(true)


func _leave(car: CarController) -> void:
	match kind:
		Kind.ICE:
			IceSpot._leave(car)
		Kind.AQUA_SLIDER:
			var count := maxi(int(car.get_meta(SLIDER_COUNT_META, 0)) - 1, 0)
			car.set_meta(SLIDER_COUNT_META, count)
			if count == 0 and car.has_meta(SLIDER_EFFECT_META):
				var effects := CarEffects.of(car)
				if effects != null:
					effects.remove(car.get_meta(SLIDER_EFFECT_META) as CarEffect)
				car.remove_meta(SLIDER_EFFECT_META)
		Kind.MUD:
			var count := maxi(int(car.get_meta(MUD_COUNT_META, 0)) - 1, 0)
			car.set_meta(MUD_COUNT_META, count)
			if count == 0 and car.has_meta(MUD_EFFECT_META):
				var effects := CarEffects.of(car)
				if effects != null:
					effects.remove(car.get_meta(MUD_EFFECT_META) as CarEffect)
				car.remove_meta(MUD_EFFECT_META)
	if car.is_in_group(ItemObject.LOCAL_PLAYER_GROUP):
		_set_loop(false)


## Звук ленты/реки для своей машины: Audio.play −50 дБ → fade 0 дБ за 0.1 с; выход — −100 за 0.2 с.
func _set_loop(on: bool) -> void:
	var stream := conveyor_sound if kind == Kind.CONVEYOR else slider_sound if kind == Kind.AQUA_SLIDER else null
	if stream == null or DisplayServer.get_name() == "headless":
		return
	if _loop == null:
		_loop = AudioStreamPlayer.new()
		_loop.bus = Sfx.BUS
		_loop.stream = stream
		add_child(_loop)
	if _loop_tween != null:
		_loop_tween.kill()
	_loop_tween = create_tween()
	if on:
		if not _loop.playing:
			_loop.volume_db = SILENT_DB
			_loop.play()
		_loop_tween.tween_property(_loop, ^"volume_db", LOUD_DB, 0.1)
	else:
		_loop_tween.tween_property(_loop, ^"volume_db", SILENT_DB, 0.2)
		_loop_tween.tween_callback(_loop.stop)


func _texture() -> Texture2D:
	match kind:
		Kind.CONVEYOR:
			return conveyor_texture
		Kind.AQUA_SLIDER:
			return slider_texture
		Kind.MUD:
			return mud_texture
	return ice_texture


## Картинка (плоскость у земли) и коллизия по size; узлы не сохраняются в сцену.
func _rebuild() -> void:
	if not is_inside_tree():
		return
	for child in get_children():
		if child.has_meta(&"generated"):
			remove_child(child)
			child.queue_free()
	var texture := _texture()
	_material = StandardMaterial3D.new()
	_material.albedo_texture = texture
	_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	_material.albedo_color = tint
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if tint.a < 1.0 \
			else BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	if texture != null and kind != Kind.ICE:
		# Плитка в масштабе оригинала (8 px = 1 м) — лента и вода повторяются, лёд растянут.
		# Картинка горки (152 px) — ровно её ширина в оригинале, с бортиками по краям:
		# поперёк одна картинка на всю ширину, вдоль — повторяется.
		var across := 1.0 if kind == Kind.AQUA_SLIDER else size.x * PX_PER_M / texture.get_width()
		_material.uv1_scale = Vector3(across, size.y * PX_PER_M / texture.get_height(), 1.0)
	var plane := PlaneMesh.new()
	plane.size = size
	plane.material = _material
	if kind == Kind.ICE and texture != null:
		# Лёд и лужи — «водичка» (puddle.gdshader): рябь, блики, кромка.
		plane.material = IceSpot.puddle_material(texture, tint)
	if kind == Kind.MUD and texture != null and mud_shader != null:
		# Грязь — пятно с рваным краем (mud.gdshader).
		var mud := ShaderMaterial.new()
		mud.shader = mud_shader
		mud.set_shader_parameter(&"mud_texture", texture)
		mud.set_shader_parameter(&"size", size)
		# Пятно уже дороги — овальная лужа; на всю ширину (от 9 м) — почти прямоугольник
		# от стены до стены, рваные только края.
		mud.set_shader_parameter(&"roundness", 2.5 if size.x < MUD_FULL_WIDTH else 8.0)
		plane.material = mud
	var mesh := MeshInstance3D.new()
	mesh.name = "Visual"
	mesh.mesh = plane
	# Зоны лежат над дорогой (0.03) и под ускорителями (0.12); пятна, налезающие друг на друга,
	# — на чуть разной высоте по имени узла, иначе они мерцали бы (Z-fighting).
	mesh.position = Vector3.UP * (0.05 + 0.008 * (absi(hash(String(name))) % 6))
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.set_meta(&"generated", true)
	add_child(mesh)
	var shape := BoxShape3D.new()
	# Лёд оригинала — пятно неровной формы: коллизия чуть меньше картинки.
	# Грязь — с рваным краем (пятно — овал): коллизия тоже меньше картинки.
	var k := 0.8 if kind == Kind.ICE else 1.0
	if kind == Kind.MUD:
		k = 0.85 if size.x >= MUD_FULL_WIDTH else 0.72
	shape.size = Vector3(size.x * k, 1.0, size.y * k)
	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	collision.shape = shape
	collision.position = Vector3.UP * 0.5
	collision.set_meta(&"generated", true)
	add_child(collision)
	# Рамка редактора карт (addons/track_editor/map_zone_gizmo.gd) — по новому размеру.
	update_gizmos()
