class_name MusicTrigger
extends Area3D
## Невидимый триггер оригинала (Trigger, Act = «Music X»): своя машина въехала — играет
## музыка X по кругу (Audio.play-by-name, тег music). Триггеры «Achieve X» (ачивки
## GamePush) не переносятся — ачивок в ремейке нет.

@export var music: AudioStream

signal triggered(car: CarController)


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	var car := body as CarController
	if car == null or not car.is_in_group(ItemObject.LOCAL_PLAYER_GROUP) or music == null:
		return
	GameMusic.player().play(music)
	triggered.emit(car)
