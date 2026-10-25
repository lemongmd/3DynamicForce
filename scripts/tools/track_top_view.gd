extends SceneTree
## Снимок карты сверху (ортографическая камера): дорога, стены, объекты — для сравнения
## с картой оригинала (docs/original/maps) и проверки ровной расстановки.
##
## Запуск (нужно окно, не --headless):
##   godot --path . -s res://scripts/tools/track_top_view.gd -- res://scenes/tracks/map_b.tscn C:/путь/top.png [размер_px] [--marks]
## Код возврата 0 — снимок сохранён.

const DEFAULT_SIZE := 1536


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("Аргументы: <res://трасса.tscn> <путь.png> [размер_px]")
		quit(1)
		return
	var size := int(args[2]) if args.size() > 2 else DEFAULT_SIZE
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(size, size)
	var track := (load(args[0]) as PackedScene).instantiate() as Track
	root.add_child(track)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-70.0, 30.0, 0.0)
	root.add_child(light)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.7)
	root.add_child(env)
	for i in 5:
		await process_frame

	# Границы — по центральной линии трассы с запасом на дорогу и стены.
	var bounds := AABB(track.get_point_at(0.0), Vector3.ZERO)
	var offset := 0.0
	while offset < track.length:
		bounds = bounds.expand(track.get_point_at(offset))
		offset += 2.0
	var margin := track.road_width + 2.0 * track.wall_width + 4.0
	bounds = bounds.grow(margin)
	# --marks: подписи расстояния от старта каждые 25 м у правого края (для ручной расстановки).
	if OS.get_cmdline_user_args().has("--marks"):
		var mark := 0.0
		while mark < track.length:
			var dir := track.get_direction_at(mark)
			var right := dir.cross(Vector3.UP).normalized()
			var label := Label3D.new()
			label.text = "%d" % int(mark)
			label.font_size = 64
			label.pixel_size = 0.04
			label.modulate = Color(1.0, 1.0, 0.2)
			label.outline_size = 12
			label.no_depth_test = true
			label.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
			label.position = track.get_point_at(mark) + right * (track.road_width * 0.5 + track.wall_width + 3.0) + Vector3.UP * 2.0
			root.add_child(label)
			var tick := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(track.road_width, 0.1, 0.4)
			var material := StandardMaterial3D.new()
			material.albedo_color = Color(1.0, 1.0, 0.2)
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			box.material = material
			tick.mesh = box
			tick.position = track.get_point_at(mark) + Vector3.UP * 0.2
			tick.rotation.y = atan2(-dir.x, -dir.z)
			root.add_child(tick)
			mark += 25.0
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = maxf(bounds.size.x, bounds.size.z)
	camera.far = 500.0
	root.add_child(camera)
	var center := bounds.get_center()
	camera.global_transform = Transform3D(Basis.from_euler(Vector3(-PI * 0.5, 0.0, 0.0)),
			Vector3(center.x, bounds.end.y + 100.0, center.z))
	camera.make_current()
	for i in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	var err := root.get_texture().get_image().save_png(args[1])
	print("Снимок %s -> %s: %s (%.0f × %.0f м)" % [args[0], args[1], error_string(err), bounds.size.x, bounds.size.z])
	quit(0 if err == OK else 1)
