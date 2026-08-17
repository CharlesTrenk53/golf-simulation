extends SceneTree

const PlayerWorldSession = preload("res://simulation/player_world_session.gd")
const PlayerWorldHub = preload("res://simulation/player_world_hub.gd")
const PlayerActivityContract = preload("res://simulation/player_activity_contract.gd")
const POC27Course = preload("res://simulation/poc27_eighteen_hole_course.gd")
const Golfer = preload("res://scenes/golfer.gd")

var failures: int = 0
var created_nodes: Array = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("POC-29D: practice activity launch and factual consequences")
	var course = POC27Course.build()
	_assert_true(course != null and course.hole_count() == 18, "18-hole living course builds")
	if course == null:
		_finish()
		return

	var player = _new_golfer(Golfer.GolferProfile.CAREFUL_CARL)
	var persistent = PlayerWorldSession.new()
	persistent.name = "PersistentPlayerWorldSession"
	get_root().add_child(persistent)
	created_nodes.append(persistent)
	_assert_true(persistent.configure(player, course, 40, 21600.0), "persistent world session configures")

	var hub = PlayerWorldHub.new()
	_assert_true(hub.configure(persistent), "world hub configures over persistent session")
	var original_player_id: int = player.get_instance_id()
	var original_controller_id: int = persistent.controller.get_instance_id()
	var original_world_time: float = persistent.world_time_seconds
	var original_population: int = persistent.controller.living_course.population.group_count()
	var before_development: Dictionary = persistent.development_snapshot()
	var before_putting_experience: int = int(before_development.get(3, {}).get("total_experience", 0))

	var selection: Dictionary = hub.select_activity(PlayerActivityContract.ACTIVITY_PRACTICE, {
		"total_repetitions": 80,
		"focus": {3: 1.0},
		"quality": 0.75,
		"duration_seconds": 900.0
	})
	_assert_true(bool(selection.get("accepted", false)), "hub accepts valid practice selection")
	_assert_equal_str(str(selection.get("activity_type", "")), PlayerActivityContract.ACTIVITY_PRACTICE, "practice selection stays canonical")
	_assert_near(persistent.world_time_seconds, original_world_time, 0.0001, "practice selection alone does not advance world time")
	_assert_equal_int(persistent.golf_activity.total_practice_repetitions(), 0, "practice selection alone records no repetitions")
	_assert_true(persistent.active_practice.is_empty(), "practice selection alone does not create active practice")

	var launched: Dictionary = hub.launch_selected_activity(selection)
	_assert_true(bool(launched.get("launched", false)), "accepted PRACTICE selection launches")
	_assert_equal_str(str(launched.get("activity_type", "")), PlayerActivityContract.ACTIVITY_PRACTICE, "launcher reports PRACTICE activity")
	var entry: Dictionary = launched.get("entry", {})
	_assert_true(bool(entry.get("entered", false)), "practice launcher delegates to persistent session")
	_assert_equal_int(int(entry.get("total_repetitions", 0)), 80, "practice launcher preserves repetition plan")
	_assert_near(float(entry.get("quality", 0.0)), 0.75, 0.0001, "practice launcher preserves quality")
	_assert_near(float(entry.get("duration_seconds", 0.0)), 900.0, 0.0001, "practice launcher preserves duration")
	_assert_equal_int(int(entry.get("golfer_instance_id", 0)), original_player_id, "practice launcher uses exact persistent golfer")
	_assert_true(persistent.active_round.is_empty(), "practice launch does not create a round")
	_assert_true(not persistent.active_practice.is_empty(), "practice launch creates explicit active practice")
	_assert_equal_int(persistent.controller.living_course.population.group_count(), original_population, "practice launch does not add course population")
	_assert_near(persistent.world_time_seconds, original_world_time, 0.0001, "practice launch itself does not advance world time")
	_assert_equal_int(persistent.golf_activity.total_practice_repetitions(), 0, "practice launch itself does not award repetitions")

	var context: Dictionary = hub.context()
	_assert_equal_str(str(context.get("state", "")), PlayerWorldHub.STATE_ACTIVITY, "hub projects active practice as activity state")
	_assert_equal_str(str(context.get("active_activity_type", "")), PlayerActivityContract.ACTIVITY_PRACTICE, "hub identifies active PRACTICE")
	_assert_true(not bool(context.get("can_choose_activity", true)), "active practice blocks conflicting activity selection")
	_assert_equal_int(int(context.get("golfer_instance_id", 0)), original_player_id, "practice context preserves golfer identity")
	_assert_equal_int(int(context.get("controller_instance_id", 0)), original_controller_id, "practice context preserves controller identity")

	var blocked_round: Dictionary = hub.select_activity(PlayerActivityContract.ACTIVITY_ROUND, {})
	_assert_true(not bool(blocked_round.get("accepted", true)), "round selection is blocked while practice is active")
	_assert_equal_str(str(blocked_round.get("reason", "")), PlayerActivityContract.REASON_ACTIVITY_ALREADY_ACTIVE, "practice uses shared conflicting-activity rejection")

	# Missing observed execution must fail transactionally: no world time, activity,
	# or development is committed until practice has factual outcome evidence.
	var missing_observation: Dictionary = persistent.finalize_practice({})
	_assert_true(not bool(missing_observation.get("finalized", true)), "practice cannot finalize without observed execution")
	_assert_equal_str(str(missing_observation.get("reason", "")), "OBSERVED_EXECUTION_REQUIRED", "missing practice outcome has explicit reason")
	_assert_near(persistent.world_time_seconds, original_world_time, 0.0001, "rejected practice completion does not advance world time")
	_assert_equal_int(persistent.golf_activity.total_practice_repetitions(), 0, "rejected practice completion records no repetitions")
	_assert_true(not persistent.active_practice.is_empty(), "rejected practice completion leaves activity active")

	var completed: Dictionary = persistent.finalize_practice({
		3: {
			"execution_score": 78.0,
			"lateral_error": 0.0,
			"distance_error": 0.5
		}
	})
	_assert_true(bool(completed.get("finalized", false)), "practice finalizes with observed execution")
	var practice: Dictionary = completed.get("practice", {})
	var activity_record: Dictionary = practice.get("activity_record", {})
	var evidence: Dictionary = practice.get("development_evidence", {})
	_assert_equal_str(str(practice.get("activity_type", "")), PlayerActivityContract.ACTIVITY_PRACTICE, "completed archive identifies PRACTICE")
	_assert_equal_int(int(activity_record.get("repetitions", 0)), 80, "factual GolfActivity records all practice repetitions")
	_assert_equal_int(int(activity_record.get("practice_repetitions", {}).get(3, 0)), 80, "putting focus receives all repetitions")
	_assert_near(float(activity_record.get("quality", 0.0)), 0.75, 0.0001, "factual GolfActivity records selected practice quality")
	_assert_equal_int(int(evidence.get("total_raw_repetitions", 0)), 80, "development bridge receives factual raw repetitions")
	_assert_equal_int(int(evidence.get("total_evidence", 0)), 60, "quality controls useful development evidence through existing bridge")
	_assert_equal_int(int(evidence.get("total_experience_only", 0)), 20, "non-evidence repetitions still count as experience")
	_assert_near(persistent.world_time_seconds, original_world_time + 900.0, 0.0001, "practice consumes authoritative world time")
	_assert_equal_int(persistent.controller.get_instance_id(), original_controller_id, "practice completion preserves exact world controller")
	_assert_equal_int(player.get_instance_id(), original_player_id, "practice completion preserves exact golfer")
	_assert_equal_int(persistent.controller.living_course.population.group_count(), original_population, "practice completion does not rebuild living-course population")
	_assert_equal_int(persistent.completed_practices.size(), 1, "completed practice is archived once")
	_assert_true(persistent.active_practice.is_empty(), "completed practice clears active activity")
	_assert_equal_int(persistent.golf_activity.total_practice_repetitions(), 80, "persistent GolfActivity retains completed practice")
	_assert_equal_int(int(persistent.golf_activity.career_practice_repetitions.get(3, 0)), 80, "persistent putting practice accumulation is factual")

	var after_development: Dictionary = persistent.development_snapshot()
	var after_putting_experience: int = int(after_development.get(3, {}).get("total_experience", 0))
	_assert_equal_int(after_putting_experience, before_putting_experience + 80, "all practice repetitions reach persistent development experience")
	_assert_equal_int(int(player.career_shot_experience.get(3, 0)), after_putting_experience, "golfer career experience is synchronized from development authority")

	var returned_context: Dictionary = hub.context()
	_assert_equal_str(str(returned_context.get("state", "")), PlayerWorldHub.STATE_WORLD, "completed practice returns hub projection to WORLD")
	_assert_equal_str(str(returned_context.get("active_activity_type", "")), PlayerWorldHub.ACTIVITY_NONE, "hub reports no active activity after practice")
	_assert_true(bool(returned_context.get("can_choose_activity", false)), "activity selection reopens after practice completion")
	_assert_equal_int(int(returned_context.get("completed_practices", 0)), 1, "hub exposes completed practice count")
	_assert_equal_int(int(returned_context.get("total_practice_repetitions", 0)), 80, "hub exposes persistent factual practice volume")
	_assert_equal_int(int(returned_context.get("golfer_instance_id", 0)), original_player_id, "return to world retains same golfer")
	_assert_equal_int(int(returned_context.get("controller_instance_id", 0)), original_controller_id, "return to world retains same controller")

	var next_round: Dictionary = hub.select_activity(PlayerActivityContract.ACTIVITY_ROUND, {})
	_assert_true(bool(next_round.get("accepted", false)), "round becomes selectable again after practice completion")
	_assert_near(persistent.world_time_seconds, original_world_time + 900.0, 0.0001, "post-practice selection remains pure")

	print("POC29D_PRACTICE_SUMMARY golfer_id=%d controller_id=%d reps=%d evidence=%d world_time=%.1f putting_experience=%d" % [
		original_player_id,
		original_controller_id,
		persistent.golf_activity.total_practice_repetitions(),
		int(evidence.get("total_evidence", 0)),
		persistent.world_time_seconds,
		after_putting_experience
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


func _assert_equal_int(actual: int, expected: int, label: String) -> void:
	if actual == expected:
		print("PASS: %s (actual=%d expected=%d)" % [label, actual, expected])
	else:
		failures += 1
		push_error("FAIL: %s (actual=%d expected=%d)" % [label, actual, expected])


func _assert_equal_str(actual: String, expected: String, label: String) -> void:
	if actual == expected:
		print("PASS: %s (actual=%s expected=%s)" % [label, actual, expected])
	else:
		failures += 1
		push_error("FAIL: %s (actual=%s expected=%s)" % [label, actual, expected])


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
		print("POC-29D PRACTICE ACTIVITY LAUNCH PASSED")
		quit(0)
	else:
		push_error("POC-29D PRACTICE ACTIVITY LAUNCH FAILED: %d" % failures)
		quit(1)
