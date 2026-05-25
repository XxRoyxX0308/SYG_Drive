extends Control

signal confirm_requested(drawing_texture: Texture2D)

@onready var drawing_surface = $DrawingCanvas/CanvasSurface
@onready var clear_button: TextureButton = $ActionButtons/ClearButton
@onready var confirm_button: TextureButton = $ActionButtons/ConfirmButton


func _ready() -> void:
	clear_button.pressed.connect(_on_clear_pressed)
	confirm_button.pressed.connect(_on_confirm_pressed)


func reset_view() -> void:
	drawing_surface.clear_strokes()


func _on_clear_pressed() -> void:
	drawing_surface.clear_strokes()


func _on_confirm_pressed() -> void:
	confirm_requested.emit(drawing_surface.build_texture())
