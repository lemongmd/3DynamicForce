extends SceneTree
## Проверка TURN/STUN игры: WebRTC (webrtc-native) с настройками Tube собирает ICE-кандидаты.
## relay — адрес на нашем TURN-сервере (значит, через него можно играть при строгом NAT),
## srflx — внешний адрес через STUN, host — локальные адреса.
## Если есть только host — запросы к серверам не уходят (например, мешает VPN в режиме TUN).
##
## Запуск (из корня проекта):
##   godot --headless --path . -s res://scripts/tools/turn_check.gd
## Код возврата 0 — есть relay.

const WAIT_MSEC := 20000

var _types := {}
var _peer: WebRTCPeerConnection


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var ice: Dictionary = Network.load_context().get_ice_servers()
	_peer = WebRTCPeerConnection.new()
	var err := _peer.initialize(ice)
	if err != OK:
		print("WebRTC не запустился: ", error_string(err))
		quit(1)
		return
	_peer.ice_candidate_created.connect(func(_mid: String, _index: int, sdp: String) -> void:
		var parts := sdp.split(" ")
		var at := parts.find("typ")
		var kind := parts[at + 1] if at >= 0 else "?"
		_types[kind] = _types.get(kind, 0) + 1
		print("  ", kind, ": ", parts[4], ":", parts[5]))
	_peer.session_description_created.connect(func(type: String, sdp: String) -> void:
		_peer.set_local_description(type, sdp))
	_peer.create_data_channel("check")
	_peer.create_offer()
	var until := Time.get_ticks_msec() + WAIT_MSEC
	while Time.get_ticks_msec() < until and not _types.has("relay"):
		_peer.poll()
		await process_frame
	_peer.close()
	if _types.has("relay"):
		print("TURN: ВСЁ ПРОШЛО (есть адрес на сервере)")
	elif _types.has("srflx"):
		print("TURN: нет relay, но STUN отвечает — проверь логин и пароль TURN в scenes/net/turn_servers.tres")
	else:
		print("TURN: только локальные адреса — запросы к серверам не уходят (VPN в режиме TUN?)")
	quit(0 if _types.has("relay") else 1)
