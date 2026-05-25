extends Control

class VehicleOptionData:
	var style_id := 1
	var button_center: Control
	var button: TextureButton
	var animation_player: AnimationPlayer
	var base_rotation := 0.0
	var base_scale := Vector2.ONE
	var frame_textures: Array = []


const VEHICLE_BUTTON_TEXTURE_SETS := [
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


signal confirm_requested(style_id: int)

@onready var menu_buttons_grid: GridContainer = $MenuButtonsContainer/MenuButtonsGrid
@onready var confirm_button: TextureButton = $ConfirmButton

@export var selected_frame_interval := 0.2

var _vehicle_options: Array = []
var _selected_style_id := 0
var _selected_frame_elapsed := 0.0
var _selected_frame_index := 0


func _ready() -> void:
	_vehicle_options = _collect_vehicle_options()
	for option in _vehicle_options:
		option.button.pressed.connect(_on_vehicle_pressed.bind(option.style_id))

	confirm_button.pressed.connect(_on_confirm_pressed)
	set_selected_style(_selected_style_id)


func _process(delta: float) -> void:
	if _selected_style_id <= 0 or _vehicle_options.is_empty():
		return

	_selected_frame_elapsed += delta
	if _selected_frame_elapsed < selected_frame_interval:
		return

	var frame_steps := int(floor(_selected_frame_elapsed / selected_frame_interval))
	_selected_frame_elapsed = fmod(_selected_frame_elapsed, selected_frame_interval)
	_selected_frame_index = (_selected_frame_index + frame_steps) % 2
	_apply_selected_option_frame()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			_handle_pointer_press(mouse_event.position)
		return

	if event is InputEventScreenTouch:
		var touch_event: InputEventScreenTouch = event as InputEventScreenTouch
		if touch_event.pressed:
			_handle_pointer_press(touch_event.position)


func set_selected_style(style_id: int) -> void:
	var previous_selected_style_id := _selected_style_id
	if _vehicle_options.is_empty():
		_selected_style_id = maxi(style_id, 0)
		_update_confirm_button_visibility()
		return

	if style_id <= 0:
		_selected_style_id = 0
	else:
		_selected_style_id = clampi(style_id, 1, _vehicle_options.size())

	for option in _vehicle_options:
		var is_selected: bool = option.style_id == _selected_style_id
		option.button.set_pressed_no_signal(is_selected)
		_set_option_active(option, is_selected)

	if previous_selected_style_id != _selected_style_id:
		_selected_frame_elapsed = 0.0
		_selected_frame_index = 0

	_apply_selected_option_frame()

	_update_confirm_button_visibility()


func _collect_vehicle_options() -> Array:
	var options: Array = []
	var style_id := 1
	for child in menu_buttons_grid.get_children():
		var option_root := child as Control
		if option_root == null:
			continue

		var option := VehicleOptionData.new()
		option.style_id = style_id
		option.button_center = option_root.get_node("ButtonCenter") as Control
		option.button = option_root.get_node("ButtonCenter/Button") as TextureButton
		option.animation_player = option_root.get_node("FloatingPlayer") as AnimationPlayer
		option.base_rotation = option.button_center.rotation
		option.base_scale = option.button_center.scale
		option.frame_textures = VEHICLE_BUTTON_TEXTURE_SETS[clampi(style_id - 1, 0, VEHICLE_BUTTON_TEXTURE_SETS.size() - 1)]
		_apply_option_frame(option, 0)
		options.append(option)
		style_id += 1

	return options


func _on_vehicle_pressed(style_id: int) -> void:
	set_selected_style(style_id)


func _on_confirm_pressed() -> void:
	if _selected_style_id <= 0:
		return

	confirm_requested.emit(_selected_style_id)


func _set_option_active(option: VehicleOptionData, is_selected: bool) -> void:
	if is_selected:
		option.animation_player.play("selected")
		_apply_option_frame(option, _selected_frame_index)
		return

	option.animation_player.stop()
	option.button_center.rotation = option.base_rotation
	option.button_center.scale = option.base_scale
	_apply_option_frame(option, 0)


func _handle_pointer_press(pointer_position: Vector2) -> void:
	if _is_pointer_over_vehicle_button(pointer_position):
		return

	if confirm_button.visible and confirm_button.get_global_rect().has_point(pointer_position):
		return

	set_selected_style(0)


func _is_pointer_over_vehicle_button(pointer_position: Vector2) -> bool:
	for option in _vehicle_options:
		if option.button.get_global_rect().has_point(pointer_position):
			return true

	return false


func _update_confirm_button_visibility() -> void:
	var has_selection: bool = _selected_style_id > 0
	confirm_button.visible = has_selection
	confirm_button.disabled = not has_selection


func _apply_selected_option_frame() -> void:
	var selected_option: VehicleOptionData = _get_selected_option()
	if selected_option == null:
		return

	_apply_option_frame(selected_option, _selected_frame_index)


func _get_selected_option() -> VehicleOptionData:
	if _selected_style_id <= 0:
		return null

	for option in _vehicle_options:
		if option.style_id == _selected_style_id:
			return option

	return null


func _apply_option_frame(option: VehicleOptionData, frame_index: int) -> void:
	if option == null or option.frame_textures.is_empty():
		return

	var safe_index := clampi(frame_index, 0, option.frame_textures.size() - 1)
	var frame_texture: Texture2D = option.frame_textures[safe_index]
	option.button.texture_normal = frame_texture
	option.button.texture_pressed = frame_texture
