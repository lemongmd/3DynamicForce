extends Node
## Автозагрузка «PixelUi»: всплывающие окна интерфейса (выпадающие списки, подсказки) —
## это отдельные Window со своим фильтром текстур, по умолчанию сглаживающим (Linear).
## Пиксельный шрифт в них «мылится». Каждому новому окну ставим фильтр Nearest,
## как у основного экрана (rendering/textures/canvas_textures/default_texture_filter).


func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)


func _on_node_added(node: Node) -> void:
	var window := node as Window
	if window != null:
		window.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
