class_name TouchControlButton
extends TouchScreenButton
## Экранная кнопка: нажатие = действие InputMap (поле action у TouchScreenButton).
## Поэтому машина не отличает сенсор от клавиатуры и геймпада.

## Подпись на кнопке.
@export var caption: String = "":
	set(value):
		caption = value
		if is_node_ready():
			_caption_label.text = value

@onready var _caption_label: Label = $Caption


func _ready() -> void:
	_caption_label.text = caption
