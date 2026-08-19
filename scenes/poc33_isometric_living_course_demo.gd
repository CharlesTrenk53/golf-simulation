extends Node2D

# POC-33D: Launchable Isometric Living-Course Demo
# -------------------------------------------------
# Human-facing proof that the accepted player-authored construction-grid terrain
# can host the already-authoritative living-course population in the accepted
# isometric presentation. Golf decisions, shot outcomes, scoring, pace, traffic,
# tee releases, and group state remain owned by the POC-24/25 simulation stack.
# This scene only authors a visual construction property, projects those existing
# golfer/ball visuals into isometric space, and consumes authoritative timestamps.

const CourseDefinition = preload("res://simulation/course_definition.gd")
const CourseConstructionGrid = preload("res://simulation/course_construction_grid.gd")
const SpacingAwareTimedCourseController = preload("res://simulation/spacing_aware_timed_course_controller.gd")
const SpectatorCourseWorld = preload("res://scenes/spectator_course_world.gd")
const SpectatorPopulationView = preload("res://scenes/spectator_population_view.gd")
const LivingSpectatorSession = preload("res://scenes/living_spectator_session.gd")
const IsometricRotatableCourseRenderer = preload("res://scenes/isometric_rotatable_course_renderer.gd")
const IsometricLivingGolferLayer = preload("res://scenes/isometric_living_golfer_layer.gd")
const Golfer = preload("res://scenes/golfer.gd")

const GRID_WIDTH: int = 80
const GRID_HEIGHT: int = 50
const TILE_SIZE_YARDS: float = 10.0
const GRID_ORIGIN := Vector2(0.0, 0.0)
const COURSE_PATH := "res://data/courses/poc12_proving_course.json"

@export var auto_advance: bool = true
@export var simulation_speed: float = 120.0
@export var max_real_step_seconds: float = 0.05
@export var initial_zoom: float = 0.34
@export var seed_value: int = 33301

var course = null
var controller = null
var course_world = null
var population_view = null
var session = null
var grid = null
var renderer = null
var living_layer = null
var camera: Camera2D = null
var initialized: bool = false
var golfer_nodes: Array = []

var status_label: Label = null
var groups_label: Label = null
var controls_label: Label = null


func _ready() -> void:
	if not initialize_demo():
		push_error("POC-33D isometric living-course demo failed to initialize")


func _process(delta: float) -> void:
	if not initialized:
		return
	if auto_advance:
		advance_presentation(delta)
	else:
		_refresh_projection()


func _unhandled_input(event: InputEvent) -> void:
	if not initialized:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_Q:
				rotate_view(-1)
				get_viewport().set_input_as_handled()
			KEY_E:
				rotate_view(1)
				get_viewport().set_input_as_handled()
			KEY_SPACE:
				auto_advance = not auto_advance
				_update_hud()
				get_viewport().set_input_as_handled()
			KEY_LEFT:
				_pan_camera(Vector2(-1.0, 0.0))
				get_viewport().set_input_as_handled()
			KEY_RIGHT:
				_pan_camera(Vector2(1.0, 0.0))
				get_viewport().set_input_as_handled()
			KEY_UP:
				_pan_camera(Vector2(0.0, -1.0))
				get_viewport().set_input_as_handled()
			KEY_DOWN:
				_pan_camera(Vector2(0.0, 1.0))
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_camera(1.10)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_camera(1.0 / 1.10)
			get_viewport().set_input_as_handled()


func initialize_demo() -> bool:
	if initialized:
		return true

	course = CourseDefinition.load_json(COURSE_PATH)
	if course == null or course.hole_count() != 3:
		return false

	controller = SpacingAwareTimedCourseController.new()
	if not controller.configure(course):
		return false

	# Three twosomes create enough population to see a lead group, a safely
	# released follower, and a waiting group without introducing new traffic rules.
	if not controller.add_group("group_1", [_make_golfer(Golfer.GolferProfile.CAREFUL_CARL), _make_golfer(Golfer.GolferProfile.WILD_BILL)]):
		return false
	if not controller.add_group("group_2", [_make_golfer(Golfer.GolferProfile.WILD_BILL), _make_golfer(Golfer.GolferProfile.CAREFUL_CARL)]):
		return false
	if not controller.add_group("group_3", [_make_golfer(Golfer.GolferProfile.CAREFUL_CARL), _make_golfer(Golfer.GolferProfile.WILD_BILL)]):
		return false

	# Reuse the proven POC-25 world solely as the presentation-coordinate bridge
	# used by SpectatorGroupVisual. Hide its old 3D renderer; POC-33 draws the same
	# positions on the construction-grid isometric world instead.
	course_world = SpectatorCourseWorld.new()
	course_world.name = "HiddenSpectatorCourseWorld"
	add_child(course_world)
	if not course_world.configure(course):
		return false
	course_world.visible = false

	population_view = SpectatorPopulationView.new()
	population_view.name = "HiddenSpectatorPopulationView"
	add_child(population_view)
	if not population_view.configure(course_world, controller):
		return false
	population_view.visible = false

	session = LivingSpectatorSession.new()
	session.name = "LivingSpectatorSession"
	add_child(session)
	if not session.configure(controller, course_world, population_view, seed_value):
		return false

	grid = CourseConstructionGrid.new()
	if not grid.configure(GRID_WIDTH, GRID_HEIGHT, TILE_SIZE_YARDS, GRID_ORIGIN):
		return false
	_author_player_property()

	renderer = IsometricRotatableCourseRenderer.new()
	renderer.name = "IsometricCourseRenderer"
	add_child(renderer)
	if not renderer.configure(grid, _course_dressing()):
		return false

	living_layer = IsometricLivingGolferLayer.new()
	living_layer.name = "IsometricLivingGolferLayer"
	add_child(living_layer)
	if not living_layer.configure(renderer, grid):
		return false

	_build_camera()
	_build_hud()
	if session.start_session().is_empty():
		return false
	if not living_layer.sync_from_population_view(population_view):
		return false

	initialized = true
	_update_hud()
	return true


func advance_presentation(real_delta_seconds: float) -> Dictionary:
	if not initialized or session == null:
		return {}

	var visible_action: bool = false
	for playback in session.active_playbacks.values():
		if playback == null:
			continue
		playback.complete_finished_flights()
		if playback.has_active_flight() or playback.has_active_tee_dispersion():
			visible_action = true
	for visual in population_view.group_visuals.values():
		if visual != null and visual.has_active_inter_hole_transition():
			visible_action = true

	# Preserve the accepted spectator pacing contract: visible ball flights and
	# group walks run in real time; only dead authoritative clock time is compressed.
	if not visible_action and not _physical_round_complete():
		var real_step: float = clampf(real_delta_seconds, 0.0, max_real_step_seconds)
		if real_step > 0.0:
			session.advance_time(real_step * maxf(simulation_speed, 0.01), true)

	_refresh_projection()
	return snapshot()


func rotate_view(step_quarters: int) -> bool:
	if renderer == null or living_layer == null:
		return false
	renderer.rotate_view(step_quarters)
	living_layer.refresh_projection()
	if camera != null:
		camera.position = renderer.visual_bounds().get_center()
	_update_hud()
	return true


func snapshot() -> Dictionary:
	var layer_snapshot: Dictionary = living_layer.snapshot() if living_layer != null else {}
	return {
		"initialized": initialized,
		"simulation_time_seconds": controller.current_time_seconds if controller != null else 0.0,
		"auto_advance": auto_advance,
		"rotation_quarters": int(renderer.rotation_quarters) if renderer != null else 0,
		"grid_width": int(grid.width) if grid != null else 0,
		"grid_height": int(grid.height) if grid != null else 0,
		"fairway_cells": int(grid.count_surface("FAIRWAY")) if grid != null else 0,
		"tee_cells": int(grid.count_surface("TEE")) if grid != null else 0,
		"green_cells": int(grid.count_surface("GREEN")) if grid != null else 0,
		"bunker_cells": int(grid.count_surface("BUNKER")) if grid != null else 0,
		"group_count": int(layer_snapshot.get("group_count", 0)),
		"golfer_count": int(layer_snapshot.get("golfer_count", 0)),
		"ball_count": int(layer_snapshot.get("ball_count", 0)),
		"physical_round_complete": _physical_round_complete(),
		"groups": layer_snapshot.get("groups", []).duplicate(true),
		"camera_position": camera.position if camera != null else Vector2.ZERO,
		"camera_zoom": camera.zoom if camera != null else Vector2.ONE,
		"hud_status": status_label.text if status_label != null else ""
	}


func _make_golfer(profile_value: int):
	var golfer = Golfer.new()
	golfer.profile = profile_value
	golfer.apply_profile()
	golfer_nodes.append(golfer)
	add_child(golfer)
	return golfer


func _author_player_property() -> void:
	# This is a construction-grid property, not a parallel visual map. Every
	# surface and elevation painted here is stored in CourseConstructionGrid and
	# read back by the same isometric renderer proven in POC-30/31/32.
	for y in range(GRID_HEIGHT):
		for x in range(GRID_WIDTH):
			var elevation := (
				0.85 * sin(float(y) * 0.16)
				+ 0.55 * cos(float(x) * 0.12)
				+ 0.22 * sin(float(x + y) * 0.09)
			)
			grid.set_elevation(x, y, elevation)

	for hole_number in range(1, course.hole_count() + 1):
		var hole = course.hole_by_number(hole_number)
		var tee_world: Vector3 = course_world.world_position(hole_number, hole.tee_position("default"))
		var pin_world: Vector3 = course_world.world_position(hole_number, hole.pin_position)
		_paint_fairway_ribbon(tee_world, pin_world, hole_number)
		_paint_disc_world(pin_world, 3, "FRINGE")
		_paint_disc_world(pin_world, 2, "GREEN")
		_paint_disc_world(tee_world, 1, "TEE")

		# A small deterministic fairway bunker gives the visual proof another crisp
		# player-owned surface without attempting to recreate authored hazard rules.
		var bunker_point: Vector3 = tee_world.lerp(pin_world, 0.58)
		var forward := Vector2(pin_world.x - tee_world.x, pin_world.z - tee_world.z).normalized()
		var lateral := Vector2(-forward.y, forward.x)
		bunker_point.x += lateral.x * (18.0 + 4.0 * float(hole_number))
		bunker_point.z += lateral.y * (18.0 + 4.0 * float(hole_number))
		_paint_disc_world(bunker_point, 1, "BUNKER")


func _paint_fairway_ribbon(tee_world: Vector3, pin_world: Vector3, hole_number: int) -> void:
	var distance: float = Vector2(tee_world.x, tee_world.z).distance_to(Vector2(pin_world.x, pin_world.z))
	var steps: int = maxi(int(ceil(distance / (TILE_SIZE_YARDS * 0.45))), 1)
	var forward := Vector2(pin_world.x - tee_world.x, pin_world.z - tee_world.z).normalized()
	var lateral := Vector2(-forward.y, forward.x)
	for index in range(steps + 1):
		var t: float = float(index) / float(steps)
		var p: Vector3 = tee_world.lerp(pin_world, t)
		var bend: float = sin(t * PI * 2.0 + float(hole_number) * 0.7) * 10.0
		p.x += lateral.x * bend
		p.z += lateral.y * bend
		_paint_disc_world(p, 2, "FAIRWAY")


func _paint_disc_world(world_position: Vector3, radius_cells: int, surface: String) -> void:
	var center: Vector2i = _world_to_cell(world_position)
	for dy in range(-radius_cells, radius_cells + 1):
		for dx in range(-radius_cells, radius_cells + 1):
			if dx * dx + dy * dy > radius_cells * radius_cells + 1:
				continue
			var cell := center + Vector2i(dx, dy)
			if grid.is_in_bounds(cell.x, cell.y):
				grid.set_surface(cell.x, cell.y, surface)


func _world_to_cell(world_position: Vector3) -> Vector2i:
	return Vector2i(
		int(floor((world_position.x - grid.origin.x) / grid.tile_size_yards)),
		int(floor((world_position.z - grid.origin.y) / grid.tile_size_yards))
	)


func _course_dressing() -> Array:
	var records: Array = []
	for hole_number in range(1, course.hole_count() + 1):
		var hole = course.hole_by_number(hole_number)
		var tee_world: Vector3 = course_world.world_position(hole_number, hole.tee_position("default"))
		var pin_world: Vector3 = course_world.world_position(hole_number, hole.pin_position)
		var forward := Vector2(pin_world.x - tee_world.x, pin_world.z - tee_world.z).normalized()
		var lateral := Vector2(-forward.y, forward.x)
		for index in range(1, 7):
			var t: float = float(index) / 7.0
			var center: Vector3 = tee_world.lerp(pin_world, t)
			for side in [-1.0, 1.0]:
				var offset: float = side * (48.0 + float((index + hole_number) % 3) * 7.0)
				var p := Vector3(center.x + lateral.x * offset, 0.0, center.z + lateral.y * offset)
				var cell: Vector2i = _world_to_cell(p)
				if grid.is_in_bounds(cell.x, cell.y):
					records.append({"kind": "TREE", "position": p, "scale": 0.82 + 0.05 * float((index + hole_number) % 4)})
	return records


func _build_camera() -> void:
	camera = Camera2D.new()
	camera.name = "IsometricCamera"
	camera.position = renderer.visual_bounds().get_center()
	var z: float = clampf(initial_zoom, 0.18, 1.25)
	camera.zoom = Vector2(z, z)
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 6.0
	add_child(camera)
	camera.make_current()


func _build_hud() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "LivingCourseHUD"
	add_child(canvas)

	var panel := PanelContainer.new()
	panel.offset_left = 18.0
	panel.offset_top = 18.0
	panel.offset_right = 445.0
	panel.offset_bottom = 230.0
	canvas.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	margin.add_child(box)

	var title := Label.new()
	title.text = "POC-33 • Living Isometric Course"
	title.add_theme_font_size_override("font_size", 20)
	box.add_child(title)

	status_label = Label.new()
	box.add_child(status_label)
	groups_label = Label.new()
	box.add_child(groups_label)
	controls_label = Label.new()
	controls_label.text = "Q/E rotate • Arrows pan • Wheel zoom • Space pause clock"
	controls_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(controls_label)


func _refresh_projection() -> void:
	if living_layer != null and population_view != null:
		living_layer.sync_from_population_view(population_view)
	_update_hud()


func _update_hud() -> void:
	if status_label == null or groups_label == null:
		return
	var state: String = "RUNNING" if auto_advance else "PAUSED"
	var time_seconds: float = controller.current_time_seconds if controller != null else 0.0
	status_label.text = "%s  •  Course clock %02d:%02d  •  View %d/4" % [
		state,
		int(time_seconds) / 60,
		int(time_seconds) % 60,
		(int(renderer.rotation_quarters) + 1) if renderer != null else 1
	]
	var parts: Array[String] = []
	if living_layer != null:
		for group_value in living_layer.snapshot().get("groups", []):
			var group: Dictionary = group_value
			var traffic_hole: int = int(group.get("traffic_hole_number", 0))
			var place: String = "waiting" if traffic_hole <= 0 else "hole %d" % traffic_hole
			parts.append("%s %s (%s)" % [str(group.get("group_id", "group")), str(group.get("status", "")), place])
	groups_label.text = "\n".join(parts)


func _physical_round_complete() -> bool:
	if controller == null or controller.living_course == null:
		return false
	for group in controller.living_course.population.groups:
		if group != null and str(group.status) != "FINISHED":
			return false
	return true


func _pan_camera(direction: Vector2) -> void:
	if camera == null:
		return
	var scale_value: float = maxf(camera.zoom.x, 0.01)
	camera.position += direction * (70.0 / scale_value)


func _zoom_camera(multiplier: float) -> void:
	if camera == null:
		return
	var next_zoom: float = clampf(camera.zoom.x * multiplier, 0.18, 1.25)
	camera.zoom = Vector2(next_zoom, next_zoom)
