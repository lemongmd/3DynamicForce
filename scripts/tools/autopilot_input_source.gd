class_name AutopilotInputSource
extends CarInputSource
## Автопилот для автотестов (race_test.gd). В игре не используется: ботов в игре
## нет, это LAN-мультиплеер.
##
## Рулит к точке на центральной линии трассы впереди на своей полосе,
## заранее сбрасывает скорость перед поворотами (кривизна трассы впереди +
## тормозной путь), объезжает твёрдые препятствия (бочки, твёрдые ограждения из
## узла «Props» трассы), а перед парируемыми опасностями жмёт парирование.
## Предметы из коробок применяет по простым правилам (_want_item).
## Застрял — сдаёт назад; застрял надолго — возвращается на последний чекпоинт.

@export var car: CarController
@export var track: Track
## Доля максимальной скорости, которую автопилот себе позволяет (0..1).
@export_range(0.3, 1.0) var skill: float = 0.92
## Предпочтительная полоса: смещение от центра дороги, м (плюс — вправо).
@export var lane_offset: float = 0.0
## Сила руля на радиан отклонения от цели.
@export var steer_gain: float = 2.5
## Упреждение цели руления: база + доля скорости, м.
@export var look_ahead_base: float = 5.0
@export var look_ahead_per_speed: float = 0.3
## Запас по сцеплению в поворотах (меньше — осторожнее).
@export_range(0.3, 1.0) var corner_margin: float = 0.8
## Ниже этой скорости поворот не проходится (м/с).
@export var min_corner_speed: float = 12.0
## Насколько далеко вперёд смотреть на препятствия, м.
@export var obstacle_scan: float = 35.0
## Зазор между бортом машины и препятствием, м.
@export var obstacle_clearance: float = 1.6
## Нажать парирование за столько секунд до опасности (окно — 0.4 с).
@export var parry_lead: float = 0.2
## Сколько держать предмет в слоте, прежде чем применить, с.
@export var item_hold_time: float = 0.5

## Где на трассе смотреть кривизну: расстояния впереди, м.
const CORNER_SCAN := [8.0, 16.0, 24.0, 32.0, 40.0, 50.0]
## Длина участка, по которому оценивается кривизна, м.
const CORNER_SPAN := 12.0
const STUCK_SPEED := 1.5
const STUCK_TIME := 1.2
const REVERSE_TIME := 0.8
const RESPAWN_STUCK_TIME := 6.0
## Полуширина машины, м.
const CAR_HALF_WIDTH := 1.0
## Скорость перестроения между полосами, м/с.
const LANE_CHANGE_SPEED := 8.0
## Объект предмета (банан, бумеранг — 5 м) задевает машину ближе этого, м.
const ITEM_OBJECT_REACH := 4.0
## Вантуз применяется, если скорость выше допустимой на столько, м/с.
const STOP_ITEM_EXCESS := 10.0

var _progress: TrackProgress
var _stuck_time: float = 0.0
var _total_stuck_time: float = 0.0
var _reverse_left: float = 0.0
var _lane: float = 0.0
var _item_hold: float = 0.0
## Препятствия вдоль трассы: {offset, lateral, half_width, hazard}.
var _obstacles: Array[Dictionary] = []
var _scanned: bool = false
var _item_held: float = 0.0


func read_input(out: CarInput) -> void:
	out.clear()
	if car == null or track == null or track.length <= 0.0:
		return
	if _progress == null:
		_progress = TrackProgress.new(track)
		_lane = lane_offset
	if not _scanned:
		_scan_obstacles()
	var delta := get_physics_process_delta_time()
	var offset := _progress.update(car.global_position)
	var speed := car.forward_speed

	# Полоса: предпочтительная, если свободна; иначе ближайшая свободная.
	var wanted := _choose_lane(offset)
	_lane = move_toward(_lane, wanted, LANE_CHANGE_SPEED * delta)

	# Руль: к точке впереди на своей полосе.
	var ahead := look_ahead_base + absf(speed) * look_ahead_per_speed
	var to_target := track.get_road_point_ahead(offset, ahead, _lane) - car.global_position
	to_target.y = 0.0
	var forward := car.get_flat_forward()
	if to_target.length_squared() > 0.01:
		# Угол > 0 — цель левее носа, значит руль влево (отрицательный).
		var angle := forward.signed_angle_to(to_target.normalized(), Vector3.UP)
		out.steer = clampf(-angle * steer_gain, -1.0, 1.0)

	# Газ: держим допустимую скорость с учётом поворотов впереди.
	var desired := _desired_speed(offset)
	if speed < desired:
		out.throttle = 1.0
	elif speed > desired + 3.0:
		out.throttle = -1.0

	out.parry_pressed = _hazard_just_ahead(offset, speed)
	out.item_pressed = _want_item(offset, speed, desired, delta)
	# Помидор автопилот бросает средне: держит кнопку полсекунды.
	_item_hold = 0.5 if out.item_pressed else maxf(_item_hold - delta, 0.0)
	out.item_held = _item_hold > 0.0
	_handle_stuck(out, delta, speed)


## Когда применить предмет из слота (подержав его item_hold_time):
## вантуз — как тормоз, если перед поворотом надо сбросить много скорости;
## нитро и рывок — когда впереди прямая и полоса свободна; остальное — сразу.
func _want_item(offset: float, speed: float, desired: float, delta: float) -> bool:
	var items := CarItems.of(car)
	if items == null or items.current == null or not car.controls_enabled:
		_item_held = 0.0
		return false
	_item_held += delta
	if _item_held < item_hold_time:
		return false
	match items.current.id:
		&"stop":
			return speed > desired + STOP_ITEM_EXCESS
		&"nitro", &"dash":
			return desired >= car.get_max_speed() * skill - 0.1 and _free_distance(offset, _lane) >= obstacle_scan
	return true


func _desired_speed(offset: float) -> float:
	var limit := car.get_max_speed() * skill
	# Скорость поворота машины на ходу (рад/с).
	var turn_rate := car.get_turn_rate(car.max_speed)
	for distance in CORNER_SCAN:
		var bend := track.get_direction_at(offset + distance).angle_to(
				track.get_direction_at(offset + distance + CORNER_SPAN))
		if bend < 0.02:
			continue
		var radius := CORNER_SPAN / bend
		var corner_speed := maxf(turn_rate * radius * corner_margin, min_corner_speed)
		# Успеть затормозить до поворота: v² = v_поворота² + 2·a·s.
		var reachable := sqrt(corner_speed * corner_speed + 2.0 * car.deceleration * 0.6 * distance)
		limit = minf(limit, reachable)
	return limit


## Препятствия из узла «Props» трассы: твёрдые (StaticBody3D) и парируемые (ParryHazard).
func _scan_obstacles() -> void:
	_scanned = true
	var props := track.get_node_or_null(^"Props")
	if props == null:
		return
	for child in props.get_children():
		var node := child as Node3D
		if node == null:
			continue
		var hazard := node is ParryHazard
		if not hazard and not node is StaticBody3D:
			continue
		# По трамплинам ездят, а не объезжают их.
		if node.is_in_group(&"ramps"):
			continue
		var result := track.project(node.global_position)
		var offset := float(result["offset"])
		var right := track.get_direction_at(offset).cross(Vector3.UP).normalized()
		var lateral := (node.global_position - track.get_point_at(offset)).dot(right)
		_obstacles.append({
			"offset": offset,
			"lateral": lateral,
			"half_width": _half_width(node),
			"hazard": hazard,
		})


## Полуразмер препятствия поперёк трассы (по коллизии, с запасом на поворот).
func _half_width(node: Node3D) -> float:
	var half := 1.0
	for child in node.get_children():
		var shape := child as CollisionShape3D
		if shape != null and shape.shape is BoxShape3D:
			var size := (shape.shape as BoxShape3D).size * node.scale
			half = maxf(half, maxf(size.x, size.z) * 0.5)
	return half


## Полоса с самым длинным свободным участком впереди (бочки часто стоят «слаломом»,
## и все полосы сразу свободными не бывают). Предпочтительная — если свободна целиком.
func _choose_lane(offset: float) -> float:
	# Ширина дороги — самая узкая в ближайших метрах впереди (участки разной ширины).
	var half: float = track.road_half_width_at(offset)
	for ahead in [5.0, 10.0, 15.0, 20.0]:
		half = minf(half, track.road_half_width_at(offset + ahead))
	var max_lane := maxf(half - CAR_HALF_WIDTH - 0.3, 0.0)
	var preferred := clampf(lane_offset, -max_lane, max_lane)
	if _free_distance(offset, preferred) >= obstacle_scan:
		return preferred
	var best := _lane
	var best_score := -INF
	var lane := -max_lane
	while lane <= max_lane + 0.01:
		var score := _free_distance(offset, lane) - absf(lane - _lane) * 0.5
		if score > best_score:
			best_score = score
			best = lane
		lane += 0.5
	return best


## Сколько метров вперёд полоса свободна от твёрдых препятствий (не больше obstacle_scan).
func _free_distance(offset: float, lane: float) -> float:
	var free := obstacle_scan
	for obstacle in _obstacles:
		if obstacle["hazard"]:
			continue
		var ahead := fposmod(float(obstacle["offset"]) - offset, track.length)
		if ahead > obstacle_scan:
			continue
		if absf(lane - float(obstacle["lateral"])) < float(obstacle["half_width"]) + CAR_HALF_WIDTH + obstacle_clearance:
			free = minf(free, ahead)
	return free


## Парируемая опасность на нашей полосе вот-вот: пора жать парирование.
func _hazard_just_ahead(offset: float, speed: float) -> bool:
	for obstacle in _obstacles:
		if not obstacle["hazard"]:
			continue
		var ahead := fposmod(float(obstacle["offset"]) - offset, track.length) - 2.0
		if ahead < 0.0 or ahead > maxf(speed, 1.0) * parry_lead:
			continue
		if absf(_lane - float(obstacle["lateral"])) < float(obstacle["half_width"]) + CAR_HALF_WIDTH:
			return true
	# Чужие парируемые объекты предметов (банан, бумеранг) прямо по курсу.
	var forward := car.get_flat_forward()
	var right := forward.cross(Vector3.UP)
	for node in car.get_tree().get_nodes_in_group(ItemObject.PARRY_ITEMS_GROUP):
		# Объекты предметов (кроме своих) и летящие опасности карт (снежки турелей).
		var item_object := node as ItemObject
		if (item_object != null and item_object.owner_car == car) or not node is Node3D:
			continue
		var to_object := (node as Node3D).global_position - car.global_position
		var ahead := to_object.dot(forward)
		if ahead > 0.0 and ahead < maxf(speed, 1.0) * parry_lead + ITEM_OBJECT_REACH \
				and absf(to_object.dot(right)) < ITEM_OBJECT_REACH:
			return true
	return false


func _handle_stuck(out: CarInput, delta: float, speed: float) -> void:
	if not car.controls_enabled:
		_stuck_time = 0.0
		return
	if _reverse_left > 0.0:
		_reverse_left -= delta
		out.throttle = -1.0
		out.steer = -out.steer
		return
	if absf(speed) < STUCK_SPEED:
		_stuck_time += delta
		_total_stuck_time += delta
	else:
		_stuck_time = 0.0
		_total_stuck_time = maxf(_total_stuck_time - delta, 0.0)
	if _total_stuck_time > RESPAWN_STUCK_TIME:
		_total_stuck_time = 0.0
		_stuck_time = 0.0
		car.respawn()
		_progress.reset()
	elif _stuck_time > STUCK_TIME:
		_stuck_time = 0.0
		_reverse_left = REVERSE_TIME
