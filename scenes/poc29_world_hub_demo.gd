extends "res://scenes/poc28_persistent_engagement_demo.gd"

# POC-29 Manual Acceptance Demo — Golf World Hub & Activity Selection
# -------------------------------------------------------------------
# Starts with the persistent golfer in the living world rather than assuming that
# the next action is a round. ROUND and PRACTICE are selected/launched through the
# POC-29 hub contracts. The existing POC-28 participation/presentation stack stays
# downstream of the same authoritative living-course controller.

const POC29Course = preload("res://simulation/poc27_eighteen_hole_course.gd")
const POC29WorldSession = preload("res://simulation/player_world_session.gd")
const POC29WorldHub = preload("res://simulation/player_world_hub.gd")
const POC29ActivityContract = preload("res://simulation/player_activity_contract.gd")
const POC29CourseWorld = preload("res://scenes/spectator_course_world.gd")
const POC29PopulationView = preload("res://scenes/spectator_population_view.gd")
const POC29ParticipateSession = preload("res://scenes/poc28_participate_session.gd")
const POC29FocusController = preload("res://scenes/participate_focus_controller.gd")
const POC29Golfer = preload("res://scenes/golfer.gd")
const PuttingProficiencyModel = preload("res://simulation/putting_proficiency_model.gd")
const PuttingExecutionModel = preload("res://simulation/putting_execution_model.gd")

const PRACTICE_REPETITIONS := 30
const PRACTICE_DURATION_SECONDS := 600.0
const PRACTICE_DISTANCE_FEET := 20.0
const PRACTICE_QUALITY := 0.80

var world_hub = null
var practice_action: Button = null
var last_completed_practice: Dictionary = {}
var last_result_activity: String = ""


func initialize_demo() -> bool:
	if initialized:
		return true
	var course = POC29Course.build()
	if course == null or course.hole_count() != 18:
		return false

	persistent_player = _make_golfer(POC29Golfer.GolferProfile.CAREFUL_CARL)
	world_session = POC29WorldSession.new()
	world_session.name = "PlayerWorldSession"
	add_child(world_session)
	if not world_session.configure(persistent_player, course, starting_world_day, starting_world_time_seconds):
		return false
	controller = world_session.controller

	world_hub = POC29WorldHub.new()
	if not world_hub.configure(world_session):
		return false

	# The player begins outside an activity. The course is already alive with the
	# same ordinary autonomous population used by the POC-28 participation proof.
	engagement_state = STATE_WORLD
	active_player_group_id = ""
	round_number = 0
	last_completed_round.clear()
	last_completed_practice.clear()
	last_result_activity = ""
	if not _add_initial_world_population():
		return false

	course_world = POC29CourseWorld.new()
	course_world.name = "CourseWorld"
	add_child(course_world)
	if not course_world.configure(course):
		return false

	population_view = POC29PopulationView.new()
	population_view.name = "PopulationView"
	add_child(population_view)
	if not population_view.configure(course_world, controller):
		return false

	session = POC29ParticipateSession.new()
	session.name = "POC29ParticipateSession"
	add_child(session)
	if not session.configure(controller, course_world, population_view):
		return false
	var started: Dictionary = session.start_session()
	if started.is_empty() or str(started.get("group_id", "")) != "group_2":
		return false

	focus_controller = POC29FocusController.new()
	focus_controller.name = "ParticipateFocusController"
	add_child(focus_controller)
	if not focus_controller.configure(session, population_view):
		return false
	focus_controller.select_group("group_2")

	_build_environment()
	_build_hud()
	initialized = true
	_sync_world_session_from_controller()
	_refresh_presentation(1.0, true)
	_refresh_world_hub_text()
	if engagement_panel != null:
		engagement_panel.visible = true
	return true


func snapshot() -> Dictionary:
	var result: Dictionary = super.snapshot()
	result["poc29_hub"] = world_hub.context() if world_hub != null else {}
	result["last_completed_practice"] = last_completed_practice.duplicate(true)
	result["last_result_activity"] = last_result_activity
	return result


func _build_hud() -> void:
	super._build_hud()
	if engagement_action == null:
		return
	engagement_action.text = "PLAY ROUND  (Enter)"
	practice_action = Button.new()
	practice_action.name = "PracticeAction"
	practice_action.text = "PRACTICE PUTTING  (P)"
	practice_action.pressed.connect(_on_practice_action)
	engagement_action.get_parent().add_child(practice_action)


func _unhandled_input(event: InputEvent) -> void:
	if not initialized or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if engagement_state == STATE_RESULTS:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			_return_to_world()
			get_viewport().set_input_as_handled()
		return
	if engagement_state == STATE_WORLD:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			begin_round_activity()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_P:
			begin_practice_activity()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_TAB or event.keycode == KEY_RIGHT:
			cycle_group(1)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_LEFT:
			cycle_group(-1)
			get_viewport().set_input_as_handled()
		return
	super._unhandled_input(event)


func begin_round_activity() -> bool:
	if engagement_state != STATE_WORLD or world_hub == null:
		return false
	var next_round: int = round_number + 1
	var group_id: String = "player_round_%d" % next_round
	var partner_a = _make_golfer(POC29Golfer.GolferProfile.WILD_BILL)
	var partner_b = _make_golfer(POC29Golfer.GolferProfile.RECKLESS_RICK)
	var partner_c = _make_golfer(POC29Golfer.GolferProfile.CAREFUL_CARL)
	var selection: Dictionary = world_hub.select_activity(POC29ActivityContract.ACTIVITY_ROUND, {
		"group_id": group_id,
		"other_golfers": [partner_a, partner_b, partner_c],
		"tee_id": "default",
		"player_member_index": 0,
		"seed_base": player_seed + next_round * 1000
	})
	if not bool(selection.get("accepted", false)):
		_show_hub_error("Round is not available: %s" % str(selection.get("reason", "UNKNOWN")))
		return false
	var launched: Dictionary = world_hub.launch_selected_activity(selection)
	if not bool(launched.get("launched", false)):
		_show_hub_error("Could not enter round: %s" % str(launched.get("reason", "UNKNOWN")))
		return false

	var entry: Dictionary = launched.get("entry", {})
	round_number = int(entry.get("sequence", next_round))
	active_player_group_id = str(entry.get("group_id", group_id))
	engagement_state = STATE_PLAYING
	last_result_activity = ""
	if not _attach_group_visual(active_player_group_id):
		_show_hub_error("Round entered authority but presentation could not attach the group.")
		return false
	if focus_controller != null:
		focus_controller.select_group(active_player_group_id)
	if session != null:
		# Normal FIFO/traffic authority decides whether this releases the player or
		# another already-waiting world group. No player-special tee bypass occurs.
		session.attempt_release_next(true)
	if engagement_panel != null:
		engagement_panel.visible = false
	if practice_action != null:
		practice_action.visible = false
	current_decision_id = ""
	choice_browser.clear()
	_sync_world_session_from_controller()
	_refresh_presentation(0.0, true)
	return true


func begin_practice_activity() -> bool:
	if engagement_state != STATE_WORLD or world_hub == null or persistent_player == null:
		return false
	var selection: Dictionary = world_hub.select_activity(POC29ActivityContract.ACTIVITY_PRACTICE, {
		"total_repetitions": PRACTICE_REPETITIONS,
		"focus": {3: 1.0},
		"quality": PRACTICE_QUALITY,
		"duration_seconds": PRACTICE_DURATION_SECONDS
	})
	if not bool(selection.get("accepted", false)):
		_show_hub_error("Practice is not available: %s" % str(selection.get("reason", "UNKNOWN")))
		return false
	var launched: Dictionary = world_hub.launch_selected_activity(selection)
	if not bool(launched.get("launched", false)):
		_show_hub_error("Could not begin practice: %s" % str(launched.get("reason", "UNKNOWN")))
		return false

	# Catch presentation up to the moment the golfer leaves the course view. The
	# 10-minute practice then advances the same authoritative world off-screen.
	if session != null:
		session.drain_visuals_immediate()
	var observation: Dictionary = _modeled_putting_practice_observation(PRACTICE_REPETITIONS)
	var returned: Dictionary = world_hub.return_to_world("COMPLETE", {
		"observations": {3: observation}
	})
	if not bool(returned.get("returned", false)) or not bool(returned.get("completed", false)):
		_show_hub_error("Practice could not complete: %s" % str(returned.get("reason", "UNKNOWN")))
		return false
	last_completed_practice = returned.get("finalization", {}).get("practice", {}).duplicate(true)
	last_result_activity = POC29ActivityContract.ACTIVITY_PRACTICE
	engagement_state = STATE_RESULTS
	_sync_world_session_from_controller()
	if population_view != null:
		population_view.sync_from_authority()
	_refresh_presentation(0.0, true)
	_show_practice_results(last_completed_practice)
	return true


func _modeled_putting_practice_observation(repetitions: int) -> Dictionary:
	var planned := {
		"signature": "POC29_20FT_STRAIGHT_PRACTICE",
		"distance_feet": PRACTICE_DISTANCE_FEET,
		"intended_distance_feet": PRACTICE_DISTANCE_FEET,
		"aim_offset_feet": 0.0
	}
	var proficiency_model = PuttingProficiencyModel.new()
	var execution_model = PuttingExecutionModel.new()
	var proficiency: Dictionary = proficiency_model.assess(persistent_player, planned)
	var line_sigma: float = maxf(float(proficiency.get("line_sigma_inches", 1.0)), 0.05)
	var pace_sigma: float = maxf(float(proficiency.get("pace_sigma_feet", 1.0)), 0.05)
	var line_sum: float = 0.0
	var pace_sum: float = 0.0
	var score_sum: float = 0.0
	var reps: int = maxi(repetitions, 1)
	var seed_offset: int = world_session.practice_sequence * 1000 if world_session != null else 0
	for index in range(reps):
		var realized: Dictionary = execution_model.realize(planned, proficiency, 29000 + seed_offset + index)
		var line_error: float = float(realized.get("line_error_inches", 0.0))
		var pace_error: float = float(realized.get("pace_error_feet", 0.0))
		line_sum += line_error
		pace_sum += pace_error
		var line_cost: float = abs(line_error) / (line_sigma * 2.5)
		var pace_cost: float = abs(pace_error) / (pace_sigma * 2.5)
		score_sum += clampf(100.0 - 45.0 * line_cost - 45.0 * pace_cost, 10.0, 100.0)
	return {
		"execution_score": score_sum / float(reps),
		"lateral_error": line_sum / float(reps),
		"distance_error": pace_sum / float(reps),
		"sample_count": reps,
		"distance_feet": PRACTICE_DISTANCE_FEET,
		"execution_reliability": float(proficiency.get("execution_reliability", 0.0)),
		"line_sigma_inches": line_sigma,
		"pace_sigma_feet": pace_sigma
	}


func _maybe_finalize_player_round() -> void:
	if not _player_round_authority_complete():
		return
	if session != null and session.group_presentation_busy(active_player_group_id):
		return
	_sync_world_session_from_controller()
	var returned: Dictionary = world_hub.return_to_world() if world_hub != null else {}
	if not bool(returned.get("returned", false)) or not bool(returned.get("completed", false)):
		return
	last_completed_round = returned.get("finalization", {}).get("round", {}).duplicate(true)
	last_result_activity = POC29ActivityContract.ACTIVITY_ROUND
	engagement_state = STATE_RESULTS
	if decision_panel != null:
		decision_panel.visible = false
	if practice_action != null:
		practice_action.visible = false
	_show_round_results(last_completed_round)


func _show_practice_results(archive: Dictionary) -> void:
	if engagement_panel == null:
		return
	var observation: Dictionary = archive.get("observations", {}).get(3, {})
	var evidence: Dictionary = archive.get("development_evidence", {})
	var before: Dictionary = archive.get("development_before", {})
	var after: Dictionary = archive.get("development_after", {})
	engagement_title.text = "PUTTING PRACTICE COMPLETE"
	engagement_body.text = "%d modeled putts from %.0f ft\nPractice time: %.0f minutes\nExecution score: %.1f\nMean line bias: %+.2f in\nMean pace bias: %+.2f ft\n\nUseful development evidence: %d\nExperience-only reps: %d\nCourse clock: %s\n\nDurable development\n%s" % [
		int(observation.get("sample_count", 0)),
		float(observation.get("distance_feet", PRACTICE_DISTANCE_FEET)),
		float(archive.get("duration_seconds", 0.0)) / 60.0,
		float(observation.get("execution_score", 0.0)),
		float(observation.get("lateral_error", 0.0)),
		float(observation.get("distance_error", 0.0)),
		int(evidence.get("total_evidence", 0)),
		int(evidence.get("total_experience_only", 0)),
		_clock_label(world_session.world_time_seconds),
		_development_delta_text(before, after)
	]
	engagement_action.text = "RETURN TO WORLD  (Enter)"
	if practice_action != null:
		practice_action.visible = false
	engagement_panel.visible = true


func _return_to_world() -> void:
	if engagement_state != STATE_RESULTS:
		return
	if last_result_activity == POC29ActivityContract.ACTIVITY_ROUND and not active_player_group_id.is_empty():
		_remove_group_visual(active_player_group_id)
	active_player_group_id = ""
	last_result_activity = ""
	engagement_state = STATE_WORLD
	_select_first_available_world_group()
	_refresh_world_hub_text()
	engagement_action.text = "PLAY ROUND  (Enter)"
	if practice_action != null:
		practice_action.text = "PRACTICE PUTTING  (P)"
		practice_action.visible = true
	engagement_panel.visible = true


func _begin_next_round() -> void:
	begin_round_activity()


func _on_engagement_action() -> void:
	if engagement_state == STATE_RESULTS:
		_return_to_world()
	elif engagement_state == STATE_WORLD:
		begin_round_activity()


func _on_practice_action() -> void:
	if engagement_state == STATE_WORLD:
		begin_practice_activity()


func _refresh_world_hub_text() -> void:
	if engagement_state != STATE_WORLD or engagement_panel == null or world_hub == null:
		return
	var context: Dictionary = world_hub.context()
	var abilities: Dictionary = context.get("abilities", {})
	engagement_title.text = "YOUR GOLF WORLD"
	engagement_body.text = "%s\n\nChoose what to do next. The course keeps living around you.\n\nRounds played: %d\nPractice sessions: %d\nPractice repetitions: %d\nWorld day: %d\nCourse clock: %s\nGroups in world: %d\n\nCurrent durable ability\nDrive %.2f  •  Approach %.2f\nShort game %.2f  •  Putting %.2f\n\nPLAY ROUND joins an ordinary group through normal FIFO/traffic authority.\nPRACTICE PUTTING runs a modeled 30-putt session while the same world clock advances." % [
		str(context.get("golfer_name", "Golfer")),
		int(context.get("career_rounds_played", 0)),
		int(context.get("completed_practices", 0)),
		int(context.get("total_practice_repetitions", 0)),
		int(context.get("day", 0)),
		_clock_label(float(context.get("world_time_seconds", 0.0))),
		int(context.get("population", {}).get("group_count", 0)),
		float(abilities.get("driving", persistent_player.driving)),
		float(abilities.get("approach", persistent_player.approach)),
		float(abilities.get("short_game", persistent_player.short_game)),
		float(abilities.get("putting", persistent_player.putting))
	]
	engagement_action.text = "PLAY ROUND  (Enter)"
	if practice_action != null:
		practice_action.visible = true


func _show_hub_error(message: String) -> void:
	if engagement_panel == null:
		return
	engagement_title.text = "YOUR GOLF WORLD"
	engagement_body.text = message
	engagement_panel.visible = true
