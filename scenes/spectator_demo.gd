extends Node3D

# POC-25H: Launchable Living Spectator Demo
# ------------------------------------------
# Human-facing spectator experience over the authoritative POC-24/25 simulation.
# This scene owns presentation only: camera, controls, HUD, and wall-clock pacing.
# Golf outcomes, group traffic, tee releases, honors, away order, and scoring all
# remain authoritative in the existing simulation/controller stack.
#
# Spectator pacing deliberately compresses uneventful wall-clock time. The
# authoritative course clock still uses the full POC-24 walking/routine/traffic
# durations; only the rate at which the presentation consumes those timestamps
# changes. Visible ball flights, tee dispersal walks, and inter-hole walks pause
# the course clock so none of those presentations can be skipped.

const CourseDefinition = preload("res://simulation/course_definition.gd")
const SpacingAwareTimedCourseController = preload("res://simulation/spacing_aware_timed_course_controller.gd")
const SpectatorCourseWorld = preload("res://scenes/spectator_course_world.gd")
const SpectatorPopulationView = preload("res://scenes/spectator_population_view.gd")
const LivingSpectatorSession = preload("res://scenes/living_spectator_session.gd")
const SpectatorFocusController = preload("res://scenes/spectator_focus_controller.gd")
const Golfer = preload("res://scenes/golfer.gd")

@export var auto_advance: bool = true
@export var simulation_speed: float = 30.0
@export var playing_idle_simulation_speed: float = 120.0
@export var waiting_simulation_speed: float = 60.0
@export var max_real_step_seconds: float = 0.05
@export var camera_offset: Vector3 = Vector3(34.0, 30.0, 38.0)
@export var camera_lerp_speed: float = 4.0
@export var seed_value: int = 27501

var controller = null
var course_world = null
var population_view = null
var session = null
var focus_controller = null
var initialized: bool = false
var golfer_nodes: Array = []

var spectator_camera: Camera3D = null
var status_label: Label = null
var shot_label: Label = null
var members_label: Label = null
var clock_label: Label = null
var group_label: Label = null


func _ready() -> void:
	initialize_demo()


func _process(delta: float) -> void:
	if not initialized:
		return
	if auto_advance:
		advance_presentation(delta)
	else:
		_refresh_presentation(delta)


func _unhandled_input(event: InputEvent) -> void:
	if not initialized or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == KEY_TAB or event.keycode == KEY_RIGHT:
		cycle_group(1)
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_LEFT:
		cycle_group(-1)
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_1:
		select_group("group_1")
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_2:
		select_group("group_2")
		get_viewport().set_input_as_handled()


func initialize_demo() -> bool:
	if initialized:
		return true
	var course = CourseDefinition.load_json("res://data/courses/poc12_proving_course.json")
	if course == null or course.hole_count() != 3:
		return false

	controller = SpacingAwareTimedCourseController.new()
	if not controller.configure(course):
		return false

	var lead_a = _make_golfer(Golfer.GolferProfile.CAREFUL_CARL)
	var lead_b = _make_golfer(Golfer.GolferProfile.WILD_BILL)
	var follow_a = _make_golfer(Golfer.GolferProfile.CAREFUL_CARL)
	var follow_b = _make_golfer(Golfer.GolferProfile.CAREFUL_CARL)
	if not controller.add_group("group_1", [lead_a, lead_b]):
		return false
	if not controller.add_group("group_2", [follow_a, follow_b]):
		return false

	course_world = SpectatorCourseWorld.new()
	course_world.name = "CourseWorld"
	add_child(course_world)
	if not course_world.configure(course):
		return false

	population_view = SpectatorPopulationView.new()
	population_view.name = "PopulationView"
	add_child(population_view)
	if not population_view.configure(course_world, controller):
		return false

	session = LivingSpectatorSession.new()
	session.name = "LivingSpectatorSession"
	add_child(session)
	if not session.configure(controller, course_world, population_view, seed_value):
		return false

	focus_controller = SpectatorFocusController.new()
	focus_controller.name = "SpectatorFocusController"
	add_child(focus_controller)
	if not focus_controller.configure(session, population_view):
		return false

	_build_environment()
	_build_hud()
	if session.start_session().is_empty():
		return false
	initialized = true
	_refresh_presentation(1.0)
	return true


func advance_presentation(real_delta_seconds: float) -> Dictionary:
	if not initialized or session == null:
		return {}
	var any_flying: bool = false
	for playback in session.active_playbacks.values():
		if playback == null:
			continue
		playback.complete_finished_flights()
		if playback.has_active_flight():
			any_flying = true

	var any_walking: bool = _any_group_walking()

	# Ball flights and visible group walks remain normal-speed actions. Between
	# visible actions we consume authoritative simulation time faster so realistic
	# walking and shot-routine timestamps do not become spectator dead air.
	# Authority may already be ahead of the presentation; pausing here prevents a
	# later shot from visually overtaking a tee-dispersal or inter-hole walk.
	if not any_flying and not any_walking and not _physical_round_complete():
		var real_step: float = clampf(real_delta_seconds, 0.0, max_real_step_seconds)
		if real_step > 0.0:
			session.advance_time(real_step * presentation_simulation_speed(), true)

	_refresh_presentation(real_delta_seconds)
	return snapshot()


func select_group(group_id: String) -> bool:
	if focus_controller == null or not focus_controller.select_group(group_id):
		return false
	_refresh_presentation(0.0, true)
	return true


func cycle_group(step: int = 1) -> String:
	if focus_controller == null:
		return ""
	var selected: String = focus_controller.cycle_group(step)
	_refresh_presentation(0.0, true)
	return selected


func presentation_simulation_speed() -> float:
	var base_speed: float = maxf(simulation_speed, 0.01)
	if not initialized or focus_controller == null:
		return base_speed
	var presentation: Dictionary = focus_controller.presentation_snapshot()
	if presentation.is_empty():
		return base_speed
	var status: String = str(presentation.get("status", ""))
	if status == "PLAYING":
		return maxf(base_speed, playing_idle_simulation_speed)
	if status == "WAITING":
		return maxf(base_speed, waiting_simulation_speed)
	return base_speed


func snapshot() -> Dictionary:
	return {
		"initialized": initialized,
		"simulation_time_seconds": controller.current_time_seconds if controller != null else 0.0,
		"presentation_speed": presentation_simulation_speed(),
		"physical_round_complete": _physical_round_complete(),
		"inter_hole_walk_active": _any_inter_hole_walk(),
		"visible_walk_active": _any_group_walking(),
		"focus": focus_controller.presentation_snapshot() if focus_controller != null else {},
		"hud_status": status_label.text if status_label != null else "",
		"hud_shot": shot_label.text if shot_label != null else "",
		"hud_members": members_label.text if members_label != null else "",
		"camera_position": spectator_camera.global_position if spectator_camera != null else Vector3.ZERO
	}


func _make_golfer(profile_value: int):
	var golfer = Golfer.new()
	golfer.profile = profile_value
	golfer.apply_profile()
	golfer_nodes.append(golfer)
	add_child(golfer)
	return golfer


func _build_environment() -> void:
	var light := DirectionalLight3D.new()
	light.name = "Sun"
	light.rotation_degrees = Vector3(-55.0, -28.0, 0.0)
	light.shadow_enabled = true
	add_child(light)

	spectator_camera = Camera3D.new()
	spectator_camera.name = "SpectatorCamera"
	spectator_camera.current = true
	spectator_camera.fov = 48.0
	add_child(spectator_camera)

	var world_environment := WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.53, 0.72, 0.90)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.65, 0.68, 0.72)
	environment.ambient_light_energy = 0.75
	world_environment.environment = environment
	add_child(world_environment)


func _build_hud() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "SpectatorHUD"
	add_child(canvas)

	var panel := PanelContainer.new()
	panel.name = "InfoPanel"
	panel.offset_left = 20.0
	panel.offset_top = 20.0
	panel.offset_right = 470.0
	panel.offset_bottom = 290.0
	canvas.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "LIVING COURSE — SPECTATOR MODE"
	title.add_theme_font_size_override("font_size", 21)
	vbox.add_child(title)

	group_label = Label.new()
	group_label.add_theme_font_size_override("font_size", 18)
	vbox.add_child(group_label)

	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(status_label)

	shot_label = Label.new()
	shot_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(shot_label)

	members_label = Label.new()
	members_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(members_label)

	clock_label = Label.new()
	vbox.add_child(clock_label)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	vbox.add_child(buttons)
	var previous := Button.new()
	previous.text = "◀ Previous Group"
	previous.pressed.connect(_on_previous_group)
	buttons.add_child(previous)
	var next := Button.new()
	next.text = "Next Group ▶"
	next.pressed.connect(_on_next_group)
	buttons.add_child(next)

	var help := Label.new()
	help.text = "TAB / ← → switch groups   •   1 / 2 jump to group"
	help.add_theme_font_size_override("font_size", 12)
	vbox.add_child(help)


func _refresh_presentation(delta: float, snap_camera: bool = false) -> void:
	if focus_controller == null:
		return
	var presentation: Dictionary = focus_controller.presentation_snapshot()
	if presentation.is_empty():
		return
	_update_hud(presentation)
	_update_camera(presentation.get("camera_target", Vector3.ZERO), delta, snap_camera)


func _update_hud(presentation: Dictionary) -> void:
	var group_id: String = str(presentation.get("group_id", ""))
	var status: String = str(presentation.get("status", ""))
	var hole_number: int = int(presentation.get("hole_number", 0))
	group_label.text = "%s  •  Hole %d" % [_display_group_name(group_id), hole_number]

	var selected_visual = population_view.group_visual(group_id) if population_view != null else null
	var selected_playback = session.playback_for_group(group_id) if session != null else null
	var inter_hole_walking: bool = selected_visual != null and selected_visual.has_active_inter_hole_transition()
	var tee_dispersion_walking: bool = selected_playback != null and selected_playback.has_active_tee_dispersion()
	var walking: bool = inter_hole_walking or tee_dispersion_walking
	if tee_dispersion_walking:
		status_label.text = "WALKING — dispersing to tee shots"
	elif inter_hole_walking:
		var transition: Dictionary = selected_visual.transition_snapshot()
		status_label.text = "WALKING — to Hole %d tee" % int(transition.get("to_hole_number", hole_number))
	elif status == "WAITING":
		if bool(presentation.get("waiting_for_group_ahead", false)):
			status_label.text = "WAITING — group ahead must clear"
		elif int(presentation.get("traffic_hole_number", 0)) <= 0:
			status_label.text = "WAITING — on the first tee"
		else:
			status_label.text = "WAITING — next hole not yet available"
	elif status == "FINISHED":
		status_label.text = "FINISHED — round complete"
	else:
		status_label.text = "PLAYING"

	var shot: Dictionary = presentation.get("shot", {})
	var phase: String = str(shot.get("phase", "NONE"))
	if tee_dispersion_walking:
		shot_label.text = "Group moving to their balls"
	elif inter_hole_walking:
		shot_label.text = "Moving to the next tee"
	elif phase == "ACTIVE" or phase == "NEXT":
		var prefix: String = "NOW" if phase == "ACTIVE" else "NEXT"
		var club: String = str(shot.get("club_name", shot.get("club_id", "")))
		var intent: String = str(shot.get("intent", ""))
		var lie: String = str(shot.get("lie", ""))
		shot_label.text = "%s: %s — %s | %s | %s" % [prefix, str(shot.get("golfer_name", "Golfer")), club, intent, lie]
	elif phase == "BETWEEN_SHOTS":
		shot_label.text = "Between shots"
	else:
		shot_label.text = "No shot currently scheduled"

	var member_lines: Array[String] = []
	for member_value in presentation.get("members", []):
		if typeof(member_value) != TYPE_DICTIONARY:
			continue
		var member: Dictionary = member_value
		var line: String = "%s  %s" % [str(member.get("golfer_name", "Golfer")), str(member.get("score_label", "E"))]
		var seen: int = int(member.get("current_hole_strokes_seen", 0))
		if status == "PLAYING" and seen > 0 and not walking:
			line += "  •  %d stroke%s this hole" % [seen, "" if seen == 1 else "s"]
		member_lines.append(line)
	members_label.text = "\n".join(member_lines)

	var sim_seconds: float = controller.current_time_seconds if controller != null else 0.0
	clock_label.text = "Course clock: %02d:%02d" % [int(sim_seconds) / 60, int(sim_seconds) % 60]


func _update_camera(target: Vector3, delta: float, snap_camera: bool) -> void:
	if spectator_camera == null:
		return
	var desired: Vector3 = target + camera_offset
	if snap_camera or spectator_camera.global_position == Vector3.ZERO:
		spectator_camera.global_position = desired
	else:
		var weight: float = clampf(delta * camera_lerp_speed, 0.0, 1.0)
		spectator_camera.global_position = spectator_camera.global_position.lerp(desired, weight)
	if spectator_camera.global_position.distance_to(target) > 0.01:
		spectator_camera.look_at(target, Vector3.UP)


func _any_inter_hole_walk() -> bool:
	if population_view == null:
		return false
	for visual in population_view.group_visuals.values():
		if visual != null and visual.has_active_inter_hole_transition():
			return true
	return false


func _any_group_walking() -> bool:
	if _any_inter_hole_walk():
		return true
	if session == null:
		return false
	for playback in session.active_playbacks.values():
		if playback != null and playback.has_active_tee_dispersion():
			return true
	return false


func _physical_round_complete() -> bool:
	if controller == null:
		return false
	for group_id in ["group_1", "group_2"]:
		if int(controller.traffic.group_hole(group_id)) != 0:
			return false
		if not controller.active_event(group_id).is_empty():
			return false
		var group = controller.living_course.population.group_by_id(group_id)
		if group == null or str(group.status) != "FINISHED":
			return false
	return true


func _display_group_name(group_id: String) -> String:
	if group_id == "group_1":
		return "GROUP 1 — Carl & Bill"
	if group_id == "group_2":
		return "GROUP 2 — Carl & Carl"
	return group_id.to_upper()


func _on_previous_group() -> void:
	cycle_group(-1)


func _on_next_group() -> void:
	cycle_group(1)
