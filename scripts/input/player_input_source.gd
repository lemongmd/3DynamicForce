class_name PlayerInputSource
extends CarInputSource
## Управление локального игрока через InputMap.
##
## Клавиатура, геймпад и сенсорные кнопки (TouchScreenButton с полем action)
## попадают в одни и те же действия InputMap, поэтому здесь нет кода под
## конкретное устройство.


func read_input(out: CarInput) -> void:
	# get_axis/get_action_strength учитывают аналоговую силу стиков и курков.
	out.steer = Input.get_axis(GameActions.STEER_LEFT, GameActions.STEER_RIGHT)
	var brake := Input.get_action_strength(GameActions.BRAKE)
	if GameSettings.autogas:
		# Автогаз (настройка): газ всегда, тормоз — тормоз/задний ход.
		out.throttle = -brake if brake > 0.0 else 1.0
	else:
		out.throttle = Input.get_action_strength(GameActions.ACCELERATE) - brake
	out.drift = Input.is_action_pressed(GameActions.DRIFT)
	# Вызывается из _physics_process, поэтому just_pressed срабатывает
	# ровно в одном физическом кадре.
	out.parry_pressed = Input.is_action_just_pressed(GameActions.PARRY)
	out.item_pressed = Input.is_action_just_pressed(GameActions.USE_ITEM)
	out.item_held = Input.is_action_pressed(GameActions.USE_ITEM)
