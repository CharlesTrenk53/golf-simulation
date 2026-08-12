extends Control

# POC-17E: Developer Course Builder Prototype
# --------------------------------------------
# Thin visual shell over HoleAuthoringModel. This is intentionally not a polished
# end-user editor; it proves that screen-space authoring actions can create the
# same semantic hole data already consumed by the autonomous golfer.

const HoleAuthoringModel = preload("res://simulation/hole_authoring_model.gd")

enum DrawMode { NONE, FAIRWAY, GREEN, WATER }

@onready var canvas: Control = $Layout/CanvasPanel/Canvas
@onready var mode_label: Label = $Layout/Sidebar/ModeLabel
@onready var summary_label: Label = $Layout/Sidebar/SummaryLabel

var author = HoleAuthoringModel.new()
var draw_mode: DrawMode = DrawMode.NONE
var draft_points: PackedVector2Array = PackedVector2Array()
var tee_position: Vector3 = Vector3.ZERO
var pin_position: Vector3 = Vector3.ZERO
var _fairway_counter: int = 0
var _water_counter: int = 0


func _ready() -> void:
	reset_hole()
	canvas.gui_input.connect(_on_canvas_gui_input)
	$Layout/Sidebar/FairwayButton.pressed.connect(func(): begin_draw(DrawMode.FAIRWAY))
	$Layout/Sidebar/GreenButton.pressed.connect(func(): begin_draw(DrawMode.GREEN))
	$Layout/Sidebar/WaterButton.pressed.connect(func(): begin_draw(DrawMode.WATER))
	$Layout/Sidebar/TeeButton.pressed.connect(func(): begin_draw(DrawMode.NONE); mode_label.text = "Mode: place tee (next click)"; set_meta("place_tee", true))
	$Layout/Sidebar/PinButton.pressed.connect(func(): begin_draw(DrawMode.NONE); mode_label.text = "Mode: place pin (next click)"; set_meta("place_pin", true))
	$Layout/Sidebar/FinishButton.pressed.connect(finish_shape)
	$Layout/Sidebar/ResetButton.pressed.connect(reset_hole)


func reset_hole() -> void:
	author = HoleAuthoringModel.new()
	author.configure_identity("poc17_visual_builder", 1, "Developer Authored Hole", 4, 410.0)
	tee_position = Vector3(0.0, 0.0, 410.0)
	pin_position = Vector3.ZERO
	author.add_tee("back", "Back", tee_position, 410.0)
	author.set_pin(pin_position)
	draw_mode = DrawMode.NONE
	draft_points = PackedVector2Array()
	_fairway_counter = 0
	_water_counter = 0
	set_meta("place_tee", false)
	set_meta("place_pin", false)
	_refresh_summary()
	queue_redraw()


func begin_draw(mode: DrawMode) -> void:
	draw_mode = mode
	draft_points = PackedVector2Array()
	set_meta("place_tee", false)
	set_meta("place_pin", false)
	mode_label.text = "Mode: %s" % _mode_name(mode)
	queue_redraw()


func add_canvas_point(point: Vector2) -> void:
	if bool(get_meta("place_tee", false)):
		tee_position = _canvas_to_course(point)
		author.tees.clear()
		author.add_tee("back", "Back", tee_position, 410.0)
		set_meta("place_tee", false)
		mode_label.text = "Mode: none"
		_refresh_summary()
		queue_redraw()
		return
	if bool(get_meta("place_pin", false)):
		pin_position = _canvas_to_course(point)
		author.set_pin(pin_position)
		set_meta("place_pin", false)
		mode_label.text = "Mode: none"
		_refresh_summary()
		queue_redraw()
		return
	if draw_mode == DrawMode.NONE:
		return
	draft_points.append(_canvas_to_course_2d(point))
	queue_redraw()


func finish_shape() -> bool:
	if draft_points.size() < 3:
		return false
	match draw_mode:
		DrawMode.FAIRWAY:
			_fairway_counter += 1
			author.add_surface_region("fairway_%d" % _fairway_counter, "Fairway %d" % _fairway_counter, "FAIRWAY", draft_points)
		DrawMode.GREEN:
			author.set_green(draft_points)
		DrawMode.WATER:
			_water_counter += 1
			author.add_hazard("water_%d" % _water_counter, "Water %d" % _water_counter, "WATER", draft_points, 1, "lateral")
		_:
			return false
	draft_points = PackedVector2Array()
	draw_mode = DrawMode.NONE
	mode_label.text = "Mode: none"
	_refresh_summary()
	queue_redraw()
	return true


func authored_definition():
	return author.build_definition()


func authored_snapshot() -> Dictionary:
	var definition = authored_definition()
	if definition == null:
		return {"valid": false}
	return {
		"valid": true,
		"course_id": definition.course_id,
		"hole_number": definition.hole_number,
		"par": definition.par,
		"yardage": definition.nominal_yardage,
		"tees": definition.tees.size(),
		"surfaces": definition.surface_regions.size(),
		"hazards": definition.hazards.size(),
		"green_points": definition.green_polygon.size(),
		"pin": definition.pin_position
	}


func _on_canvas_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		add_canvas_point(event.position)


func _canvas_to_course(point: Vector2) -> Vector3:
	var size := canvas.size
	var x := (point.x / maxf(size.x, 1.0) - 0.5) * 160.0
	var z := (1.0 - point.y / maxf(size.y, 1.0)) * 440.0
	return Vector3(x, 0.0, z)


func _canvas_to_course_2d(point: Vector2) -> Vector2:
	var course := _canvas_to_course(point)
	return Vector2(course.x, course.z)


func _course_to_canvas(point: Vector2) -> Vector2:
	var x := (point.x / 160.0 + 0.5) * canvas.size.x
	var y := (1.0 - point.y / 440.0) * canvas.size.y
	return Vector2(x, y)


func _draw() -> void:
	if canvas == null:
		return
	# Drawing is performed in the root Control's coordinates; offset by Canvas.
	var offset := canvas.global_position - global_position
	_draw_polygon_outline(author.green_polygon, offset, 3.0)
	for region in author.surface_regions:
		_draw_polygon_outline(region.get("polygon", PackedVector2Array()), offset, 2.0)
	for hazard in author.hazards:
		_draw_polygon_outline(hazard.get("polygon", PackedVector2Array()), offset, 2.0)
	_draw_polygon_outline(draft_points, offset, 1.0)
	var tee_canvas := offset + _course_to_canvas(Vector2(tee_position.x, tee_position.z))
	var pin_canvas := offset + _course_to_canvas(Vector2(pin_position.x, pin_position.z))
	draw_circle(tee_canvas, 5.0, Color(1, 1, 1))
	draw_circle(pin_canvas, 5.0, Color(1, 1, 1))


func _draw_polygon_outline(points: PackedVector2Array, offset: Vector2, width: float) -> void:
	if points.size() < 2:
		return
	var converted := PackedVector2Array()
	for point in points:
		converted.append(offset + _course_to_canvas(point))
	if points.size() >= 3:
		converted.append(converted[0])
	draw_polyline(converted, Color(1, 1, 1), width, true)


func _refresh_summary() -> void:
	if summary_label == null:
		return
	var definition = authored_definition()
	if definition == null:
		summary_label.text = "Hole invalid/incomplete"
		return
	summary_label.text = "Hole %d  Par %d  %.0f yd\nSurfaces: %d  Hazards: %d\nGreen points: %d" % [
		definition.hole_number,
		definition.par,
		definition.nominal_yardage,
		definition.surface_regions.size(),
		definition.hazards.size(),
		definition.green_polygon.size()
	]


func _mode_name(mode: DrawMode) -> String:
	match mode:
		DrawMode.FAIRWAY: return "draw fairway"
		DrawMode.GREEN: return "draw green"
		DrawMode.WATER: return "draw water"
		_: return "none"
