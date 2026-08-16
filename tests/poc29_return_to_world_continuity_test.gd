extends SceneTree

const PlayerWorldSession = preload("res://simulation/player_world_session.gd")
const PlayerWorldHub = preload("res://simulation/player_world_hub.gd")
const PlayerActivityContract = preload("res://simulation/player_activity_contract.gd")
const PlayerActivityReturnCoordinator = preload("res://simulation/player_activity_return_coordinator.gd")
const POC27Course = preload("res://simulation/poc27_eighteen_hole_course.gd")
const Golfer = preload("res://scenes/golfer.gd")

var failures: int = 0
var created_nodes: Array = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("POC-29E: return-to-world continuity")
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
	_assert_true(persistent.configure(player, course, 50, 25200.0), "persistent world session configures")

	var hub = PlayerWorldHub.new()
	_assert_true(hub.configure(persistent), "world hub configures over persistent session")
	var golfer_id: int = player.get_instance_id()
	var controller_id: int = persistent.controller.get_instance_id()
	var starting_time: float = persistent.world_time_seconds

	var idle_return: Dictionary = hub.return_to_world()
	_assert_true(bool(idle_return.get("returned", false)), "return request while idle succeeds")
	_assert_true(bool(idle_return.get("already_world", false)), "idle return reports already in world")
	_assert_equal_str(str(idle_return.get("activity_type", "")), PlayerWorldHub.ACTIVITY_NONE, "idle return has no activity")
	_assert_equal_int(int(idle_return.get("golfer_instance_id", 0)), golfer_id, "idle return preserves golfer identity")
	_assert_equal_int(int(idle_return.get("controller_instance_id", 0)), controller_id, "idle return preserves controller identity")

	# Practice can be cancelled before factual outcomes are committed. Cancellation
	# clears only activity intent; it must not award reps, development, or time.
	var practice_selection: Dictionary = hub.select_activity(PlayerActivityContract.ACTIVITY_PRACTICE, {
		"total_repetitions": 40,
		"focus": {3: 1.0},
		"quality": 0.8,
		"duration_seconds": 600.0
	})
	_assert_true(bool(practice_selection.get("accepted", false)), "practice selection is available from world hub")
	var practice_launch: Dictionary = hub.launch_selected_activity(practice_selection)
	_assert_true(bool(practice_launch.get("launched", false)), "practice launches before cancellation")
	_assert_equal_str(str(hub.context().get("state", "")), PlayerWorldHub.STATE_ACTIVITY, "hub enters activity state for practice")

	var cancelled: Dictionary = hub.return_to_world(PlayerActivityReturnCoordinator.ACTION_CANCEL)
	_assert_true(bool(cancelled.get("returned", false)), "active practice can return by cancellation")
	_assert_true(bool(cancelled.get("cancelled", false)), "practice return is marked cancelled")
	_assert_equal_str(str(cancelled.get("activity_type", "")), PlayerActivityContract.ACTIVITY_PRACTICE, "cancelled activity remains factual PRACTICE")
	_assert_true(persistent.active_practice.is_empty(), "practice cancellation clears active practice")
	_assert_equal_int(persistent.completed_practices.size(), 0, "cancelled practice is not archived as completed")
	_assert_equal_int(persistent.golf_activity.total_practice_repetitions(), 0, "cancelled practice awards no repetitions")
	_assert_near(persistent.world_time_seconds, starting_time, 0.0001, "cancelled practice consumes no committed practice time")
	_assert_equal_int(player.get_instance_id(), golfer_id, "practice cancellation preserves golfer")
	_assert_equal_int(persistent.controller.get_instance_id(), controller_id, "practice cancellation preserves controller")
	_assert_equal_str(str(hub.context().get("state", "")), PlayerWorldHub.STATE_WORLD, "practice cancellation returns hub to WORLD")
	_assert_true(bool(hub.context().get("can_choose_activity", false)), "activity selection reopens after cancellation")
	var history: Array = persistent.activity_history
	_assert_true(not history.is_empty(), "practice cancellation writes lifecycle history")
	if not history.is_empty():
		_assert_equal_str(str(history[history.size() - 1].get("type", "")), "PRACTICE_CANCELLED", "cancellation is recorded factually")

	# A later practice completion uses the same return seam and commits ordinary
	# POC-10 factual/development consequences before returning to the same hub.
	var second_selection: Dictionary = hub.select_activity(PlayerActivityContract.ACTIVITY_PRACTICE, {
		"total_repetitions": 40,
		"focus": {3: 1.0},
		"quality": 0.8,
		"duration_seconds": 600.0
	})
	_assert_true(bool(second_selection.get("accepted", false)), "practice can be selected again after cancellation")
	_assert_true(bool(hub.launch_selected_activity(second_selection).get("launched", false)), "second practice launches")
	var completed: Dictionary = hub.return_to_world(PlayerActivityReturnCoordinator.ACTION_COMPLETE, {
		"observations": {
			3: {
				"execution_score": 76.0,
				"lateral_error": 0.0,
				"distance_error": 0.4
			}
		}
	})
	_assert_true(bool(completed.get("returned", false)), "completed practice returns through shared hub seam")
	_assert_true(bool(completed.get("completed", false)), "practice return is marked completed")
	_assert_true(not bool(completed.get("cancelled", true)), "completed practice is not marked cancelled")
	_assert_equal_int(persistent.completed_practices.size(), 1, "completed practice archives exactly once")
	_assert_equal_int(persistent.golf_activity.total_practice_repetitions(), 40, "completed practice commits factual reps")
	_assert_near(persistent.world_time_seconds, starting_time + 600.0, 0.0001, "completed practice advances same world clock")
	_assert_equal_str(str(hub.context().get("state", "")), PlayerWorldHub.STATE_WORLD, "completed practice returns hub to WORLD")
	_assert_equal_int(int(hub.context().get("golfer_instance_id", 0)), golfer_id, "completed return keeps exact golfer")
	_assert_equal_int(int(hub.context().get("controller_instance_id", 0)), controller_id, "completed return keeps exact controller")

	# A scored round cannot be discarded merely because the player asks to return.
	# Until ordinary round authority reaches FINISHED, both cancel and complete are
	# rejected and the group remains in the living course.
	var round_selection: Dictionary = hub.select_activity(PlayerActivityContract.ACTIVITY_ROUND, {
		"group_id": "return_test_round",
		"other_golfers": [],
		"tee_id": "default",
		"player_member_index": 0,
		"seed_base": 29501
	})
	_assert_true(bool(round_selection.get("accepted", false)), "round selectable after completed practice")
	var round_launch: Dictionary = hub.launch_selected_activity(round_selection)
	_assert_true(bool(round_launch.get("launched", false)), "round launches through ordinary authority")
	_assert_equal_int(persistent.controller.living_course.population.group_count(), 1, "launched round occupies living-course population")

	var cancel_round: Dictionary = hub.return_to_world(PlayerActivityReturnCoordinator.ACTION_CANCEL)
	_assert_true(not bool(cancel_round.get("returned", true)), "unfinished round cannot be cancelled through hub")
	_assert_equal_str(str(cancel_round.get("reason", "")), PlayerActivityReturnCoordinator.REASON_ROUND_ABANDONMENT_NOT_SUPPORTED, "round cancellation rejection is explicit")
	_assert_true(not persistent.active_round.is_empty(), "rejected round cancellation leaves round authoritative")
	_assert_equal_int(persistent.controller.living_course.population.group_count(), 1, "rejected cancellation cannot remove living-course group")

	var premature_complete: Dictionary = hub.return_to_world(PlayerActivityReturnCoordinator.ACTION_COMPLETE)
	_assert_true(not bool(premature_complete.get("returned", true)), "unfinished round cannot return as completed")
	_assert_equal_str(str(premature_complete.get("reason", "")), "ROUND_NOT_FINISHED", "premature round completion delegates authoritative rejection")
	_assert_equal_str(str(hub.context().get("state", "")), PlayerWorldHub.STATE_ACTIVITY, "hub remains in activity while round is unfinished")
	_assert_equal_int(player.get_instance_id(), golfer_id, "round return rejection preserves golfer")
	_assert_equal_int(persistent.controller.get_instance_id(), controller_id, "round return rejection preserves controller")

	print("POC29E_RETURN_WORLD_SUMMARY golfer_id=%d controller_id=%d practices=%d reps=%d world_time=%.1f round_active=%s" % [
		golfer_id,
		controller_id,
		persistent.completed_practices.size(),
		persistent.golf_activity.total_practice_repetitions(),
		persistent.world_time_seconds,
		str(not persistent.active_round.is_empty())
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
		print("POC-29E RETURN-TO-WORLD CONTINUITY PASSED")
		quit(0)
	else:
		push_error("POC-29E RETURN-TO-WORLD CONTINUITY FAILED: %d" % failures)
		quit(1)
