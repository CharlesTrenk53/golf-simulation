extends Node3D

# POC-26E/F: Launchable Living-Course Participate Demo
# ----------------------------------------------------
# Extends the proven POC-25 spectator experience into direct participation. The
# player is one normal member of group_1. Between player turns this remains a
# spectator view; on the player's authoritative turn a compact Club -> Aim ->
# Shot browser appears. Committing a selection submits only the original
# authority-issued candidate index. Simulation, traffic, shot execution, scoring,
# and outcomes remain outside this scene.

const CourseDefinition = preload("res://simulation/course_definition.gd")
const ShotProgressiveLivingCourseController = preload("res://simulation/shot_progressive_living_course_controller.gd")
const SpectatorCourseWorld = preload("res://scenes/spectator_course_world.gd")
const SpectatorPopulationView = preload("res://scenes/spectator_population_view.gd")
const ParticipateSpectatorSession = preload("res://scenes/participate_spectator_session.gd")
const ParticipateFocusController = preload("res://scenes/participate_focus_controller.gd")
const ParticipateChoiceBrowser = preload("res://scenes/participate_choice_browser.gd")
const Golfer = preload("res://scenes/golfer.gd")

@export var auto_advance: bool = true
@export var simulation_speed: float = 28.0
@export var max_real_step_seconds: float = 0.05
@export var camera_offset: Vector3 = Vector3(34.0, 30.0, 38.0)
@export var camera_lerp_speed: float = 4.0
@export var player_seed: int = 27601
@export var other_seed: int = 27701

var controller = null
var course_world = null
var population_view = null
var session = null
var focus_controller = null
var choice_browser = ParticipateChoiceBrowser.new()
var initialized: bool = false
var golfer_nodes: Array = []
var current_decision_id: String = ""

var spectator_camera: Camera3D = null
var group_label: Label = null
var status_label: Label = null
var shot_label: Label = null
var members_label: Label = null
var clock_label: Label = null
var turn_alert_label: Label = null
var decision_panel: PanelContainer = null
var decision_title: Label = null
var situation_label: Label = null
var club_select: OptionButton = null
var aim_select: OptionButton = null
var shot_select: OptionButton = null
var commit_button: Button = null
var choice_count_label: Label = null


func _ready() -> void:
	initialize_demo()


func _process(delta: float) -> void:
	if not initialized:
		return
	if session != null:
		session.advance_visuals(delta)
	if auto_advance and session != null and not _physical_round_complete():
		var real_step: float = clampf(delta, 0.0, max_real_step_seconds)
		if real_step > 0.0 and not session.presentation_busy():
			session.advance_time(real_step * maxf(simulation_speed, 0.01), true)
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
	elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
		if decision_panel != null and decision_panel.visible:
			_commit_selected_choice()
			get_viewport().set_input_as_handled()


func initialize_demo() -> bool:
	if initialized:
		return true
	var course = CourseDefinition.load_json("res://data/courses/poc12_proving_course.json")
	if course == null or course.hole_count() != 3:
		return false

	controller = ShotProgressiveLivingCourseController.new()
	if not controller.configure(course):
		return false

	var player = _make_golfer(Golfer.GolferProfile.CAREFUL_CARL)
	var partner = _make_golfer(Golfer.GolferProfile.WILD_BILL)
	var other_a = _make_golfer(Golfer.GolferProfile.RECKLESS_RICK)
	var other_b = _make_golfer(Golfer.GolferProfile.WILD_BILL)
	if not controller.add_group("group_1", [player, partner], "default", 0, player_seed):
		return false
	if not controller.add_group("group_2", [other_a, other_b], "default", -1, other_seed):
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

	session = ParticipateSpectatorSession.new()
	session.name = "ParticipateSpectatorSession"
	add_child(session)
	if not session.configure(controller, course_world, population_view):
		return false
	var started: Dictionary = session.start_session()
	if started.is_empty():
		return false

	focus_controller = ParticipateFocusController.new()
	focus_controller.name = "ParticipateFocusController"
	add_child(focus_controller)
	if not focus_controller.configure(session, population_view):
		return false
	focus_controller.select_group("group_1")

	_build_environment()
	_build_hud()
	initialized = true
	_refresh_presentation(1.0, true)
	return true


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


func snapshot() -> Dictionary:
	var presentation: Dictionary = focus_controller.presentation_snapshot() if focus_controller != null else {}
	return {
		"initialized": initialized,
		"simulation_time_seconds": controller.current_time_seconds if controller != null else 0.0,
		"round_complete": _physical_round_complete(),
		"focus": presentation,
		"decision_visible": decision_panel.visible if decision_panel != null else false,
		"decision_id": current_decision_id,
		"choice_browser": choice_browser.snapshot(),
		"camera_position": spectator_camera.global_position if spectator_camera != null else Vector3.ZERO
	}


func selected_candidate_index() -> int:
	if shot_select == null or shot_select.item_count <= 0 or shot_select.selected < 0:
		return -1
	return int(shot_select.get_item_metadata(shot_select.selected))


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
	spectator_camera.name = "ParticipateCamera"
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
	canvas.name = "ParticipateHUD"
	add_child(canvas)

	var info_panel := PanelContainer.new()
	info_panel.name = "InfoPanel"
	info_panel.offset_left = 20.0
	info_panel.offset_top = 20.0
	info_panel.offset_right = 485.0
	info_panel.offset_bottom = 300.0
	canvas.add_child(info_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	info_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "LIVING COURSE — PARTICIPATE"
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

	var group_buttons := HBoxContainer.new()
	group_buttons.add_theme_constant_override("separation", 8)
	vbox.add_child(group_buttons)
	var previous := Button.new()
	previous.text = "◀ Previous Group"
	previous.pressed.connect(func(): cycle_group(-1))
	group_buttons.add_child(previous)
	var next := Button.new()
	next.text = "Next Group ▶"
	next.pressed.connect(func(): cycle_group(1))
	group_buttons.add_child(next)

	turn_alert_label = Label.new()
	turn_alert_label.offset_left = 20.0
	turn_alert_label.offset_top = 312.0
	turn_alert_label.offset_right = 485.0
	turn_alert_label.offset_bottom = 350.0
	turn_alert_label.add_theme_font_size_override("font_size", 18)
	canvas.add_child(turn_alert_label)

	decision_panel = PanelContainer.new()
	decision_panel.name = "DecisionPanel"
	decision_panel.offset_left = 20.0
	decision_panel.offset_top = 360.0
	decision_panel.offset_right = 520.0
	decision_panel.offset_bottom = 690.0
	decision_panel.visible = false
	canvas.add_child(decision_panel)

	var decision_margin := MarginContainer.new()
	decision_margin.add_theme_constant_override("margin_left", 14)
	decision_margin.add_theme_constant_override("margin_top", 12)
	decision_margin.add_theme_constant_override("margin_right", 14)
	decision_margin.add_theme_constant_override("margin_bottom", 12)
	decision_panel.add_child(decision_margin)

	var decision_box := VBoxContainer.new()
	decision_box.add_theme_constant_override("separation", 8)
	decision_margin.add_child(decision_box)

	decision_title = Label.new()
	decision_title.add_theme_font_size_override("font_size", 19)
	decision_box.add_child(decision_title)

	situation_label = Label.new()
	situation_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	decision_box.add_child(situation_label)

	club_select = OptionButton.new()
	club_select.tooltip_text = "Choose club"
	club_select.item_selected.connect(_on_club_selected)
	decision_box.add_child(_labeled_control("Club", club_select))

	aim_select = OptionButton.new()
	aim_select.tooltip_text = "Choose aim lane"
	aim_select.item_selected.connect(_on_aim_selected)
	decision_box.add_child(_labeled_control("Aim", aim_select))

	shot_select = OptionButton.new()
	shot_select.tooltip_text = "Choose shot shape / trajectory / technique"
	decision_box.add_child(_labeled_control("Shot", shot_select))

	choice_count_label = Label.new()
	choice_count_label.add_theme_font_size_override("font_size", 12)
	decision_box.add_child(choice_count_label)

	commit_button = Button.new()
	commit_button.text = "PLAY SHOT  (Enter)"
	commit_button.pressed.connect(_commit_selected_choice)
	decision_box.add_child(commit_button)

	var help := Label.new()
	help.text = "TAB / ← → switch groups   •   1 / 2 jump to group   •   Enter commits selected shot"
	help.offset_left = 20.0
	help.offset_top = 705.0
	help.offset_right = 760.0
	help.offset_bottom = 735.0
	help.add_theme_font_size_override("font_size", 12)
	canvas.add_child(help)


func _labeled_control(label_text: String, control: Control) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(70.0, 0.0)
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row


func _refresh_presentation(delta: float, snap_camera: bool = false) -> void:
	if focus_controller == null:
		return
	var presentation: Dictionary = focus_controller.presentation_snapshot()
	if presentation.is_empty():
		return
	_update_hud(presentation)
	_update_decision_ui(presentation)
	_update_turn_alert()
	_update_camera(presentation.get("camera_target", Vector3.ZERO), delta, snap_camera)


func _update_hud(presentation: Dictionary) -> void:
	var group_id: String = str(presentation.get("group_id", ""))
	var status: String = str(presentation.get("status", ""))
	var hole_number: int = int(presentation.get("hole_number", 0))
	group_label.text = "%s  •  Hole %d" % [_display_group_name(group_id), hole_number]

	if status == "DECIDING":
		status_label.text = "YOUR TURN — course remains live"
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
	if phase == "AWAITING_DECISION":
		shot_label.text = "YOU: %s — %.1f yd — %s" % [
			str(shot.get("lie", "")),
			float(shot.get("remaining_distance_yards", 0.0)),
			str(shot.get("golfer_name", "Golfer"))
		]
	elif phase == "ACTIVE" or phase == "NEXT":
		var prefix: String = "NOW" if phase == "ACTIVE" else "NEXT"
		shot_label.text = "%s: %s — %s | %s" % [
			prefix,
			str(shot.get("golfer_name", "Golfer")),
			str(shot.get("club_name", shot.get("club_id", ""))),
			str(shot.get("intent", ""))
		]
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
		if seen > 0:
			line += "  •  %d stroke%s shown" % [seen, "" if seen == 1 else "s"]
		member_lines.append(line)
	members_label.text = "\n".join(member_lines)

	var sim_seconds: float = controller.current_time_seconds if controller != null else 0.0
	clock_label.text = "Course clock: %02d:%02d" % [int(sim_seconds) / 60, int(sim_seconds) % 60]


func _update_decision_ui(presentation: Dictionary) -> void:
	var decision_id: String = str(presentation.get("decision_id", ""))
	var is_player_group: bool = str(presentation.get("group_id", "")) == "group_1"
	var playable: bool = is_player_group and str(presentation.get("mode", "")) == "PARTICIPATE" and not decision_id.is_empty()
	decision_panel.visible = playable
	if not playable:
		current_decision_id = ""
		choice_browser.clear()
		return
	if decision_id == current_decision_id:
		return

	current_decision_id = decision_id
	var choices: Array = presentation.get("choices", [])
	if not choice_browser.load_choices(choices):
		decision_panel.visible = false
		return
	var situation: Dictionary = presentation.get("situation", {})
	decision_title.text = "YOUR SHOT — %s" % str(presentation.get("shot", {}).get("golfer_name", "Golfer"))
	situation_label.text = "Hole %d • Shot %d • %s • %.1f yd" % [
		int(situation.get("hole_number", presentation.get("hole_number", 0))),
		int(situation.get("shot_number", 0)),
		str(situation.get("surface", "")),
		float(situation.get("remaining_distance_yards", 0.0))
	]
	choice_count_label.text = "%d authoritative choices — browsed without pruning" % choice_browser.candidate_count()
	_populate_clubs(choice_browser.default_path())


func _populate_clubs(default_path: Dictionary = {}) -> void:
	club_select.clear()
	var desired: String = str(default_path.get("club_key", ""))
	var desired_index: int = 0
	for option_value in choice_browser.club_options():
		var option: Dictionary = option_value
		var index: int = club_select.item_count
		club_select.add_item(str(option.get("label", "Club")))
		club_select.set_item_metadata(index, str(option.get("key", "")))
		if str(option.get("key", "")) == desired:
			desired_index = index
	if club_select.item_count > 0:
		club_select.select(desired_index)
		_populate_aims(default_path)


func _populate_aims(default_path: Dictionary = {}) -> void:
	aim_select.clear()
	shot_select.clear()
	if club_select.item_count <= 0 or club_select.selected < 0:
		return
	var club_key: String = str(club_select.get_item_metadata(club_select.selected))
	var desired: String = str(default_path.get("aim_key", ""))
	var desired_index: int = 0
	for option_value in choice_browser.aim_options(club_key):
		var option: Dictionary = option_value
		var index: int = aim_select.item_count
		aim_select.add_item(str(option.get("label", "Aim")))
		aim_select.set_item_metadata(index, str(option.get("key", "")))
		if str(option.get("key", "")) == desired:
			desired_index = index
	if aim_select.item_count > 0:
		aim_select.select(desired_index)
		_populate_shots(default_path)


func _populate_shots(default_path: Dictionary = {}) -> void:
	shot_select.clear()
	if club_select.item_count <= 0 or aim_select.item_count <= 0 or club_select.selected < 0 or aim_select.selected < 0:
		return
	var club_key: String = str(club_select.get_item_metadata(club_select.selected))
	var aim_key: String = str(aim_select.get_item_metadata(aim_select.selected))
	var desired: int = int(default_path.get("candidate_index", -1))
	var desired_index: int = 0
	for option_value in choice_browser.shot_options(club_key, aim_key):
		var option: Dictionary = option_value
		var index: int = shot_select.item_count
		var candidate_index: int = int(option.get("candidate_index", -1))
		shot_select.add_item(str(option.get("label", "Shot")))
		shot_select.set_item_metadata(index, candidate_index)
		if candidate_index == desired:
			desired_index = index
	if shot_select.item_count > 0:
		shot_select.select(desired_index)


func _on_club_selected(_index: int) -> void:
	_populate_aims()


func _on_aim_selected(_index: int) -> void:
	_populate_shots()


func _commit_selected_choice() -> void:
	if session == null or focus_controller == null or decision_panel == null or not decision_panel.visible:
		return
	var candidate_index: int = selected_candidate_index()
	if candidate_index < 0:
		return
	var group_id: String = focus_controller.selected_group_id()
	var result: Dictionary = session.submit_human_choice(group_id, candidate_index, true)
	if bool(result.get("played", false)):
		current_decision_id = ""
		choice_browser.clear()
		decision_panel.visible = false
	_refresh_presentation(0.0)


func _update_turn_alert() -> void:
	if turn_alert_label == null or session == null:
		return
	var player_decision: Dictionary = session.pending_human_decision("group_1")
	if player_decision.is_empty():
		turn_alert_label.text = ""
		return
	if focus_controller != null and focus_controller.selected_group_id() == "group_1":
		turn_alert_label.text = "YOUR TURN — choose a shot below. The rest of the course is still live."
	else:
		turn_alert_label.text = "YOUR TURN in Group 1 — press 1 to return to your golfer."


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


func _physical_round_complete() -> bool:
	if controller == null:
		return false
	for group_id in ["group_1", "group_2"]:
		if int(controller.traffic.group_hole(group_id)) != 0:
			return false
		if controller.live_sessions.has(group_id):
			return false
		if controller.blocked_transitions.has(group_id):
			return false
		var group = controller.living_course.population.group_by_id(group_id)
		if group == null or str(group.status) != "FINISHED":
			return false
	return true


func _display_group_name(group_id: String) -> String:
	if group_id == "group_1":
		return "GROUP 1 — YOU & WILD BILL"
	if group_id == "group_2":
		return "GROUP 2 — RICK & BILL"
	return group_id.to_upper()
