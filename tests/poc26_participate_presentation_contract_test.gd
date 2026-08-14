extends SceneTree

const CourseDefinition = preload("res://simulation/course_definition.gd")
const ShotProgressiveLivingCourseController = preload("res://simulation/shot_progressive_living_course_controller.gd")
const SpectatorCourseWorld = preload("res://scenes/spectator_course_world.gd")
const SpectatorPopulationView = preload("res://scenes/spectator_population_view.gd")
const ParticipateSpectatorSession = preload("res://scenes/participate_spectator_session.gd")
const ParticipateFocusController = preload("res://scenes/participate_focus_controller.gd")
const Golfer = preload("res://scenes/golfer.gd")

var failures: int = 0
var created_nodes: Array = []


func _init() -> void:
	print("POC-26E: spectator-to-participate presentation contract")
	var course = CourseDefinition.load_json("res://data/courses/poc12_proving_course.json")
	_assert_true(course != null, "three-hole proving course loads")
	if course == null:
		_finish()
		return

	var runtime = ShotProgressiveLivingCourseController.new()
	_assert_true(runtime.configure(course), "shot-progressive authority configures")

	var player_golfers: Array = [
		_new_golfer(Golfer.GolferProfile.CAREFUL_CARL),
		_new_golfer(Golfer.GolferProfile.WILD_BILL)
	]
	var other_golfers: Array = [
		_new_golfer(Golfer.GolferProfile.RECKLESS_RICK),
		_new_golfer(Golfer.GolferProfile.CAREFUL_CARL)
	]
	_assert_true(runtime.add_group("player_group", player_golfers, "default", 0, 26601), "player group joins normal live course")
	_assert_true(runtime.add_group("other_group", other_golfers, "default", -1, 26701), "other group joins same live course")

	var world = SpectatorCourseWorld.new()
	get_root().add_child(world)
	created_nodes.append(world)
	_assert_true(world.configure(course), "POC-25 spectator course world is reused")

	var population_view = SpectatorPopulationView.new()
	get_root().add_child(population_view)
	created_nodes.append(population_view)
	_assert_true(population_view.configure(world, runtime), "POC-25 spectator population view accepts POC-26 live authority")
	_assert_equal(population_view.group_visuals.size(), 2, "both living groups have spectator visuals")

	var session = ParticipateSpectatorSession.new()
	get_root().add_child(session)
	created_nodes.append(session)
	_assert_true(session.configure(runtime, world, population_view), "participate session bridges live authority to spectator visuals")
	var started: Dictionary = session.start_session()
	_assert_true(not started.is_empty(), "participate spectator session starts")
	_assert_equal(str(started.get("group_id", "")), "player_group", "FIFO player group starts first")

	var focus = ParticipateFocusController.new()
	get_root().add_child(focus)
	created_nodes.append(focus)
	_assert_true(focus.configure(session, population_view), "participate focus controller configures")
	_assert_true(focus.select_group("player_group"), "focus selects player group")
	_assert_true(focus.available_group_ids().has("other_group"), "spectator group switching still sees autonomous group")

	var decision: Dictionary = session.pending_human_decision("player_group")
	var search_iterations: int = 0
	while decision.is_empty() and search_iterations < 180:
		session.advance_time(30.0, false)
		decision = session.pending_human_decision("player_group")
		search_iterations += 1
	_assert_true(search_iterations < 180, "human presentation turn is reached in bounded course time")
	_assert_true(not decision.is_empty(), "authority exposes a pending human decision to presentation")
	if decision.is_empty():
		_finish()
		return

	var presentation: Dictionary = focus.presentation_snapshot()
	_assert_equal(str(presentation.get("mode", "")), "PARTICIPATE", "spectator presentation becomes playable only on human turn")
	_assert_equal(str(presentation.get("decision_id", "")), str(decision.get("decision_id", "")), "HUD projects exact authoritative decision identity")
	_assert_equal(str(presentation.get("decision_kind", "")), str(decision.get("decision_kind", "")), "HUD projects exact authoritative decision kind")
	_assert_equal(str(presentation.get("situation", {}).get("surface", "")), str(decision.get("situation", {}).get("surface", "")), "HUD lie comes from authoritative situation")
	_assert_near(float(presentation.get("situation", {}).get("remaining_distance_yards", -1.0)), float(decision.get("situation", {}).get("remaining_distance_yards", -2.0)), 0.0001, "HUD distance comes from authoritative situation")
	var choices: Array = presentation.get("choices", [])
	_assert_true(not choices.is_empty(), "playable HUD exposes human-selectable authoritative choices")
	var hidden_ai_choices: int = 0
	for choice_value in choices:
		if typeof(choice_value) == TYPE_DICTIONARY and not bool(choice_value.get("human_selectable", false)):
			hidden_ai_choices += 1
	_assert_equal(hidden_ai_choices, 0, "HUD exposes no hidden AI-only candidate as player command")
	var current_turn: Dictionary = runtime.live_session_snapshot("player_group").get("current_turn", {})
	_assert_equal(int(current_turn.get("member_index", -1)), 0, "playable HUD belongs to designated human golfer")
	_assert_equal(str(current_turn.get("golfer_name", "")), str(player_golfers[0].get("golfer_name")), "playable HUD identifies human golfer")

	var chosen_candidate: int = int(choices[0].get("index", -1)) if not choices.is_empty() else -1
	_assert_true(chosen_candidate >= 0, "HUD choice retains authority-issued candidate index")
	var submitted: Dictionary = session.submit_human_choice("player_group", chosen_candidate, false)
	_assert_true(bool(submitted.get("played", false)), "HUD command commits through authoritative human decision path")
	var authoritative_event: Dictionary = submitted.get("shot_event", {})
	var authoritative_shot: Dictionary = submitted.get("shot", {})
	_assert_true(not authoritative_event.is_empty(), "committed human shot produces authoritative live event")
	_assert_equal(str(authoritative_shot.get("choice_source", "")), "HUMAN", "committed shot retains human provenance")
	_assert_equal(str(authoritative_shot.get("decision_id", "")), str(decision.get("decision_id", "")), "committed shot retains HUD decision identity")

	var playback = session.playback_for_group("player_group")
	_assert_true(playback != null, "player group retains live spectator playback")
	if playback != null:
		var playback_snapshot: Dictionary = playback.snapshot()
		var presented: Array = playback_snapshot.get("presented_events", [])
		var human_presentations: Array = []
		for event_value in presented:
			if typeof(event_value) == TYPE_DICTIONARY and str(event_value.get("shot", {}).get("decision_id", "")) == str(decision.get("decision_id", "")):
				human_presentations.append(event_value)
		_assert_equal(human_presentations.size(), 1, "authoritative human result appears exactly once in spectator playback")
		if human_presentations.size() == 1:
			var visual_event: Dictionary = human_presentations[0]
			_assert_equal(visual_event.get("shot", {}).get("landing_position", Vector3.ZERO), authoritative_shot.get("landing_position", Vector3.ONE), "playback preserves exact authoritative landing in simulation coordinates")
			var expected_world_landing: Vector3 = world.world_position(int(authoritative_event.get("hole_number", 0)), authoritative_shot.get("landing_position", Vector3.ZERO))
			_assert_equal(visual_event.get("world_shot", {}).get("landing_position", Vector3.ONE), expected_world_landing, "presentation only translates authoritative landing into spectator world coordinates")

	var after_commit: Dictionary = focus.presentation_snapshot()
	_assert_true(str(after_commit.get("decision_id", "")) != str(decision.get("decision_id", "")), "executed decision is removed from playable HUD")
	_assert_true(session.event_log.size() > 0, "participate presentation maintains living-course event log")

	print("POC26E_PRESENTATION_SUMMARY decision=%s kind=%s choices=%d presented=%d course_time=%.1f" % [
		str(decision.get("decision_id", "")),
		str(decision.get("decision_kind", "")),
		choices.size(),
		playback.snapshot().get("presented_event_count", 0) if playback != null else 0,
		runtime.current_time_seconds
	])
	_finish()


func _new_golfer(profile_value: int):
	var golfer = Golfer.new()
	golfer.profile = profile_value
	golfer.apply_profile()
	get_root().add_child(golfer)
	created_nodes.append(golfer)
	return golfer


func _assert_true(value: bool, label: String) -> void:
	if value:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)


func _assert_equal(actual, expected, label: String) -> void:
	if actual == expected:
		print("PASS: %s (actual=%s expected=%s)" % [label, str(actual), str(expected)])
	else:
		failures += 1
		push_error("FAIL: %s (actual=%s expected=%s)" % [label, str(actual), str(expected)])


func _assert_near(actual: float, expected: float, tolerance: float, label: String) -> void:
	if abs(actual - expected) <= tolerance:
		print("PASS: %s (actual=%.6f expected=%.6f)" % [label, actual, expected])
	else:
		failures += 1
		push_error("FAIL: %s (actual=%.6f expected=%.6f)" % [label, actual, expected])


func _finish() -> void:
	for node in created_nodes:
		if node != null and is_instance_valid(node):
			node.queue_free()
	if failures == 0:
		print("POC-26E SPECTATOR-TO-PARTICIPATE PRESENTATION CONTRACT PASSED")
		quit(0)
	else:
		push_error("POC-26E SPECTATOR-TO-PARTICIPATE PRESENTATION CONTRACT FAILED: %d" % failures)
		quit(1)
