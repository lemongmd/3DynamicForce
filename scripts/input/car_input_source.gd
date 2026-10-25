class_name CarInputSource
extends Node
## Базовый источник управления машиной.
##
## Наследники: PlayerInputSource (локальный игрок через InputMap),
## позже — боты и сетевой ввод. Базовый класс выдаёт «ничего не нажато».


## Заполняет out управлением на текущий физический кадр.
## Вызывается машиной из _physics_process ровно один раз за кадр.
func read_input(out: CarInput) -> void:
	out.clear()
