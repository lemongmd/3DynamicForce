extends SceneTree
## Скриншот из игры (камера машины) в выбранном месте карты — проверить расстановку глазами.
##
## Запуск (нужно окно):
##   godot --path . -s res://scripts/tools/map_shot.gd -- map_b 230 C:/путь/shot.png [ещё_расстояние …]
## Машина ставится на трассу в указанные метры от старта (во время отсчёта она стоит),
## для каждого расстояния — свой снимок (<путь>_<метры>.png, если расстояний несколько).
## --spawn=res://сцена.tscn — поставить объект в 8 м перед машиной (посмотреть его вид).


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var race := (load("res://scenes/race/race.tscn") as PackedScene).instantiate() as Race
	race.track_scene = load("res://scenes/tracks/%s.tscn" % args[0]) as PackedScene
	race.autostart = false
	root.add_child(race)
	var autopilot := AutopilotInputSource.new()
	autopilot.track = race.track
	race.add_child(autopilot)
	var racer := race.spawn_racer("Игрок", true, autopilot)
	race.begin()
	var out: String = args[2]
	var spawn_scene := ""
	for arg in args:
		if arg.begins_with("--spawn="):
			spawn_scene = arg.trim_prefix("--spawn=")
	var offsets := PackedStringArray()
	for k in args.size():
		if (k == 1 or k > 2) and not args[k].begins_with("--"):
			offsets.append(args[k])
	for text in offsets:
		var offset := float(text)
		racer.car.teleport(race.track.get_transform_at(offset))
		if not spawn_scene.is_empty():
			var node := (load(spawn_scene) as PackedScene).instantiate() as Node3D
			race.add_child(node)
			node.global_transform = race.track.get_transform_at(offset + 8.0)
		for i in 45:
			await physics_frame
		await RenderingServer.frame_post_draw
		var path := out if offsets.size() == 1 else out.get_basename() + "_%d.png" % int(offset)
		var err := root.get_texture().get_image().save_png(path)
		print("снимок %s @ %.0f м -> %s: %s" % [args[0], offset, path, error_string(err)])
	quit(0)
