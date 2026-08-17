extends Node2D

# POC-30H: Isometric Visual Spike
# -------------------------------
# Renders the same authoritative Contour Creek proof hole used by POC-30F through
# a 64x32 diamond isometric presentation. This is deliberately a renderer spike,
# not a rewrite of construction, economics, HoleDefinition, or golfer simulation.

const CourseConstructionGrid = preload("res://simulation/course_construction_grid.gd")
const CourseConstructionEconomy = preload("res://simulation/course_construction_economy.gd")
const ConstructionGridHoleBuilder = preload("res://simulation/construction_grid_hole_builder.gd")
const CourseDressing = preload("res://scenes/construction_grid_course_dressing.gd")
const RotatableIsometricCourseRenderer = preload("res://scenes/isometric_rotatable_course_renderer.gd")

var grid = null
var economy = null
var hole = null
var renderer = null
var dressing_plan: Array = []
var camera: Camera2D = null
var initialized: bool = false
var initialization_reason: String = ""
var active_review_view: int = 1


func _ready() -> void:
	initialized = initialize_proof()
	if not initialized:
		push_error("POC-30H isometric proof failed to initialize: %s" % initialization_reason)
		return
	_add_background()
	_add_camera()
	_add_hud()
	print("POC30H_ISOMETRIC_READY yardage=%.1f par=%d spend=%d fairway=%d fringe=%d green=%d bunker=%d water=%d dressing=%d" % [
		float(hole.nominal_yardage),
		int(hole.par),
		int(economy.lifetime_construction_spend),
		int(grid.count_surface("FAIRWAY")),
		int(grid.count_surface("FRINGE")),
		int(grid.count_surface("GREEN")),
		int(grid.count_surface("BUNKER")),
		int(grid.count_surface("WATER")),
		dressing_plan.size()
	])


func initialize_proof() -> bool:
	if initialized and grid != null and hole != null and renderer != null:
		return true

	grid = CourseConstructionGrid.new()
	if not grid.configure(15, 48, 10.0, Vector2(-75.0, -15.0)):
		initialization_reason = "GRID_CONFIGURE_FAILED"
		return false
	_author_landform()

	economy = CourseConstructionEconomy.new()
	if not economy.configure(grid, 30000):
		initialization_reason = "ECONOMY_CONFIGURE_FAILED"
		return false
	if not _build_player_hole():
		initialization_reason = "CONSTRUCTION_FAILED"
		return false

	var builder = ConstructionGridHoleBuilder.new()
	hole = builder.build_hole(
		grid,
		"poc30_visual_proof_course",
		1,
		"Contour Creek",
		4,
		Vector2i(7, 44),
		Vector2i(7, 3),
		"back",
		"Back Tee"
	)
	if hole == null:
		initialization_reason = "HOLE_BUILD_FAILED"
		return false

	var dressing_planner = CourseDressing.new()
	dressing_plan = dressing_planner.build_dressing_plan(grid)
	dressing_planner.free()

	renderer = RotatableIsometricCourseRenderer.new()
	renderer.name = "IsometricCourseRenderer"
	add_child(renderer)
	if not renderer.configure(grid, dressing_plan, Vector2i(7, 3), Vector2i(7, 44)):
		initialization_reason = "ISOMETRIC_RENDERER_CONFIGURE_FAILED"
		return false

	initialized = true
	initialization_reason = "READY"
	return true


func _author_landform() -> void:
	# Exact same authored POC-30F landform.
	for y in range(int(grid.height)):
		for x in range(int(grid.width)):
			var elevation: float = (
				1.35 * sin(float(y) * 0.23)
				+ 0.55 * cos(float(x - 7) * 0.42)
				+ 0.35 * sin(float(x + y) * 0.17)
			)
			grid.set_elevation(x, y, elevation)


func _build_player_hole() -> bool:
	# Exact same authoritative construction recipe as POC-30F.
	for y in range(44, 46):
		for x in range(6, 9):
			if not _purchase(x, y, "TEE"):
				return false

	for y in range(8, 44):
		var center_x: int = 7
		if y >= 18 and y < 29:
			center_x = 8
		elif y >= 29 and y < 37:
			center_x = 6
		for x in range(center_x - 1, center_x + 2):
			if not _purchase(x, y, "FAIRWAY"):
				return false

	for y in range(1, 6):
		for x in range(5, 10):
			if x >= 6 and x <= 8 and y >= 2 and y <= 4:
				continue
			if not _purchase(x, y, "FRINGE"):
				return false
	for y in range(2, 5):
		for x in range(6, 9):
			if not _purchase(x, y, "GREEN"):
				return false

	for cell in [Vector2i(4, 4), Vector2i(4, 5), Vector2i(4, 6), Vector2i(5, 6)]:
		if not _purchase(cell.x, cell.y, "BUNKER"):
			return false
	for cell in [
		Vector2i(10, 24), Vector2i(11, 24),
		Vector2i(10, 25), Vector2i(11, 25),
		Vector2i(10, 26), Vector2i(11, 26),
		Vector2i(10, 27), Vector2i(11, 27)
	]:
		if not _purchase(cell.x, cell.y, "WATER"):
			return false
	return true


func _purchase(x: int, y: int, surface: String) -> bool:
	var result: Dictionary = economy.build_surface(x, y, surface)
	return bool(result.get("built", false))


func _add_background() -> void:
	var layer := CanvasLayer.new()
	layer.name = "BackgroundLayer"
	layer.layer = -10
	add_child(layer)
	var background := ColorRect.new()
	background.name = "Background"
	background.color = Color(0.10, 0.17, 0.10)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(background)


func _add_camera() -> void:
	camera = Camera2D.new()
	camera.name = "IsometricCamera"
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 7.0
	add_child(camera)
	camera.enabled = true
	camera.make_current()
	switch_review_view(1)


func switch_review_view(view_index: int) -> void:
	if camera == null or renderer == null:
		return
	active_review_view = view_index
	match view_index:
		1:
			var bounds: Rect2 = renderer.visual_bounds().grow(80.0)
			camera.position = bounds.get_center()
			var viewport_size: Vector2 = get_viewport().get_visible_rect().size
			var usable_height: float = maxf(viewport_size.y - 120.0, 320.0)
			var zoom_factor: float = minf(viewport_size.x / maxf(bounds.size.x, 1.0), usable_height / maxf(bounds.size.y, 1.0))
			zoom_factor = clampf(zoom_factor, 0.42, 1.15)
			camera.zoom = Vector2(zoom_factor, zoom_factor)
		2:
			camera.position = renderer.cell_center_iso(7, 44) + Vector2(0.0, -70.0)
			camera.zoom = Vector2(1.15, 1.15)
		3:
			camera.position = renderer.cell_center_iso(7, 3) + Vector2(0.0, -50.0)
			camera.zoom = Vector2(1.35, 1.35)
		_:
			active_review_view = 1
			switch_review_view(1)


func rotate_camera_view(step_quarters: int) -> void:
	if renderer == null:
		return
	var saved_zoom: Vector2 = camera.zoom if camera != null else Vector2.ONE
	renderer.rotate_view(step_quarters)
	if camera == null:
		return
	match active_review_view:
		2:
			camera.position = renderer.cell_center_iso(7, 44) + Vector2(0.0, -70.0)
		3:
			camera.position = renderer.cell_center_iso(7, 3) + Vector2(0.0, -50.0)
		_:
			camera.position = renderer.visual_bounds().get_center()
	camera.zoom = saved_zoom


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_1:
			switch_review_view(1)
		elif event.keycode == KEY_2:
			switch_review_view(2)
		elif event.keycode == KEY_3:
			switch_review_view(3)
		elif event.keycode == KEY_Q:
			rotate_camera_view(-1)
		elif event.keycode == KEY_E:
			rotate_camera_view(1)
	elif event is InputEventMouseButton and event.pressed and camera != null:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera.zoom = (camera.zoom * 1.10).clamp(Vector2(0.35, 0.35), Vector2(2.5, 2.5))
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.zoom = (camera.zoom / 1.10).clamp(Vector2(0.35, 0.35), Vector2(2.5, 2.5))


func _process(delta: float) -> void:
	if camera == null:
		return
	var direction := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if direction.length_squared() > 0.0:
		camera.position += direction * 420.0 * delta / maxf(camera.zoom.x, 0.1)


func _add_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "ReviewHUD"
	layer.layer = 10
	add_child(layer)

	var panel := ColorRect.new()
	panel.color = Color(0.025, 0.04, 0.025, 0.86)
	panel.position = Vector2(18.0, 18.0)
	panel.size = Vector2(560.0, 118.0)
	layer.add_child(panel)

	var label := Label.new()
	label.position = Vector2(34.0, 29.0)
	label.text = "POC-30H  •  CONTOUR CREEK  •  64×32 ISOMETRIC SPIKE\n410 yd  •  Par 4  •  Same authoritative construction grid\n1 Full course    2 Tee area    3 Green area    Q/E Rotate view\nArrow keys pan  •  Mouse wheel zoom  •  Crisp surfaces + smooth elevation"
	label.add_theme_font_size_override("font_size", 16)
	layer.add_child(label)
