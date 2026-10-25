class_name Sfx
extends RefCounted
## Одноразовые звуки: каждый в своём AudioStreamPlayer, который удаляется по окончании.
## Так несколько звуков (например, «удар» + «боль») играют одновременно.
## Как в оригинале, звуки не позиционные. Шина SFX (громкость — в настройках).

const BUS := &"SFX"


## Проиграть stream; плеер живёт как дочерний узел owner_node.
static func play(owner_node: Node, stream: AudioStream, volume_db: float = 0.0) -> void:
	if stream == null or owner_node == null or not owner_node.is_inside_tree():
		return
	# Как в оригинале (IsMe): звуки чужих машин в сетевой игре не играют.
	if owner_node is CarController and (owner_node as CarController).is_puppet:
		return
	# Без экрана (тесты, будущий выделенный сервер) звука нет, а недоигранные
	# плееры висели бы в аудиосервере до выхода.
	if DisplayServer.get_name() == "headless":
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	player.bus = BUS
	owner_node.add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
