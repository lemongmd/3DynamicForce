@tool
extends Node3D
## Осеннее дерево «Хэллоуина» (декор): ствол и крона из гранёных шаров с пиксельной листвой.
## Цвет кроны (оранжевая, красная, жёлтая), размер и поворот — от места дерева: ряд деревьев
## из одной сцены не выглядит одинаковым.

const LEAVES: Array[Material] = [
	preload("res://assets/materials/leaves_orange.tres"),
	preload("res://assets/materials/leaves_red.tres"),
	preload("res://assets/materials/leaves_yellow.tres"),
]


func _ready() -> void:
	var seed_value := hash(Vector2i(roundi(global_position.x * 3.0), roundi(global_position.z * 3.0)))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var leaves: Material = LEAVES[rng.randi_range(0, LEAVES.size() - 1)]
	for crown in find_children("Crown*", "MeshInstance3D", false, false):
		(crown as MeshInstance3D).material_override = leaves
	var size := rng.randf_range(0.62, 0.95)
	scale = Vector3(size, size * rng.randf_range(0.9, 1.15), size)
	rotation.y = rng.randf() * TAU
