class_name ItemBox
extends Area3D
## Коробка предметов оригинала (ItemBox): полупрозрачный куб 2 м с радужным «?»,
## висит на высоте 1 м, качается вверх-вниз (0.5 м, период 2 с) и вращается 70 °/с.
##
## Машина въехала — получает случайный предмет (ItemCatalog), звук Tidin; коробка
## сжимается за 0.2 с и через 4 с снова появляется (растёт за 0.2 с). Пока её нет,
## взять нельзя (Usable в оригинале). Призраки (финишировавшие) коробку не берут:
## у них нет слоя машин.

## Кто-то взял коробку.
signal picked(car: CarController, item: Item)

## Высота низа коробки над дорогой, м (zElevation 8 px).
const HOVER_HEIGHT := 1.0
## Ребро куба, м (16 px); узел Model — его центр, чтобы сжиматься к середине.
const BOX_SIZE := 2.0
## Качание: размах, м, и период, с (UpDownSine: 4 px, 2 с).
const BOB_HEIGHT := 0.5
const BOB_PERIOD := 2.0
## Вращение, °/с (Rotate: 70).
const SPIN_SPEED_DEG := 70.0
## Через сколько секунд коробка появляется снова.
const RESPAWN_TIME := 4.0
## Сжатие и появление, с.
const SCALE_TIME := 0.2
## Полупрозрачное «стекло» коробки (в оригинале непрозрачность 0.5) + френель, радужный
## перелив и бегущий блик (assets/shaders/item_box.gdshader).
const SHADER := preload("res://assets/shaders/item_box.gdshader")

@export var pickup_sound: AudioStream

## Номер коробки в гонке (Race.item_boxes) — по нему коробку находят в сети.
var index: int = -1
## Гонка (ставит Race): предмет зависит от места взявшего (ItemCatalog.item_for_place).
var race_manager: RaceManager
## Сеть: уже спросили хоста, ждём ответа.
var _requested: bool = false
## Можно ли взять коробку сейчас.
var usable: bool = true

var _time: float = 0.0
var _tween: Tween

@onready var _model: Node3D = $Model


func _ready() -> void:
	for node in _model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		for i in mesh.mesh.get_surface_count():
			var source := mesh.get_active_material(i) as BaseMaterial3D
			var glass := ShaderMaterial.new()
			glass.shader = SHADER
			if source != null:
				glass.set_shader_parameter(&"albedo_texture", source.albedo_texture)
			mesh.set_surface_override_material(i, glass)
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_update_model(0.0)
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_time += delta
	_update_model(delta)


## Отдать машине случайный предмет. false — коробки сейчас нет или у машины нет слота.
func pick(car: CarController, item: Item = null) -> bool:
	if not usable or CarItems.of(car) == null:
		return false
	take(car, item if item != null else item_for(car))
	return true


## Предмет из коробки для машины car — по её месту в гонке.
func item_for(car: CarController) -> Item:
	var share := race_manager.place_share(car) if race_manager != null else -1.0
	return ItemCatalog.item_for_place(share)


## Коробку взяла машина car: исчезает у всех; предмет item (если не null) — в слот car.
## В сети зовётся у всех по решению хоста; предмет получает только хозяин машины.
func take(car: CarController, item: Item) -> void:
	if not usable:
		return
	_requested = false
	if car != null and item != null:
		var items := CarItems.of(car)
		if items != null:
			items.give(item)
	if car != null:
		Sfx.play(car, pickup_sound)
	Fx.burst([&"item_sparkle"], get_parent(), _model.global_position)
	usable = false
	_scale_to(Vector3.ONE * 0.001, Tween.EASE_IN)
	get_tree().create_timer(RESPAWN_TIME, false, true).timeout.connect(_on_respawn)
	picked.emit(car, item)


func _on_body_entered(body: Node3D) -> void:
	var car := body as CarController
	if car == null or car.is_puppet:
		return
	if not Network.session().is_online():
		pick(car)
	elif usable and not _requested:
		# Сеть: что внутри и кому досталось, решает хост (Network.session()._box_taken).
		_requested = true
		Network.session().request_box(index)
		get_tree().create_timer(1.0, false).timeout.connect(func() -> void: _requested = false)


func _on_respawn() -> void:
	usable = true
	_scale_to(Vector3.ONE, Tween.EASE_OUT)


func _scale_to(target: Vector3, ease_type: Tween.EaseType) -> void:
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_model, ^"scale", target, SCALE_TIME).set_trans(Tween.TRANS_BACK).set_ease(ease_type)


func _update_model(delta: float) -> void:
	_model.position.y = HOVER_HEIGHT + BOX_SIZE * 0.5 + BOB_HEIGHT * sin(TAU * _time / BOB_PERIOD)
	_model.rotate_y(deg_to_rad(SPIN_SPEED_DEG) * delta)
