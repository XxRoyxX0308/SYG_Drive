extends Control

class PendingUserVehicleRequest:
	var style_id := 1
	var drawing_texture: Texture2D = null


class VehicleEntry:
	var root: Node2D
	var sprite: AnimatedSprite2D
	var dialog_box: Sprite2D
	var drawing_overlay: Sprite2D = null
	var style_id := 1
	var lane_index := 0
	var next_lane_index := 0
	var progress_distance := 0.0
	var drawing_texture: Texture2D = null
	var is_user_vehicle := false
	var is_active := false
	var refresh_serial := 0


const TOP_LANE := 0
const BOTTOM_LANE := 1
const DIALOG_BOX_TEXTURE := preload("res://assets/canvas/dialog_box.png")
const VEHICLE_TEXTURE_SETS := [
	[
		preload("res://assets/vehicles/vehicle_A_01.png"),
		preload("res://assets/vehicles/vehicle_A_02.png"),
	],
	[
		preload("res://assets/vehicles/vehicle_B_01.png"),
		preload("res://assets/vehicles/vehicle_B_02.png"),
	],
	[
		preload("res://assets/vehicles/vehicle_C_01.png"),
		preload("res://assets/vehicles/vehicle_C_02.png"),
	],
	[
		preload("res://assets/vehicles/vehicle_D_01.png"),
		preload("res://assets/vehicles/vehicle_D_02.png"),
	],
	[
		preload("res://assets/vehicles/vehicle_E_01.png"),
		preload("res://assets/vehicles/vehicle_E_02.png"),
	],
	[
		preload("res://assets/vehicles/vehicle_F_01.png"),
		preload("res://assets/vehicles/vehicle_F_02.png"),
	],
	[
		preload("res://assets/vehicles/vehicle_G_01.png"),
		preload("res://assets/vehicles/vehicle_G_02.png"),
	],
	[
		preload("res://assets/vehicles/vehicle_H_01.png"),
		preload("res://assets/vehicles/vehicle_H_02.png"),
	],
	[
		preload("res://assets/vehicles/vehicle_I_01.png"),
		preload("res://assets/vehicles/vehicle_I_02.png"),
	],
]

@export var top_lane_y := 356.0
@export var bottom_lane_y := 764.0
@export var auto_spawn_interval := 1.5
@export var vehicle_speed := 210.0
@export var vehicle_scale := 1.2
@export var spawn_margin := 250.0
@export var despawn_margin := 250.0
@export var dialog_box_scale := 0.9
@export var dialog_box_vertical_offset := 10.0
@export var drawing_width_ratio := 0.98
@export var drawing_height_ratio := 0.98
@export var drawing_vertical_offset := 0.0
@export var wheel_animation_fps := 6.0

@onready var top_lane: Node2D = $TrafficVehicles/TopLane
@onready var bottom_lane: Node2D = $TrafficVehicles/BottomLane

var _lane_containers: Array[Node2D] = []
var _vehicle_entries: Array = []
var _vehicle_frames: Array[SpriteFrames] = []
var _pending_user_requests: Array = []
var _refresh_serial_counter := 0
var _spawn_counter := 0
var _launch_cursor := 0
var _launch_count := 0
var _time_until_next_departure := 0.0


func _ready() -> void:
	_lane_containers = [top_lane, bottom_lane]
	_vehicle_frames = _build_vehicle_frames()
	_build_loop_entries()


func _process(delta: float) -> void:
	_update_active_entries(delta)
	_advance_launch_schedule(delta)


func spawn_vehicle(drawing_texture: Texture2D, style_id: int) -> void:
	if style_id <= 0:
		return

	var request := PendingUserVehicleRequest.new()
	request.style_id = clampi(style_id, 1, VEHICLE_TEXTURE_SETS.size())
	request.drawing_texture = drawing_texture
	_pending_user_requests.append(request)
	_apply_waiting_replacements()


func capture_view_image() -> Image:
	return get_viewport().get_texture().get_image()


func reset_display() -> void:
	_clear_vehicle_entries()
	_vehicle_entries.clear()
	_pending_user_requests.clear()
	_refresh_serial_counter = 0
	_spawn_counter = 0
	_launch_cursor = 0
	_launch_count = 0
	_time_until_next_departure = 0.0
	_build_loop_entries()


func _build_loop_entries() -> void:
	var lane_travel_time: float = _get_lane_travel_time()
	for entry_index in range(VEHICLE_TEXTURE_SETS.size()):
		var entry := VehicleEntry.new()
		entry.style_id = entry_index + 1
		entry.refresh_serial = _refresh_serial_counter
		_refresh_serial_counter += 1

		entry.root = Node2D.new()
		entry.root.name = "Vehicle_%02d" % (_spawn_counter + 1)
		entry.root.z_index = 100 + _spawn_counter
		entry.root.scale = Vector2.ONE * vehicle_scale
		entry.sprite = AnimatedSprite2D.new()
		entry.root.add_child(entry.sprite)
		entry.dialog_box = Sprite2D.new()
		entry.root.add_child(entry.dialog_box)
		_spawn_counter += 1

		_refresh_vehicle_entry(entry)
		_vehicle_entries.append(entry)

	for entry_index in range(_vehicle_entries.size()):
		var entry: VehicleEntry = _vehicle_entries[entry_index]
		var age_steps := 0 if entry_index == 0 else _vehicle_entries.size() - entry_index
		var last_lane_index: int = _get_lane_for_launch_order(age_steps)
		_initialize_entry_runtime(entry, last_lane_index, float(age_steps) * auto_spawn_interval, lane_travel_time)

	if not _vehicle_entries.is_empty():
		_launch_cursor = 1 % _vehicle_entries.size()
		_launch_count = 1
		_time_until_next_departure = auto_spawn_interval


func _refresh_vehicle_entry(entry: VehicleEntry) -> void:
	var base_texture: Texture2D = _get_primary_vehicle_texture(entry.style_id)
	var base_size := base_texture.get_size() if base_texture != null else Vector2.ZERO

	entry.root.scale = Vector2.ONE * vehicle_scale
	entry.sprite.centered = false
	entry.sprite.sprite_frames = _vehicle_frames[entry.style_id - 1]
	entry.sprite.animation = &"drive"
	entry.sprite.position = Vector2(-base_size.x * 0.5, -base_size.y)
	entry.sprite.flip_h = entry.lane_index == TOP_LANE
	entry.sprite.play()

	if entry.dialog_box == null:
		entry.dialog_box = Sprite2D.new()
		entry.root.add_child(entry.dialog_box)

	entry.dialog_box.texture = DIALOG_BOX_TEXTURE
	entry.dialog_box.centered = true
	entry.dialog_box.z_index = 1
	entry.dialog_box.scale = Vector2.ONE * dialog_box_scale
	entry.dialog_box.position = _get_dialog_box_position(base_size)

	if is_instance_valid(entry.drawing_overlay):
		entry.drawing_overlay.queue_free()
		entry.drawing_overlay = null

	if entry.drawing_texture != null:
		entry.drawing_overlay = _build_drawing_overlay(entry.drawing_texture)
		if entry.drawing_overlay != null:
			entry.dialog_box.add_child(entry.drawing_overlay)


func _initialize_entry_runtime(entry: VehicleEntry, last_lane_index: int, time_since_departure: float, lane_travel_time: float) -> void:
	entry.lane_index = last_lane_index
	entry.next_lane_index = _get_opposite_lane(last_lane_index)

	if time_since_departure < lane_travel_time:
		entry.is_active = true
		entry.progress_distance = vehicle_speed * time_since_departure
		_update_entry_transform(entry)
		return

	_set_entry_waiting(entry)


func _update_entry_transform(entry: VehicleEntry) -> void:
	var x_position: float = _get_base_spawn_x(entry.lane_index)
	if entry.lane_index == TOP_LANE:
		x_position -= entry.progress_distance
	else:
		x_position += entry.progress_distance

	entry.sprite.flip_h = entry.lane_index == TOP_LANE
	_reparent_entry(entry.root, _lane_containers[entry.lane_index])
	entry.root.visible = true
	entry.root.position = Vector2(x_position, _get_lane_y(entry.lane_index))


func _update_active_entries(delta: float) -> void:
	var lane_distance: float = _get_lane_distance()
	for entry_data in _vehicle_entries:
		var entry: VehicleEntry = entry_data
		if not is_instance_valid(entry.root) or not entry.is_active:
			continue

		entry.progress_distance += vehicle_speed * delta
		if entry.progress_distance >= lane_distance:
			_handle_entry_despawn(entry)
			continue

		_update_entry_transform(entry)


func _advance_launch_schedule(delta: float) -> void:
	if _vehicle_entries.is_empty():
		return

	_time_until_next_departure -= delta
	while _time_until_next_departure <= 0.0:
		if not _launch_next_vehicle():
			_time_until_next_departure = 0.0
			return

		_time_until_next_departure += auto_spawn_interval


func _launch_next_vehicle() -> bool:
	if _vehicle_entries.is_empty():
		return false

	var entry: VehicleEntry = _vehicle_entries[_launch_cursor]
	if entry.is_active:
		return false

	entry.lane_index = _get_lane_for_launch_order(_launch_count)
	entry.next_lane_index = _get_opposite_lane(entry.lane_index)
	entry.is_active = true
	entry.progress_distance = 0.0
	_update_entry_transform(entry)

	_launch_cursor = (_launch_cursor + 1) % _vehicle_entries.size()
	_launch_count += 1
	return true


func _handle_entry_despawn(entry: VehicleEntry) -> void:
	_set_entry_waiting(entry)
	_apply_waiting_replacements()


func _set_entry_waiting(entry: VehicleEntry) -> void:
	entry.is_active = false
	entry.progress_distance = 0.0
	entry.root.visible = false
	_reparent_entry(entry.root, _lane_containers[entry.next_lane_index])


func _apply_waiting_replacements() -> void:
	while not _pending_user_requests.is_empty():
		var oldest_entry: VehicleEntry = _get_oldest_entry()
		if oldest_entry == null or oldest_entry.is_active:
			return

		var request: PendingUserVehicleRequest = _pending_user_requests[0]
		_pending_user_requests.remove_at(0)
		_apply_request_to_entry(oldest_entry, request)


func _apply_request_to_entry(entry: VehicleEntry, request: PendingUserVehicleRequest) -> void:
	entry.style_id = request.style_id
	entry.drawing_texture = request.drawing_texture
	entry.is_user_vehicle = request.drawing_texture != null
	entry.refresh_serial = _refresh_serial_counter
	_refresh_serial_counter += 1
	_refresh_vehicle_entry(entry)


func _get_oldest_entry() -> VehicleEntry:
	var oldest_entry: VehicleEntry = null
	for entry_data in _vehicle_entries:
		var entry: VehicleEntry = entry_data
		if oldest_entry == null or entry.refresh_serial < oldest_entry.refresh_serial:
			oldest_entry = entry
	return oldest_entry


func _build_drawing_overlay(drawing_texture: Texture2D) -> Sprite2D:
	if drawing_texture == null:
		return null

	if DIALOG_BOX_TEXTURE == null:
		return null

	var overlay := Sprite2D.new()
	overlay.texture = drawing_texture
	overlay.centered = true
	overlay.z_index = 2
	overlay.modulate = Color(1.0, 1.0, 1.0, 0.95)

	var dialog_box_size := DIALOG_BOX_TEXTURE.get_size()
	var target_size := Vector2(float(dialog_box_size.x) * drawing_width_ratio, float(dialog_box_size.y) * drawing_height_ratio)
	var drawing_size_i := drawing_texture.get_size()
	var drawing_size := Vector2(float(drawing_size_i.x), float(drawing_size_i.y))
	if drawing_size.x > 0.0 and drawing_size.y > 0.0:
		var overlay_scale: float = minf(target_size.x / drawing_size.x, target_size.y / drawing_size.y)
		overlay.scale = Vector2.ONE * maxf(overlay_scale, 0.01)

	overlay.position = Vector2(0.0, drawing_vertical_offset)
	return overlay


func _get_dialog_box_position(base_size: Vector2) -> Vector2:
	if DIALOG_BOX_TEXTURE == null:
		return Vector2(0.0, -base_size.y + dialog_box_vertical_offset)

	var dialog_box_size := DIALOG_BOX_TEXTURE.get_size() * dialog_box_scale
	return Vector2(0.0, -base_size.y - dialog_box_size.y * 0.5 + dialog_box_vertical_offset)


func _build_vehicle_frames() -> Array[SpriteFrames]:
	var sprite_frames_list: Array[SpriteFrames] = []
	for texture_pair in VEHICLE_TEXTURE_SETS:
		var sprite_frames := SpriteFrames.new()
		sprite_frames.add_animation(&"drive")
		sprite_frames.set_animation_loop(&"drive", true)
		sprite_frames.set_animation_speed(&"drive", wheel_animation_fps)
		for frame_texture in texture_pair:
			sprite_frames.add_frame(&"drive", frame_texture)
		sprite_frames_list.append(sprite_frames)

	return sprite_frames_list


func _clear_vehicle_entries() -> void:
	for entry_data in _vehicle_entries:
		var entry: VehicleEntry = entry_data
		if is_instance_valid(entry.root):
			entry.root.queue_free()


func _reparent_entry(root: Node, target_parent: Node) -> void:
	if not is_instance_valid(root):
		return

	var current_parent: Node = root.get_parent()
	if current_parent == target_parent:
		return

	if current_parent != null:
		current_parent.remove_child(root)
	if target_parent != null:
		target_parent.add_child(root)


func _get_primary_vehicle_texture(style_id: int) -> Texture2D:
	var texture_pair: Array = VEHICLE_TEXTURE_SETS[clampi(style_id - 1, 0, VEHICLE_TEXTURE_SETS.size() - 1)]
	return texture_pair[0] as Texture2D


func _get_lane_distance() -> float:
	return _get_finish_x(TOP_LANE) * -1.0 + _get_base_spawn_x(TOP_LANE)


func _get_lane_travel_time() -> float:
	return _get_lane_distance() / maxf(vehicle_speed, 0.001)


func _get_lane_for_launch_order(launch_order: int) -> int:
	return TOP_LANE if posmod(launch_order, 2) == 0 else BOTTOM_LANE


func _get_opposite_lane(lane_index: int) -> int:
	return BOTTOM_LANE if lane_index == TOP_LANE else TOP_LANE


func _get_base_spawn_x(lane_index: int) -> float:
	var view_size: Vector2 = _get_view_size()
	return view_size.x + spawn_margin if lane_index == TOP_LANE else -spawn_margin


func _get_finish_x(lane_index: int) -> float:
	var view_size: Vector2 = _get_view_size()
	return -despawn_margin if lane_index == TOP_LANE else view_size.x + despawn_margin


func _get_lane_y(lane_index: int) -> float:
	return top_lane_y if lane_index == TOP_LANE else bottom_lane_y


func _get_view_size() -> Vector2:
	return Vector2(maxf(size.x, 1920.0), maxf(size.y, 1080.0))