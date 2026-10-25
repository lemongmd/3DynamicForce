class_name ItemFlash
extends Item
## Флешка (Flash оригинала): у всех остальных экран белеет полностью (слой Flash 100 %),
## у себя — на 30 %, дальше плавно гаснет (ScreenEffects). Звук Damage4 — use_sounds.

## Насколько белеет свой экран и чужой (0..1).
@export_range(0.0, 1.0) var own_opacity: float = 0.3
@export_range(0.0, 1.0) var other_opacity: float = 1.0


func use(car: CarController) -> void:
	for node in car.get_tree().get_nodes_in_group(ScreenEffects.GROUP):
		(node as ScreenEffects).flash_from(car, own_opacity, other_opacity)
	# Остальные «ослепли» (эмоция Unsee оригинала).
	for other in car.get_tree().get_nodes_in_group(CarController.GROUP):
		if other != car:
			(other as CarController).emote(&"unsee", 1.0)
