extends Control

signal confirm_requested(drawing_texture: Texture2D)

@onready var drawing_surface = $DrawingCanvas/CanvasSurface
@onready var clear_button: TextureButton = $ActionButtons/ClearButton
@onready var confirm_button: TextureButton = $ActionButtons/ConfirmButton
@onready var vehicle: TextureRect = $Figurine/Vehicle


func _ready() -> void:
	clear_button.pressed.connect(_on_clear_pressed)
	confirm_button.pressed.connect(_on_confirm_pressed)

func set_vehicle_texture(texture: Texture2D) -> void:
	if vehicle:
		vehicle.texture = texture

func reset_view() -> void:
	drawing_surface.clear_strokes()
	set_vehicle_texture(null)


func _on_clear_pressed() -> void:
	drawing_surface.clear_strokes()


func _on_confirm_pressed() -> void:
	confirm_requested.emit(drawing_surface.build_texture())
