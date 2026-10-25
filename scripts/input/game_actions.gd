class_name GameActions
extends RefCounted
## Имена действий InputMap. Используй эти константы вместо строк в коде.
## Привязки клавиш/геймпада задаются в scripts/tools/setup_project.gd
## (или вручную в «Проект → Настройки проекта → Список действий»).

const STEER_LEFT := &"steer_left"
const STEER_RIGHT := &"steer_right"
const ACCELERATE := &"accelerate"
const BRAKE := &"brake"
const DRIFT := &"drift"
const PARRY := &"parry"
const USE_ITEM := &"use_item"
const PAUSE := &"pause"
## Общая громкость (держать − / +, как в оригинале).
const VOLUME_UP := &"volume_up"
const VOLUME_DOWN := &"volume_down"

## Отладочные действия (только для тестовых сцен).
const DEBUG_RESET := &"debug_reset"
const DEBUG_TOUCH_CONTROLS := &"debug_touch_controls"
