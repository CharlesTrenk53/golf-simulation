extends SceneTree

const CourseDefinition = preload("res://simulation/course_definition.gd")
const ShotProgressiveLivingCourseController = preload("res://simulation/shot_progressive_living_course_controller.gd")
const SpectatorCourseWorld = preload("res://scenes/spectator_course_world.gd")
const SpectatorPopulationView = preload("res://scenes/spectator_population_view.gd")
const ParticipateSpectatorSession = preload("res://scenes/participate_spectator_session.gd")
const Golfer = preload("res://scenes/golfer.gd")

class UnrelatedBusyPlayback:
	extends RefCounted

	func is_busy() -> bool:
		return true

	func has_pending_events() -> bool:
		return false

	func drain_immediate() -> int:
		return 0

	func next_event() -> Dictionary:
		return {}


var failures: int = 0
var created_nodes: Array = []


func _init() -> void:
	print("POC-26E: player decision persists during unrelated group playback")
	var course = CourseDefinition.load_json("res://data/courses/poc12_proving_course.json")
	_assert_true(course != null, "three-hole proving course loads")
	if course == null:
		_finish()
		return

	var runtime = ShotProgressiveLivingCourseController.new()
	_assert_true(runtime.configure(course), "shot-progressive authority configures")

	var player = _new_golfer(Golfer.GolferProfile.CAREFUL_CARL)
	var partner = _new_golfer(Golfer.GolferProfile.WILD_BILL)
	var other_a = _new_golfer(Golfer.GolferProfile.RECKLESS_RICK)
	var other_b = _new_golfer(Golfer.GolferProfile.WILD_BILL)
	_assert_true(runtime.add_group("group_1", [player, partner], "default", 0, 29101), "player group joins normal live course")
	_assert_true(runtime.add_group("group_2", [other_a, other_b], "default", -1, 29201), "other group joins same live course")

	var world = SpectatorCourseWorld.new()
	get_root().add_child(world)
	created_nodes.append(world)
	_assert_true(world.configure(course), "spectator course world configures")

	var view = SpectatorPopulationView.new()
	get_root().add_child(view)
	created_nodes.append(view)
	_assert_true(view.configure(world, runtime), "spectator population view configures")

	var session = ParticipateSpectatorSession.new()
	get_root().add_child(session)
	created_nodes.append(session)
	_assert_true(session.configure(runtime, world, view), "participate session configures")
	_assert_true(not session.start_session().is_empty(), "participate session starts")

	var decision: Dictionary = session.pending_human_decision("group_1")
	var iterations: int = 0
	while decision.is_empty() and iterations < 180:
		session.advance_time(30.0, false)
		decision = session.pending_human_decision("group_1")
		iterations += 1
	_assert_true(not decision.is_empty(), "player reaches stable authoritative decision")
	if decision.is_empty():
		_finish()
		return

	var decision_id: String = str(decision.get("decision_id", ""))
	var candidate_index: int = _first_selectable(decision)
	_assert_true(not decision_id.is_empty(), "pending player decision has identity")
	_assert_true(candidate_index >= 0, "pending player decision has selectable candidate")
	_assert_true(not session.group_presentation_busy("group_1"), "player group presentation is caught up before choice")

	var displaced = session.active_playbacks.get("group_2", null)
	var unrelated_busy = UnrelatedBusyPlayback.new()
	session.active_playbacks["group_2"] = unrelated_busy
	_assert_true(session.presentation_busy(), "unrelated group can make global presentation busy")
	_assert_true(not session.group_presentation_busy("group_1"), "unrelated playback does not make player group presentation busy")

	var while_busy: Dictionary = session.pending_human_decision("group_1")
	_assert_equal(str(while_busy.get("decision_id", "")), decision_id, "unrelated group activity cannot erase player decision")
	var submitted: Dictionary = session.submit_human_choice("group_1", candidate_index, true)
	_assert_true(bool(submitted.get("played", false)), "player can commit stable choice while unrelated group is visually busy")
	_assert_equal(str(submitted.get("shot", {}).get("decision_id", "")), decision_id, "committed shot retains decision shown during unrelated playback")

	var player_playback = session.playback_for_group("group_1")
	_assert_true(player_playback != null, "committed player shot remains attached to player playback")
	if player_playback != null:
		var queued_snapshot: Dictionary = player_playback.snapshot()
		_assert_true(int(queued_snapshot.get("queued_event_count", 0)) > 0, "player shot waits in presentation queue while unrelated motion is active")
		_assert_true(not bool(queued_snapshot.get("active_flight", false)), "queued player shot does not visually overtake unrelated active motion")

	if displaced != null:
		session.active_playbacks["group_2"] = displaced
	else:
		session.active_playbacks.erase("group_2")

	var kicked_queue: bool = session.advance_visuals(0.01)
	_assert_true(kicked_queue, "visual update starts oldest queued shot after unrelated motion clears")
	player_playback = session.playback_for_group("group_1")
	if player_playback != null:
		var started_snapshot: Dictionary = player_playback.snapshot()
		_assert_equal(int(started_snapshot.get("queued_event_count", 0)), 0, "queued player shot leaves queue once motion clears")
		_assert_equal(int(started_snapshot.get("presented_event_count", 0)), 1, "queued player shot is actually presented")
		_assert_true(bool(started_snapshot.get("active_flight", false)), "queued player shot begins visible flight")

	session.drain_visuals_immediate()
	_assert_true(not session.group_presentation_busy("group_1"), "player presentation catches up after queued shot completes")
	_assert_true(not session.presentation_busy(), "global presentation no longer deadlocks on an empty-motion pending queue")

	var before_resume_time: float = runtime.current_time_seconds
	session.advance_time(1.0, true)
	_assert_true(runtime.current_time_seconds > before_resume_time, "course clock can resume after queued presentation drains")

	print("POC26E_DECISION_PERSISTENCE_SUMMARY decision=%s global_busy=true submitted=%s resumed=%s" % [
		decision_id,
		str(bool(submitted.get("played", false))),
		str(runtime.current_time_seconds > before_resume_time)
	])
	_finish()


func _first_selectable(decision: Dictionary) -> int:
	for choice_value in decision.get("choices", []):
		if typeof(choice_value) != TYPE_DICTIONARY:
			continue
		var choice: Dictionary = choice_value
		if bool(choice.get("human_selectable", false)):
			return int(choice.get("index", -1))
	return -1


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


func _finish() -> void:
	for node in created_nodes:
		if node != null and is_instance_valid(node):
			node.queue_free()
	if failures == 0:
		print("POC-26E PLAYER DECISION PERSISTENCE DURING OTHER-GROUP PLAYBACK PASSED")
		quit(0)
	else:
		push_error("POC-26E PLAYER DECISION PERSISTENCE FAILED: %d" % failures)
		quit(1)
