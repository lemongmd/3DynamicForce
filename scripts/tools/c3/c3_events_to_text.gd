extends SceneTree
## Event sheet оригинала (Construct 3, JSON) -> читаемый псевдокод (IF/-> действия, группы, функции).
## Запуск из корня проекта:
##   godot --headless --path . -s res://scripts/tools/c3/c3_events_to_text.gd -- "DF C3 project/eventSheets/LevelS.json" docs/original/events/LevelS.txt
var _out := PackedStringArray()


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var data = JSON.parse_string(FileAccess.get_file_as_string(a[0]))
	_out.append("SHEET " + str(data.get("name", "")))
	for e in data.get("events", []):
		_event(e, 0)
	var f := FileAccess.open(a[1], FileAccess.WRITE)
	f.store_string("\n".join(_out))
	print("lines ", _out.size())
	quit()


func _ind(d: int) -> String:
	return "  ".repeat(d)


func _params(p) -> String:
	if p == null:
		return ""
	if p is Array:
		return ", ".join(p.map(func(x): return str(x)))
	var parts := PackedStringArray()
	for k in p:
		parts.append("%s=%s" % [k, str(p[k])])
	return ", ".join(parts)


func _cond(c: Dictionary) -> String:
	var s := ""
	if c.get("isInverted", false):
		s += "NOT "
	var obj := str(c.get("objectClass", ""))
	if c.has("behaviorType"):
		obj += "." + str(c["behaviorType"])
	if c.has("callFunction"):
		return s + "call %s(%s)" % [c["callFunction"], _params(c.get("parameters"))]
	return s + "%s.%s(%s)" % [obj, c.get("id", "?"), _params(c.get("parameters"))]


func _action(a: Dictionary) -> String:
	if a.has("callFunction"):
		return "call %s(%s)" % [a["callFunction"], _params(a.get("parameters"))]
	if a.get("type", "") == "script" or a.has("script"):
		return "JS: " + str(a.get("script", "")).replace("\n", " | ")
	var obj := str(a.get("objectClass", ""))
	if a.has("behaviorType"):
		obj += "." + str(a["behaviorType"])
	var dis := "(disabled) " if a.get("disabled", false) else ""
	return dis + "%s.%s(%s)" % [obj, a.get("id", "?"), _params(a.get("parameters"))]


func _event(e: Dictionary, d: int) -> void:
	var t := str(e.get("eventType", ""))
	var dis := " (DISABLED)" if e.get("disabled", false) else ""
	match t:
		"comment":
			var text := str(e.get("text", "")).strip_edges()
			if not text.is_empty():
				_out.append(_ind(d) + "// " + text.replace("\n", " "))
			return
		"variable":
			_out.append(_ind(d) + "var %s: %s = %s%s" % [e.get("name"), e.get("type"), e.get("initialValue"), " (const)" if e.get("isConstant", false) else ""])
			return
		"include":
			_out.append(_ind(d) + "include " + str(e.get("includeSheet")))
			return
		"group":
			_out.append(_ind(d) + "== GROUP %s%s ==" % [e.get("title"), dis])
		"function-block":
			var ps := PackedStringArray()
			for p in e.get("functionParameters", []):
				ps.append("%s:%s" % [p.get("name"), p.get("type")])
			_out.append(_ind(d) + "FUNCTION %s(%s)%s" % [e.get("functionName"), ", ".join(ps), dis])
		"custom-ace-block":
			_out.append(_ind(d) + "ACE %s.%s%s" % [e.get("objectClass"), e.get("aceName"), dis])
		"script":
			_out.append(_ind(d) + "JS: " + str(e.get("script", "")).replace("\n", " | "))
			return
		_:
			pass
	var conds: Array = e.get("conditions", [])
	if not conds.is_empty():
		var joiner := " OR " if e.get("isOrBlock", false) else " AND "
		_out.append(_ind(d) + "IF " + joiner.join(PackedStringArray(conds.map(func(c): return _cond(c)))) + dis)
	elif t == "block":
		_out.append(_ind(d) + "ALWAYS" + dis)
	for a in e.get("actions", []):
		_out.append(_ind(d + 1) + "-> " + _action(a))
	for c in e.get("children", []):
		_event(c, d + 1)
