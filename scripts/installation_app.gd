extends Control

enum AppState {
	MAIN_MENU,
	DRAWING,
	COMPLETE,
}

const IMGBB_UPLOAD_URL := "https://api.imgbb.com/1/upload"
const IMGBB_API_KEY_PATH := "res://config/imgbb_api_key.txt"

const LEFT_SCENES := {
	AppState.MAIN_MENU: preload("res://scenes/left_main_menu.tscn"),
	AppState.DRAWING: preload("res://scenes/left_drawing.tscn"),
	AppState.COMPLETE: preload("res://scenes/left_completion_share.tscn"),
}

@onready var left_viewport: SubViewport = $LeftScreenHost/LeftScreenViewport
@onready var right_display = $RightScreenHost/RightScreenViewport/RightDisplayShared

var current_state: int = AppState.MAIN_MENU
var current_left_scene = null
var selected_style_id := 0
var selected_vehicle_texture: Texture2D = null
var latest_drawing_texture: Texture2D = null
var latest_uploaded_url := ""
var _upload_request: HTTPRequest = null
var _upload_in_flight := false


func _ready() -> void:
	_upload_request = HTTPRequest.new()
	add_child(_upload_request)
	_upload_request.request_completed.connect(_on_upload_request_completed)
	_configure_presentation_window()
	_show_state(AppState.MAIN_MENU)


func _show_state(next_state: int) -> void:
	current_state = next_state
	if is_instance_valid(current_left_scene):
		left_viewport.remove_child(current_left_scene)
		current_left_scene.queue_free()
		current_left_scene = null

	current_left_scene = LEFT_SCENES[next_state].instantiate()
	left_viewport.add_child(current_left_scene)
	_wire_left_scene()


func _wire_left_scene() -> void:
	match current_state:
		AppState.MAIN_MENU:
			current_left_scene.confirm_requested.connect(_on_main_menu_confirm)
			current_left_scene.set_selected_style(selected_style_id)
		AppState.DRAWING:
			current_left_scene.confirm_requested.connect(_on_drawing_confirm)
			current_left_scene.reset_view()
			current_left_scene.set_vehicle_texture(selected_vehicle_texture)
		AppState.COMPLETE:
			current_left_scene.home_requested.connect(_on_home_requested)
			current_left_scene.screenshot_requested.connect(_on_screenshot_requested)
			current_left_scene.show_qr_url(latest_uploaded_url)
			_set_capture_loading_on_complete_scene(_upload_in_flight)


func _on_main_menu_confirm(style_id: int) -> void:
	if style_id <= 0:
		return

	selected_style_id = style_id
	selected_vehicle_texture = right_display._get_primary_vehicle_texture(selected_style_id)
	_show_state(AppState.DRAWING)


func _on_drawing_confirm(drawing_texture: Texture2D) -> void:
	latest_drawing_texture = drawing_texture
	right_display.spawn_vehicle(drawing_texture, selected_style_id)
	_show_state(AppState.COMPLETE)


func _on_screenshot_requested() -> void:
	if _upload_in_flight:
		push_warning("Screenshot upload already in progress.")
		_set_capture_loading_on_complete_scene(true)
		return

	_set_capture_loading_on_complete_scene(true)

	var screenshot_image: Image = right_display.capture_view_image()
	if screenshot_image == null:
		push_warning("Failed to capture right screen screenshot.")
		_set_capture_loading_on_complete_scene(false)
		return

	var screenshot_path := _save_screenshot(screenshot_image)
	var api_key := _load_imgbb_api_key()
	if api_key.is_empty():
		push_warning("imgbb API key is missing.")
		_set_capture_loading_on_complete_scene(false)
		return

	var upload_payload := _build_imgbb_payload(screenshot_path, screenshot_path.get_file().get_basename(), api_key)
	if upload_payload.is_empty():
		push_warning("Failed to build screenshot upload payload.")
		_set_capture_loading_on_complete_scene(false)
		return

	latest_uploaded_url = ""
	if is_instance_valid(current_left_scene):
		current_left_scene.show_qr_url("")

	_upload_in_flight = true
	var request_error: Error = _upload_request.request(
		IMGBB_UPLOAD_URL,
		PackedStringArray(["Content-Type: application/x-www-form-urlencoded"]),
		HTTPClient.METHOD_POST,
		upload_payload
	)
	if request_error != OK:
		_upload_in_flight = false
		_set_capture_loading_on_complete_scene(false)
		push_warning("Failed to start screenshot upload request: %s" % error_string(request_error))


func _on_home_requested() -> void:
	_reset_application()
	_show_state(AppState.MAIN_MENU)


func _reset_application() -> void:
	selected_style_id = 0
	selected_vehicle_texture = null
	latest_drawing_texture = null
	latest_uploaded_url = ""


func _save_screenshot(image: Image) -> String:
	var captures_dir := ProjectSettings.globalize_path("user://captures")
	var dir_result := DirAccess.make_dir_recursive_absolute(captures_dir)
	if dir_result != OK:
		push_warning("Failed to prepare screenshot directory: %s" % captures_dir)

	var screenshot_path := "%s/right_screen_%s.png" % [captures_dir, int(Time.get_unix_time_from_system())]
	var save_result := image.save_png(screenshot_path)
	if save_result != OK:
		push_warning("Failed to save screenshot to %s" % screenshot_path)

	return screenshot_path


func _configure_presentation_window() -> void:
	if DisplayServer.get_name() == "headless":
		return

	var desktop_rect: Rect2i = _get_virtual_desktop_rect()
	if desktop_rect.size.x <= 0 or desktop_rect.size.y <= 0:
		return

	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_position(desktop_rect.position)
	DisplayServer.window_set_size(desktop_rect.size)


func _get_virtual_desktop_rect() -> Rect2i:
	var screen_count: int = DisplayServer.get_screen_count()
	if screen_count <= 0:
		return Rect2i(Vector2i.ZERO, Vector2i.ZERO)

	var top_left: Vector2i = DisplayServer.screen_get_position(0)
	var bottom_right: Vector2i = top_left + DisplayServer.screen_get_size(0)
	for screen_index in range(1, screen_count):
		var screen_position: Vector2i = DisplayServer.screen_get_position(screen_index)
		var screen_bottom_right: Vector2i = screen_position + DisplayServer.screen_get_size(screen_index)
		top_left.x = mini(top_left.x, screen_position.x)
		top_left.y = mini(top_left.y, screen_position.y)
		bottom_right.x = maxi(bottom_right.x, screen_bottom_right.x)
		bottom_right.y = maxi(bottom_right.y, screen_bottom_right.y)

	return Rect2i(top_left, bottom_right - top_left)


func _load_imgbb_api_key() -> String:
	var environment_api_key: String = OS.get_environment("IMGBB_API_KEY").strip_edges()
	if not environment_api_key.is_empty():
		return environment_api_key

	if not FileAccess.file_exists(IMGBB_API_KEY_PATH):
		return ""

	var file: FileAccess = FileAccess.open(IMGBB_API_KEY_PATH, FileAccess.READ)
	if file == null:
		return ""

	return file.get_as_text().strip_edges()


func _build_imgbb_payload(screenshot_path: String, image_name: String, api_key: String) -> String:
	var image_bytes: PackedByteArray = FileAccess.get_file_as_bytes(screenshot_path)
	if image_bytes.is_empty():
		return ""

	var encoded_image: String = Marshalls.raw_to_base64(image_bytes)
	return "key=%s&name=%s&image=%s" % [
		api_key.uri_encode(),
		image_name.uri_encode(),
		encoded_image.uri_encode(),
	]


func _on_upload_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_upload_in_flight = false
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		push_warning("Screenshot upload failed with result %s and response code %s." % [result, response_code])
		_set_capture_loading_on_complete_scene(false)
		return

	var response_text: String = body.get_string_from_utf8()
	var response_data: Variant = JSON.parse_string(response_text)
	if typeof(response_data) != TYPE_DICTIONARY:
		push_warning("Unexpected imgbb response: %s" % response_text)
		_set_capture_loading_on_complete_scene(false)
		return

	var response_dictionary: Dictionary = response_data
	if not bool(response_dictionary.get("success", false)):
		push_warning("imgbb rejected the screenshot upload: %s" % response_text)
		_set_capture_loading_on_complete_scene(false)
		return

	var data: Dictionary = response_dictionary.get("data", {})
	latest_uploaded_url = str(data.get("url_viewer", data.get("url", "")))
	if latest_uploaded_url.is_empty():
		push_warning("imgbb response did not contain a usable URL.")
		_set_capture_loading_on_complete_scene(false)
		return

	if current_state == AppState.COMPLETE and is_instance_valid(current_left_scene):
		current_left_scene.show_qr_url(latest_uploaded_url)


func _set_capture_loading_on_complete_scene(is_loading: bool) -> void:
	if current_state != AppState.COMPLETE or not is_instance_valid(current_left_scene):
		return

	if current_left_scene.has_method("set_capture_loading"):
		current_left_scene.set_capture_loading(is_loading)
