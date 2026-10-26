class_name NetCheck
extends Node
## Проверка сети для игры через интернет (кнопка «ПРОВЕРКА СЕТИ» в меню):
##   * трекеры — через них игроки находят друг друга по ID (WebSocket открывается или нет);
##   * роутер (NAT) — запросы к двум STUN-серверам с одного порта: если роутер показывает
##     обоим один и тот же внешний порт, прямое соединение пробивается («обычный» NAT);
##     разные порты — «строгий» (symmetric) NAT: соединение выйдет, только если у второго
##     игрока роутер обычный, иначе нужен свой TURN-сервер (TubeContext.turn_servers).
## Итог — строки для меню (signal finished), они же пишутся в журнал игры.

signal finished(lines: PackedStringArray)

## Сколько ждать ответов, с.
const WAIT := 8.0

var _sockets: Dictionary = {}  # url -> WebSocketPeer
var _diagnosis: TubeNetworkDiagnosisPeer
var _nat := TubeNetworkDiagnosisPeer.Compliance.UNKNOWN
var _time := 0.0
var _running := false


func start(context: TubeContext) -> void:
	_sockets.clear()
	for url in context.trackers_urls:
		var socket := WebSocketPeer.new()
		if socket.connect_to_url(url) == OK:
			_sockets[url] = socket
	_nat = TubeNetworkDiagnosisPeer.Compliance.UNKNOWN
	_diagnosis = null
	if TubeClient.is_webrtc_available() and context.stun_servers_urls.size() >= 2:
		# Свой случайный порт: вдруг игра уже занимает какой-то.
		_diagnosis = TubeNetworkDiagnosisPeer.new(randi_range(40000, 49999))
		_diagnosis.nat_hole_punching_compliance_updated.connect(func(compliance: TubeNetworkDiagnosisPeer.Compliance) -> void:
			_nat = compliance)
		_diagnosis.start_nat_hole_punching_detection(context.stun_servers_urls)
	_time = 0.0
	_running = true


func _process(delta: float) -> void:
	if not _running:
		return
	_time += delta
	for socket: WebSocketPeer in _sockets.values():
		socket.poll()
	if _diagnosis != null and _time < TubeNetworkDiagnosisPeer.WAITING_TIME:
		_diagnosis._process(delta)
	var trackers_done := _sockets.values().all(func(socket: WebSocketPeer) -> bool:
		return socket.get_ready_state() != WebSocketPeer.STATE_CONNECTING)
	if (trackers_done and _nat != TubeNetworkDiagnosisPeer.Compliance.UNKNOWN) or _time >= WAIT:
		_finish()


func _finish() -> void:
	_running = false
	var open := 0
	for socket: WebSocketPeer in _sockets.values():
		if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
			open += 1
		socket.close()
	if _diagnosis != null:
		_diagnosis.peer.close()
	var lines := PackedStringArray()
	if open == 0:
		lines.append("трекеры не отвечают, через интернет не войти. Мешает отсутствие интернета, файрвол или антивирус")
	else:
		lines.append("трекеры: %d из %d отвечают" % [open, _sockets.size()])
	match _nat:
		TubeNetworkDiagnosisPeer.Compliance.YES:
			lines.append("роутер: обычный NAT, прямое соединение проходит")
		TubeNetworkDiagnosisPeer.Compliance.NO:
			lines.append("роутер: строгий NAT. Войти получится, если у друга обычный. Если строгий у обоих, нужен TURN-сервер")
		_:
			lines.append("роутер: STUN-серверы не ответили, возможно, файрвол закрыл UDP. Через интернет, скорее всего, не соединится")
	for line in lines:
		print("проверка сети: ", line)
	finished.emit(lines)
