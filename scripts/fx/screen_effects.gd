class_name ScreenEffects
extends CanvasLayer
## Эффекты экрана игрока (над миром, под HUD — как слой Flash оригинала под интерфейсом):
##   * вспышка флешки: белый экран с непрозрачностью flash_opacity, гаснет как в оригинале —
##     выше 75 % по 10 %/с, от 75 до 50 % по 25 %/с, ниже 50 % по 50 %/с (со 100 % — 4.5 с);
##   * «пьяный» экран водки — эффект Warp (layout) оригинала: период 64 px,
##     амплитуда 8 px, скорость 1.5 (шейдер drunk.gdshader);
##   * наше: виньетка и полосы скорости, когда машина быстрее обычного предела
##     (screen_grade.gdshader).
## viewer — машина, за которой следит этот экран (её задаёт Race).

const GROUP := &"screen_effects"

var viewer: CarController
## Текущая непрозрачность вспышки (0..1).
var flash_opacity: float = 0.0

var _drunk_left: float = 0.0
var _speed_lines: float = 0.0

@onready var _flash: ColorRect = $Flash
@onready var _drunk: ColorRect = $Drunk
@onready var _grade: ColorRect = $Grade


func _ready() -> void:
	add_to_group(GROUP)
	_update_visuals()


## Флешку применила машина car: свой экран — own_opacity, чужой — other_opacity.
## Как set-layer-opacity в оригинале: значение ставится, а не прибавляется.
func flash_from(car: CarController, own_opacity: float, other_opacity: float) -> void:
	flash_opacity = own_opacity if car == viewer else other_opacity
	_update_visuals()


## «Пьяный» экран на seconds секунд, если это машина зрителя.
func drunk(car: CarController, seconds: float) -> void:
	if car == viewer:
		_drunk_left = seconds
		_update_visuals()


func is_drunk() -> bool:
	return _drunk_left > 0.0


func _process(delta: float) -> void:
	if flash_opacity > 0.0:
		var percent := flash_opacity * 100.0
		if percent < 50.0:
			percent -= delta * 50.0
		elif percent < 75.0:
			percent -= delta * 25.0
		else:
			percent -= delta * 10.0
		flash_opacity = maxf(percent / 100.0, 0.0)
	_drunk_left = maxf(_drunk_left - delta, 0.0)
	# Полосы скорости: от 105 % до 140 % обычного предела — от нуля до полной силы, плавно.
	var target := 0.0
	if is_instance_valid(viewer):
		target = clampf((viewer.get_speed_ratio() - 1.05) / 0.35, 0.0, 1.0)
	_speed_lines = move_toward(_speed_lines, target, delta * 3.0)
	if _grade != null:
		(_grade.material as ShaderMaterial).set_shader_parameter(&"speed", _speed_lines)
	_update_visuals()


func _update_visuals() -> void:
	if _flash == null:
		return
	_flash.visible = flash_opacity > 0.0
	_flash.color = Color(1.0, 1.0, 1.0, flash_opacity)
	_drunk.visible = _drunk_left > 0.0
