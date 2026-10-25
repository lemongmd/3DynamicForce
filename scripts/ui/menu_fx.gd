class_name MenuFx
extends RefCounted
## Мелочи меню: звуки оригинала (Click — нажатие, Chosen — выбор карты, Cancel — назад)
## и «живые» кнопки: при наведении или фокусе кнопка подпрыгивает и чуть растёт.

const CLICK := preload("res://assets/original/sounds/click.wav")
const CHOSEN := preload("res://assets/original/sounds/chosen.wav")
const CANCEL := preload("res://assets/original/sounds/cancel.wav")
## Насколько растёт кнопка под курсором.
const HOVER_SCALE := 1.12


static func click() -> void:
	_play(CLICK)


static func chosen() -> void:
	_play(CHOSEN)


static func cancel() -> void:
	_play(CANCEL)


static func _play(stream: AudioStream) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		Sfx.play(tree.root, stream)


## Кнопка растёт под курсором/фокусом (от центра) и щёлкает при нажатии.
static func juicy(button: BaseButton, with_click: bool = true) -> void:
	var grow := func(on: bool) -> void:
		button.pivot_offset = button.size * 0.5
		var tween := button.create_tween()
		tween.tween_property(button, ^"scale", Vector2.ONE * (HOVER_SCALE if on else 1.0), 0.12) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	button.mouse_entered.connect(grow.bind(true))
	button.mouse_exited.connect(grow.bind(false))
	button.focus_entered.connect(grow.bind(true))
	button.focus_exited.connect(grow.bind(false))
	if with_click:
		button.pressed.connect(click)
