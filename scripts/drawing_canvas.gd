extends Control

@export var brush_color := Color(0.31, 0.16, 0.08, 1.0)
@export_range(1.0, 24.0, 1.0) var brush_width := 8.0

const MASK_ALPHA_THRESHOLD := 0.01

var _strokes: Array = []
var _current_stroke := PackedVector2Array()
var _is_drawing := false
var _mask_texture_rect: TextureRect = null
var _mask_image: Image = null


func _ready() -> void:
	_mask_texture_rect = get_parent().get_node_or_null("Canvas") as TextureRect
	_refresh_mask_image()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin_stroke(event.position)
		else:
			_end_stroke()
		accept_event()
		return

	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		_append_point(event.position)
		accept_event()
		return

	if event is InputEventScreenTouch:
		if event.pressed:
			_begin_stroke(event.position)
		else:
			_end_stroke()
		accept_event()
		return

	if event is InputEventScreenDrag:
		_append_point(event.position)
		accept_event()


func _draw() -> void:
	for stroke in _strokes:
		_draw_stroke(stroke)

	if _current_stroke.size() > 0:
		_draw_stroke(_current_stroke)


func clear_strokes() -> void:
	_strokes.clear()
	_current_stroke = PackedVector2Array()
	_is_drawing = false
	queue_redraw()


func has_content() -> bool:
	return not _strokes.is_empty() or _current_stroke.size() > 0


func build_texture() -> Texture2D:
	var image_width: int = maxi(1, int(round(size.x)))
	var image_height: int = maxi(1, int(round(size.y)))
	var image := Image.create(image_width, image_height, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))

	for stroke in _strokes:
		_rasterize_stroke(image, stroke)

	if _current_stroke.size() > 0:
		_rasterize_stroke(image, _current_stroke)

	return ImageTexture.create_from_image(image)


func _begin_stroke(point: Vector2) -> void:
	var clamped_point := _clamp_point(point)
	if not _is_drawable_point(clamped_point):
		_is_drawing = false
		_current_stroke = PackedVector2Array()
		queue_redraw()
		return

	_start_stroke(clamped_point)
	queue_redraw()


func _append_point(point: Vector2) -> void:
	var clamped_point: Vector2 = _clamp_point(point)
	if not _is_drawable_point(clamped_point):
		_end_stroke()
		return

	if not _is_drawing:
		_start_stroke(clamped_point)
		queue_redraw()
		return

	var last_index: int = _current_stroke.size() - 1
	if last_index >= 0 and _current_stroke[last_index].distance_to(clamped_point) < 1.0:
		return

	_current_stroke.append(clamped_point)
	queue_redraw()


func _end_stroke() -> void:
	if not _is_drawing:
		return

	_is_drawing = false
	if _current_stroke.size() > 1:
		_strokes.append(_current_stroke)

	_current_stroke = PackedVector2Array()
	queue_redraw()


func _draw_stroke(stroke: PackedVector2Array) -> void:
	if stroke.size() == 1:
		draw_circle(stroke[0], brush_width * 0.5, brush_color)
		return

	if stroke.size() > 1:
		draw_polyline(stroke, brush_color, brush_width, true)


func _rasterize_stroke(image: Image, stroke: PackedVector2Array) -> void:
	if stroke.size() == 0:
		return

	var radius: int = maxi(1, int(round(brush_width * 0.5)))
	if stroke.size() == 1:
		_stamp_circle(image, stroke[0], radius)
		return

	for index in range(stroke.size() - 1):
		_rasterize_segment(image, stroke[index], stroke[index + 1], radius)


func _rasterize_segment(image: Image, from_point: Vector2, to_point: Vector2, radius: int) -> void:
	var distance: float = maxf(1.0, from_point.distance_to(to_point))
	var steps: int = int(ceil(distance))
	for step in range(steps + 1):
		var point: Vector2 = from_point.lerp(to_point, float(step) / float(steps))
		_stamp_circle(image, point, radius)


func _stamp_circle(image: Image, center: Vector2, radius: int) -> void:
	var min_x: int = maxi(0, int(floor(center.x)) - radius)
	var max_x: int = mini(image.get_width() - 1, int(ceil(center.x)) + radius)
	var min_y: int = maxi(0, int(floor(center.y)) - radius)
	var max_y: int = mini(image.get_height() - 1, int(ceil(center.y)) + radius)
	var radius_squared: float = float(radius * radius)

	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var pixel_center := Vector2(x + 0.5, y + 0.5)
			if pixel_center.distance_squared_to(center) <= radius_squared and _is_drawable_point(pixel_center):
				image.set_pixel(x, y, brush_color)


func _start_stroke(point: Vector2) -> void:
	_is_drawing = true
	_current_stroke = PackedVector2Array([point, point])


func _refresh_mask_image() -> void:
	if _mask_texture_rect == null or _mask_texture_rect.texture == null:
		_mask_image = null
		return

	_mask_image = _mask_texture_rect.texture.get_image()
	if _mask_image == null:
		return

	_mask_image.convert(Image.FORMAT_RGBA8)


func _is_drawable_point(point: Vector2) -> bool:
	if _mask_image == null or _mask_texture_rect == null:
		return true

	var canvas_local: Vector2 = point + position - _mask_texture_rect.position
	var display_rect: Rect2 = _get_mask_display_rect()
	if not display_rect.has_point(canvas_local):
		return false

	var uv: Vector2 = (canvas_local - display_rect.position) / display_rect.size
	var pixel_x: int = mini(_mask_image.get_width() - 1, maxi(0, int(floor(uv.x * _mask_image.get_width()))))
	var pixel_y: int = mini(_mask_image.get_height() - 1, maxi(0, int(floor(uv.y * _mask_image.get_height()))))
	return _mask_image.get_pixel(pixel_x, pixel_y).a > MASK_ALPHA_THRESHOLD


func _get_mask_display_rect() -> Rect2:
	if _mask_texture_rect == null or _mask_texture_rect.texture == null:
		return Rect2(Vector2.ZERO, size)

	var texture_size: Vector2 = _mask_texture_rect.texture.get_size()
	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return Rect2(Vector2.ZERO, _mask_texture_rect.size)

	var scale_factor: float = minf(
		_mask_texture_rect.size.x / texture_size.x,
		_mask_texture_rect.size.y / texture_size.y
	)
	var displayed_size: Vector2 = texture_size * scale_factor
	var displayed_position: Vector2 = (_mask_texture_rect.size - displayed_size) * 0.5
	return Rect2(displayed_position, displayed_size)


func _clamp_point(point: Vector2) -> Vector2:
	return Vector2(
		clamp(point.x, 0.0, size.x),
		clamp(point.y, 0.0, size.y)
	)