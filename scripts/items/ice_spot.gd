class_name IceSpot
extends ItemObject
## Пятно льда (Ice оригинала; мороженое Icecream оставляет 5 таких пятен).
## Пока машина стоит хотя бы на одном пятне — скользко: разгон, торможение и
## drift-recover ÷2.5 (IceStrenght оригинала). Несколько пятен сразу не складываются
## (в оригинале «trigger once while true»). Своё пятно хозяина не задевает (в оригинале
## у своих пятен выключены коллизии). Пятна льда на картах (этап 7) — те же, без хозяина.

## Во сколько раз лёд ослабляет разгон, торможение и сцепление.
const ICE_STRENGTH := 2.5
## Пятна мороженого — сильнее льда карт, но только по управлению (скорость не трогают:
## «предмет должен влиять на лёгкость управления, а не на скорость» — автор ремейка):
## машина «неуклюжая» — сцепление ÷ITEM_GRIP (занос держится дольше) и руль ×ITEM_STEERING
## (поворачивает вяло). Раньше на въезде нос резко уводило на 30° — тестерам не понравилось
## («рандомно резко разворачивает»). В оригинале — только ÷2.5.
const ITEM_GRIP := 4.0
const ITEM_STEERING := 0.5
const EFFECT_ID := &"ice"
const COUNT_META := &"ice_spots"
const EFFECT_META := &"ice_effect"
const PUDDLE_SHADER := preload("res://assets/shaders/puddle.gdshader")

var _cars_inside: Array[CarController] = []


func _ready() -> void:
	super._ready()
	body_exited.connect(_on_body_exited)


func _exit_tree() -> void:
	super._exit_tree()
	for car in _cars_inside:
		if is_instance_valid(car):
			_leave(car)
	_cars_inside.clear()


## Материал «водички» для пятна/лужи: картинка оригинала + цвет (puddle.gdshader).
static func puddle_material(texture: Texture2D, tint: Color) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = PUDDLE_SHADER
	material.set_shader_parameter(&"albedo_texture", texture)
	material.set_shader_parameter(&"tint", tint)
	material.set_shader_parameter(&"pixels", float(texture.get_width()))
	return material


func _on_spawned() -> void:
	super._on_spawned()
	var sprite := _visual as Sprite3D
	if sprite != null and sprite.texture != null:
		# Цвет пятна (modulate спрайта) шейдер берёт из цвета вершин.
		sprite.material_override = puddle_material(sprite.texture, Color.WHITE)
	_apply_alpha()


func _apply_alpha() -> void:
	var sprite := _visual as Sprite3D
	if sprite != null and sprite.material_override is ShaderMaterial:
		# Затухание — только через opacity шейдера: цвет спрайта (COLOR) он и так умножает,
		# и общий _apply_alpha погасил бы пятно дважды. Цвет — исходный: первый вызов (ещё без
		# шейдера, в начале появления) успевал обнулить его альфу — пятно было невидимым.
		if _sprite_colors.has(sprite):
			sprite.modulate = _sprite_colors[sprite]
		(sprite.material_override as ShaderMaterial).set_shader_parameter(&"opacity", _base_alpha * get_fade())
	else:
		super._apply_alpha()


func _hit(car: CarController) -> void:
	if car in _cars_inside:
		return
	_cars_inside.append(car)
	_enter(car, true)


func _on_body_exited(body: Node3D) -> void:
	var car := body as CarController
	if car != null and car in _cars_inside:
		_cars_inside.erase(car)
		_leave(car)


## Машина на льду (сколько пятен под ней — в метаданных машины).
static func is_on_ice(car: CarController) -> bool:
	return int(car.get_meta(COUNT_META, 0)) > 0


## from_item — пятно мороженого: сцепление слабее, чем у льда карт, и руль вялый.
static func _enter(car: CarController, from_item: bool = false) -> void:
	var count := int(car.get_meta(COUNT_META, 0)) + 1
	car.set_meta(COUNT_META, count)
	if count == 1:
		var effects := CarEffects.of(car)
		if effects != null:
			var k := 1.0 / ICE_STRENGTH
			var grip := 1.0 / ITEM_GRIP if from_item else k
			var multipliers := {&"acceleration": k, &"deceleration": k, &"drift_recover": grip}
			if from_item:
				multipliers[&"steering"] = ITEM_STEERING
			car.set_meta(EFFECT_META, effects.add(EFFECT_ID, INF, multipliers))


static func _leave(car: CarController) -> void:
	var count := maxi(int(car.get_meta(COUNT_META, 0)) - 1, 0)
	car.set_meta(COUNT_META, count)
	if count == 0 and car.has_meta(EFFECT_META):
		var effects := CarEffects.of(car)
		if effects != null:
			effects.remove(car.get_meta(EFFECT_META) as CarEffect)
		car.remove_meta(EFFECT_META)
