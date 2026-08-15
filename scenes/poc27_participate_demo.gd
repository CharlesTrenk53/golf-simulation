extends "res://scenes/participate_demo.gd"

# POC-27 Manual Acceptance Demo
# -----------------------------
# Reuses the proven POC-26 Participate presentation and input stack unchanged,
# but swaps in the POC-27 18-hole course and a populated four-group living day.
# Group 1 is the player's ordinary foursome. Groups 2-4 are autonomous twosomes.
# No player-only simulation, traffic, scoring, or presentation authority is added.

const POC27Course = preload("res://simulation/poc27_eighteen_hole_course.gd")
const POC27Controller = preload("res://simulation/shot_progressive_living_course_controller.gd")
const POC27World = preload("res://scenes/spectator_course_world.gd")
const POC27PopulationView = preload("res://scenes/spectator_population_view.gd")
const POC27Session = preload("res://scenes/participate_spectator_session.gd")
const POC27FocusController = preload("res://scenes/participate_focus_controller.gd")
const POC27Golfer = preload("res://scenes/golfer.gd")
const ParticipatePacingController = preload("res://scenes/participate_pacing_controller.gd")

const GROUP_IDS := ["group_1", "group_2", "group_3", "group_4"]
const HUMAN_MEMBER := 0

@export var compress_idle_waits: bool = true

var participate_pacing = ParticipatePacingController.new()


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
			var advanced: bool = false
			if compress_idle_waits:
				var pacing: Dictionary = participate_pacing.idle_advance(controller, "group_1")
				if str(pacing.get("mode", "")) == ParticipatePacingController.MODE_FAST_FORWARD:
					session.advance_time(float(pacing.get("delta_seconds", 0.0)), true)
					advanced = true
				elif str(pacing.get("mode", "")) == ParticipatePacingController.MODE_REALTIME:
					# A ready human decision must remain stable, but the living course
					# still advances normally while the player thinks.
					session.advance_time(real_step * maxf(simulation_speed, 0.01), true)
					advanced = true
			if not advanced:
				session.advance_time(real_step * maxf(simulation_speed, 0.01), true)
	_refresh_presentation(delta)


func initialize_demo() -> bool:
	if initialized:
		return true

	var course = POC27Course.build()
	if course == null or course.hole_count() != 18:
		return false

	controller = POC27Controller.new()
	if not controller.configure(course):
		return false

	# Same population shape used by the POC-27F closure proof: one ordinary
	# human foursome plus three autonomous twosomes sharing one course authority.
	var player = _make_golfer(POC27Golfer.GolferProfile.CAREFUL_CARL)
	var partner_a = _make_golfer(POC27Golfer.GolferProfile.WILD_BILL)
	var partner_b = _make_golfer(POC27Golfer.GolferProfile.RECKLESS_RICK)
	var partner_c = _make_golfer(POC27Golfer.GolferProfile.CAREFUL_CARL)
	if not controller.add_group("group_1", [player, partner_a, partner_b, partner_c], "default", HUMAN_MEMBER, player_seed):
		return false

	var auto_1a = _make_golfer(POC27Golfer.GolferProfile.WILD_BILL)
	var auto_1b = _make_golfer(POC27Golfer.GolferProfile.RECKLESS_RICK)
	if not controller.add_group("group_2", [auto_1a, auto_1b], "default", -1, other_seed):
		return false

	var auto_2a = _make_golfer(POC27Golfer.GolferProfile.RECKLESS_RICK)
	var auto_2b = _make_golfer(POC27Golfer.GolferProfile.CAREFUL_CARL)
	if not controller.add_group("group_3", [auto_2a, auto_2b], "default", -1, other_seed + 100):
		return false

	var auto_3a = _make_golfer(POC27Golfer.GolferProfile.CAREFUL_CARL)
	var auto_3b = _make_golfer(POC27Golfer.GolferProfile.WILD_BILL)
	if not controller.add_group("group_4", [auto_3a, auto_3b], "default", -1, other_seed + 200):
		return false

	course_world = POC27World.new()
	course_world.name = "CourseWorld"
	add_child(course_world)
	if not course_world.configure(course):
		return false

	population_view = POC27PopulationView.new()
	population_view.name = "PopulationView"
	add_child(population_view)
	if not population_view.configure(course_world, controller):
		return false

	session = POC27Session.new()
	session.name = "ParticipateSpectatorSession"
	add_child(session)
	if not session.configure(controller, course_world, population_view):
		return false
	var started: Dictionary = session.start_session()
	if started.is_empty() or str(started.get("group_id", "")) != "group_1":
		return false

	focus_controller = POC27FocusController.new()
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
	elif event.keycode == KEY_3:
		select_group("group_3")
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_4:
		select_group("group_4")
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
		if decision_panel != null and decision_panel.visible:
			_commit_selected_choice()
			get_viewport().set_input_as_handled()


func _build_hud() -> void:
	super._build_hud()
	var canvas = get_node_or_null("ParticipateHUD")
	if canvas == null:
		return
	for child in canvas.get_children():
		if child is Label and str(child.text).begins_with("TAB /"):
			child.text = "TAB / ← → switch groups   •   1 / 2 / 3 / 4 jump to group   •   Enter commits selected shot"


func _physical_round_complete() -> bool:
	if controller == null:
		return false
	for group_id in GROUP_IDS:
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
	match group_id:
		"group_1": return "GROUP 1 — YOU, BILL, RICK & CARL"
		"group_2": return "GROUP 2 — BILL & RICK"
		"group_3": return "GROUP 3 — RICK & CARL"
		"group_4": return "GROUP 4 — CARL & BILL"
	return group_id.to_upper()
