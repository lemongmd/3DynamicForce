@tool
extends EditorNode3DGizmoPlugin
## Зоны карты (MapZone: лента, аквагорка, лёд/лужа) — рамка в 3D-виде и выбор кликом.
## Картинку зоны MapZone строит при загрузке и в сцену не сохраняет; у таких узлов своих гизмо
## нет, и редактор не находил зону под курсором — её нельзя было выделить и подвинуть.

## Рамка — чуть выше картинки зоны (0.05–0.09 м), чтобы не пряталась под ней.
const OUTLINE_HEIGHT := 0.15


func _init() -> void:
	create_material("outline", Color(1.0, 0.85, 0.2))


func _get_gizmo_name() -> String:
	return "MapZone"


func _has_gizmo(node: Node3D) -> bool:
	return node is MapZone


func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var zone := gizmo.get_node_3d() as MapZone
	if zone == null:
		return
	var hx := zone.size.x * 0.5
	var hz := zone.size.y * 0.5
	var corners := [Vector3(-hx, OUTLINE_HEIGHT, -hz), Vector3(hx, OUTLINE_HEIGHT, -hz),
			Vector3(hx, OUTLINE_HEIGHT, hz), Vector3(-hx, OUTLINE_HEIGHT, hz)]
	var lines := PackedVector3Array()
	for i in corners.size():
		lines.append(corners[i])
		lines.append(corners[(i + 1) % corners.size()])
	# Лента и горка тянут по своей оси (+X / −Z) — стрелка по направлению.
	if zone.kind != MapZone.Kind.ICE:
		var forward := Vector3.RIGHT * hx if zone.kind == MapZone.Kind.CONVEYOR else Vector3.FORWARD * hz
		var side := Vector3.FORWARD * hz * 0.4 if zone.kind == MapZone.Kind.CONVEYOR else Vector3.RIGHT * hx * 0.4
		var lift := Vector3.UP * OUTLINE_HEIGHT
		lines.append_array([lift - forward * 0.6, lift + forward * 0.6,
				lift + forward * 0.6, lift + forward * 0.2 + side,
				lift + forward * 0.6, lift + forward * 0.2 - side])
	gizmo.add_lines(lines, get_material("outline", gizmo))
	# Выбор кликом — по всей площади зоны.
	var plane := PlaneMesh.new()
	plane.size = zone.size
	gizmo.add_collision_triangles(plane.generate_triangle_mesh())
