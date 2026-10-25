extends SceneTree
## Обзорная картинка уровня оригинала (Construct 3) сверху: фон, тайлмап, объекты.
## Невидимые объекты (чекпоинты-триггеры) — полупрозрачные; 3D-фигуры — по пятну на земле.
## Запуск из корня проекта:
##   godot --headless --path . -s res://scripts/tools/c3/c3_render_layout.gd -- "DF C3 project" MapA docs/original/maps/map_MapA.png 0.5
## Формат тайлмапа C3: RLE «NxV», V — номер тайла с 1 (0 — пусто) + флаги h/v/d,
## данные по столбцам (max-width столбцов по max-height клеток).
const FLIP_X := 0x80000000
const FLIP_Y := 0x40000000
const ROTATE := 0x20000000
const TILE_MASK := 0x1FFFFFFF

var _dir := ""
var _images := {}
var _plugins := {}
var _file_list := PackedStringArray()


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	_dir = a[0]
	var layout_name: String = a[1]
	var out: String = a[2]
	var s := float(a[3])
	_file_list = DirAccess.get_files_at(_dir + "/images")
	_load_plugins(_dir + "/objectTypes")
	var data = JSON.parse_string(FileAccess.get_file_as_string("%s/layouts/%s.json" % [_dir, layout_name]))
	var w := int(data["width"] * s)
	var h := int(data["height"] * s)
	var canvas := Image.create(w, h, false, Image.FORMAT_RGBA8)
	canvas.fill(Color(0.1, 0.1, 0.12))
	var counts := {}
	for layer in data["layers"]:
		_draw_layer(canvas, layer, s, counts)
	canvas.save_png(out)
	print("%s: %s -> %s  %s" % [layout_name, Vector2i(data["width"], data["height"]), out, counts])
	quit()


func _load_plugins(path: String) -> void:
	for f in DirAccess.get_files_at(path):
		if f.ends_with(".json") and not f.ends_with("uistate.json"):
			var j = JSON.parse_string(FileAccess.get_file_as_string(path + "/" + f))
			if j is Dictionary:
				_plugins[str(j.get("name", ""))] = str(j.get("plugin-id", ""))
	for d in DirAccess.get_directories_at(path):
		_load_plugins(path + "/" + d)


func _draw_layer(canvas: Image, layer: Dictionary, s: float, counts: Dictionary) -> void:
	for inst in layer.get("instances", []):
		_draw_instance(canvas, inst, s, counts)
	for sub in layer.get("subLayers", []):
		_draw_layer(canvas, sub, s, counts)


func _image(file: String) -> Image:
	if _images.has(file):
		return _images[file]
	var img: Image = null
	if file in _file_list:
		img = Image.new()
		if img.load(_dir + "/images/" + file) != OK:
			img = null
		else:
			img.convert(Image.FORMAT_RGBA8)
	_images[file] = img
	return img


func _frames(type_name: String, anim: String) -> Array[Image]:
	var prefix := type_name.to_lower() + "-" + anim.to_lower() + "-"
	var res: Array[Image] = []
	for f in _file_list:
		if f.begins_with(prefix):
			var img := _image(f)
			if img != null:
				res.append(img)
	return res


func _draw_instance(canvas: Image, inst: Dictionary, s: float, counts: Dictionary) -> void:
	var t := str(inst["type"])
	counts[t] = counts.get(t, 0) + 1
	var wd: Dictionary = inst["world"]
	var plugin := str(_plugins.get(t, ""))
	var props: Dictionary = inst.get("properties", {})
	if plugin == "Tilemap":
		_draw_tilemap(canvas, inst, s)
		return
	var img: Image = null
	var alpha := float(wd.get("color", [1, 1, 1, 1])[3])
	if plugin == "TiledBg":
		img = _image(t.to_lower() + ".png")
		if img != null:
			_draw_tiled(canvas, img, wd, s)
		return
	if plugin == "Sprite":
		var anim := str(props.get("initial-animation", "Animation 1"))
		var fr := _frames(t, anim)
		if fr.is_empty():
			fr = _frames(t, "animation 1")
		if not fr.is_empty():
			img = fr[clampi(int(props.get("initial-frame", 0)), 0, fr.size() - 1)]
		if not props.get("initially-visible", true):
			alpha = 0.35
	elif plugin == "Shape3D":
		var fr := _frames(t, "animation 1")
		var aspect := float(wd["width"]) / maxf(float(wd["height"]), 1.0)
		var best_err := 1e9
		for f in fr:
			var err := absf(log(float(f.get_width()) / f.get_height()) - log(aspect))
			if f.get_width() > 8 and err < best_err:
				best_err = err
				img = f
		if best_err > 0.7 and not fr.is_empty():
			img = _solid_of(fr)
	if img == null:
		return
	_blit_rotated(canvas, img, wd, s, alpha)


func _solid_of(frames: Array[Image]) -> Image:
	var biggest: Image = frames[0]
	for f in frames:
		if f.get_width() * f.get_height() > biggest.get_width() * biggest.get_height():
			biggest = f
	var c := Color(0, 0, 0, 0)
	var n := 0
	for y in biggest.get_height():
		for x in biggest.get_width():
			var p := biggest.get_pixel(x, y)
			if p.a > 0.5:
				c += p
				n += 1
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(c / maxf(n, 1) if n > 0 else Color.MAGENTA)
	return img


func _blit_rotated(canvas: Image, img: Image, wd: Dictionary, s: float, alpha: float) -> void:
	var w := float(wd["width"])
	var h := float(wd["height"])
	var ang := float(wd.get("angle", 0.0))
	var ox := float(wd.get("originX", 0.5))
	var oy := float(wd.get("originY", 0.5))
	var pos := Vector2(float(wd["x"]), float(wd["y"]))
	var tint: Array = wd.get("color", [1, 1, 1, 1])
	var c := cos(ang)
	var sn := sin(ang)
	# Углы прямоугольника в мире -> ограничивающая рамка.
	var corners := [Vector2(-ox * w, -oy * h), Vector2((1 - ox) * w, -oy * h), Vector2((1 - ox) * w, (1 - oy) * h), Vector2(-ox * w, (1 - oy) * h)]
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for p in corners:
		var r: Vector2 = pos + Vector2(p.x * c - p.y * sn, p.x * sn + p.y * c)
		mn = mn.min(r)
		mx = mx.max(r)
	var x0 := maxi(int(mn.x * s), 0)
	var y0 := maxi(int(mn.y * s), 0)
	var x1 := mini(int(mx.x * s) + 1, canvas.get_width() - 1)
	var y1 := mini(int(mx.y * s) + 1, canvas.get_height() - 1)
	for py in range(y0, y1 + 1):
		for px in range(x0, x1 + 1):
			var world := Vector2((px + 0.5) / s, (py + 0.5) / s) - pos
			var lx := world.x * c + world.y * sn
			var ly := -world.x * sn + world.y * c
			var u := lx / w + ox
			var v := ly / h + oy
			if u < 0.0 or u >= 1.0 or v < 0.0 or v >= 1.0:
				continue
			var col := img.get_pixel(int(u * img.get_width()), int(v * img.get_height()))
			col = Color(col.r * tint[0], col.g * tint[1], col.b * tint[2], col.a * alpha)
			if col.a <= 0.01:
				continue
			canvas.set_pixel(px, py, canvas.get_pixel(px, py).blend(col))


func _draw_tiled(canvas: Image, img: Image, wd: Dictionary, s: float) -> void:
	var x0 := maxi(int(float(wd["x"]) * s), 0)
	var y0 := maxi(int(float(wd["y"]) * s), 0)
	var x1 := mini(int((float(wd["x"]) + float(wd["width"])) * s), canvas.get_width())
	var y1 := mini(int((float(wd["y"]) + float(wd["height"])) * s), canvas.get_height())
	for py in range(y0, y1):
		for px in range(x0, x1):
			var wx := int(px / s - float(wd["x"]))
			var wy := int(py / s - float(wd["y"]))
			canvas.set_pixel(px, py, img.get_pixel(posmod(wx, img.get_width()), posmod(wy, img.get_height())))


func _draw_tilemap(canvas: Image, inst: Dictionary, s: float) -> void:
	# Формат C3: RLE «NxV», V = номер тайла с 1 (0 — пусто) + буквы флагов h/v/d;
	# строки хранятся с шагом total / max-width.
	var tm: Dictionary = inst["ownData"]["tilemapData"]
	var tiles := PackedInt64Array()
	for part in str(tm["data"]).split(","):
		if part.is_empty():
			continue
		var count := 1
		var value := part
		if "x" in part:
			count = int(part.get_slice("x", 0))
			value = part.get_slice("x", 1)
		var digits := ""
		var flags := 0
		for ch in value:
			if ch >= "0" and ch <= "9":
				digits += ch
			elif ch == "h":
				flags |= FLIP_X
			elif ch == "v":
				flags |= FLIP_Y
			elif ch == "d":
				flags |= ROTATE
		var number := int(digits)
		var v: int = -1 if number == 0 else ((number - 1) | flags)
		for i in count:
			tiles.append(v)
	var cols := tiles.size() / int(tm["max-width"])
	var visible_w := int(tm["width"])
	var visible_h := int(tm["height"])
	var sheet := _image("tilemap.png")
	var tw := int(inst["properties"]["tile-width"])
	var th := int(inst["properties"]["tile-height"])
	var sheet_cols := sheet.get_width() / tw
	var ox := float(inst["world"]["x"])
	var oy := float(inst["world"]["y"])
	for i in tiles.size():
		var v := tiles[i]
		if v < 0:
			continue
		var tile := int(v & TILE_MASK)
		var tx := (tile % sheet_cols) * tw
		var ty := (tile / sheet_cols) * th
		# Данные хранятся по столбцам: max-width столбцов по max-height клеток.
		var cx := i / cols
		var cy := i % cols
		if cx >= visible_w or cy >= visible_h:
			continue
		var px0 := int((ox + cx * tw) * s)
		var py0 := int((oy + cy * th) * s)
		var size := int(tw * s)
		for yy in maxi(size, 1):
			for xx in maxi(size, 1):
				var u := int(float(xx) / s)
				var vv := int(float(yy) / s)
				if v & ROTATE:
					var tmp := u
					u = vv
					vv = tmp
				if v & FLIP_X:
					u = tw - 1 - u
				if v & FLIP_Y:
					vv = th - 1 - vv
				var px := px0 + xx
				var py := py0 + yy
				if px < 0 or py < 0 or px >= canvas.get_width() or py >= canvas.get_height():
					continue
				var col := sheet.get_pixel(tx + clampi(u, 0, tw - 1), ty + clampi(vv, 0, th - 1))
				if col.a > 0.01:
					canvas.set_pixel(px, py, canvas.get_pixel(px, py).blend(col))
