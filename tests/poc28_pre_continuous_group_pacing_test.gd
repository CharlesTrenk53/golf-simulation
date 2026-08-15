extends SceneTree

const POC27Course = preload("res://simulation/poc27_eighteen_hole_course.gd")
const ShotProgressiveLivingCourseController = preload("res://simulation/shot_progressive_living_course_controller.gd")
const ParticipatePacingController = preload("res://scenes/participate_pacing_controller.gd")
const Golfer = preload("res://scenes/golfer.gd")

var failures: int = 0
var created_nodes: Array = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("PRE-POC-28: continuous group-play pacing")
	_test_ai_group_flow()
	_test_ready_human_turn_stops_fast_forward()
	_finish()


func _test_ai_group_flow() -> void:
	var course = POC27Course.build()
	_assert_true(course != null, "18-hole living course builds for pacing proof")
	if course == null:
		return

	var runtime = ShotProgressiveLivingCourseController.new()
	_assert_true(runtime.configure(course), "living-course authority configures")
	var golfers: Array = [
		_new_golfer(Golfer.GolferProfile.CAREFUL_CARL),
		_new_golfer(Golfer.GolferProfile.WILD_BILL),
		_new_golfer(Golfer.GolferProfile.RECKLESS_RICK),
		_new_golfer(Golfer.GolferProfile.CAREFUL_CARL)
	]
	_assert_true(runtime.add_group("group_1", golfers, "default", -1, 28101), "ordinary AI foursome joins course")
	var release: Dictionary = runtime.release_next_group()
	_assert_true(bool(release.get("released", false)), "ordinary foursome releases onto Hole 1")
	if not bool(release.get("released", false)):
		return

	var pacing = ParticipatePacingController.new()
	var first_four: Array = []
	var prior_world_time: float = runtime.current_time_seconds

	for shot_index in range(4):
		var before: Dictionary = runtime.live_session_snapshot("group_1")
		var before_turn: Dictionary = before.get("current_turn", {})
		_assert_equal_str(str(before_turn.get("order_reason", "")), "TEE_ORDER", "tee turn %d remains governed by tee order" % (shot_index + 1))

		var plan: Dictionary = pacing.idle_advance(runtime)
		_assert_equal_str(str(plan.get("mode", "")), ParticipatePacingController.MODE_FAST_FORWARD, "tee turn %d idle gap is compressed" % (shot_index + 1))
		var target_time: float = float(plan.get("target_time_seconds", prior_world_time))
		_assert_true(target_time + 0.001 >= prior_world_time, "tee turn %d keeps monotonic authoritative world time" % (shot_index + 1))

		var processed: Array = runtime.advance_time(float(plan.get("delta_seconds", 0.0)))
		var live_shots: Array = _live_shots_for(processed, "group_1")
		_assert_equal_int(live_shots.size(), 1, "one fast-forward produces exactly one next tee shot")
		if live_shots.size() == 1:
			first_four.append(live_shots[0])
			_assert_equal_int(int(live_shots[0].get("shot_number", 0)), 1, "tee event is golfer's first shot")
		prior_world_time = runtime.current_time_seconds

	_assert_equal_int(first_four.size(), 4, "all four golfers tee before away-order play")
	var after_tees: Dictionary = runtime.live_session_snapshot("group_1")
	_assert_equal_str(str(after_tees.get("current_turn", {}).get("order_reason", "")), "AWAY", "away order takes over immediately after final tee ball")

	var away_plan: Dictionary = pacing.idle_advance(runtime)
	_assert_equal_str(str(away_plan.get("mode", "")), ParticipatePacingController.MODE_FAST_FORWARD, "walk/setup interval to first away ball is compressed")
	_assert_true(float(away_plan.get("target_time_seconds", prior_world_time)) > prior_world_time, "compressed presentation still preserves elapsed golf-world travel/routine time")
	var away_processed: Array = runtime.advance_time(float(away_plan.get("delta_seconds", 0.0)))
	var away_shots: Array = _live_shots_for(away_processed, "group_1")
	_assert_equal_int(away_shots.size(), 1, "arrival at first away ball produces exactly one next shot")


func _test_ready_human_turn_stops_fast_forward() -> void:
	var course = POC27Course.build()
	if course == null:
		return
	var runtime = ShotProgressiveLivingCourseController.new()
	_assert_true(runtime.configure(course), "mixed-group pacing authority configures")
	var golfers: Array = [
		_new_golfer(Golfer.GolferProfile.CAREFUL_CARL),
		_new_golfer(Golfer.GolferProfile.WILD_BILL),
		_new_golfer(Golfer.GolferProfile.RECKLESS_RICK),
		_new_golfer(Golfer.GolferProfile.CAREFUL_CARL)
	]
	_assert_true(runtime.add_group("group_1", golfers, "default", 0, 28201), "human remains ordinary member of foursome")
	var release: Dictionary = runtime.release_next_group()
	_assert_true(bool(release.get("released", false)), "mixed foursome releases normally")
	if not bool(release.get("released", false)):
		return

	var pacing = ParticipatePacingController.new()
	var ready_plan: Dictionary = {}
	var guard: int = 0
	while guard < 8:
		guard += 1
		var plan: Dictionary = pacing.idle_advance(runtime, "group_1")
		if str(plan.get("mode", "")) == ParticipatePacingController.MODE_REALTIME:
			ready_plan = plan
			break
		_assert_equal_str(str(plan.get("mode", "")), ParticipatePacingController.MODE_FAST_FORWARD, "pre-human idle gap compresses without autoplaying human")
		runtime.advance_time(float(plan.get("delta_seconds", 0.0)))

	_assert_true(not ready_plan.is_empty(), "pacing reaches ready human turn in bounded jumps")
	if ready_plan.is_empty():
		return
	_assert_equal_str(str(ready_plan.get("reason", "")), "HUMAN_DECISION_READY", "ready human decision switches pacing back to realtime")
	var decision: Dictionary = runtime.pending_human_decision("group_1")
	_assert_true(not decision.is_empty(), "human decision is exposed rather than auto-executed")
	if decision.is_empty():
		return
	var decision_id: String = str(decision.get("decision_id", ""))
	var shots_before: int = runtime.group_live_shot_count("group_1")
	runtime.advance_time(15.0)
	var decision_after: Dictionary = runtime.pending_human_decision("group_1")
	_assert_equal_str(str(decision_after.get("decision_id", "")), decision_id, "human decision survives ordinary world-clock advancement")
	_assert_equal_int(runtime.group_live_shot_count("group_1"), shots_before, "human golfer never autoplays while deciding")


func _live_shots_for(events: Array, group_id: String) -> Array:
	var result: Array = []
	for event_value in events:
		if typeof(event_value) != TYPE_DICTIONARY:
			continue
		var event: Dictionary = event_value
		if str(event.get("type", "")) == "LIVE_SHOT" and str(event.get("group_id", "")) == group_id:
			result.append(event)
	return result


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


func _finish() -> void:
	for node in created_nodes:
		if node != null and is_instance_valid(node):
			node.queue_free()
	if failures == 0:
		print("PRE-POC-28 CONTINUOUS GROUP-PLAY PACING PASSED")
		quit(0)
	else:
		push_error("PRE-POC-28 CONTINUOUS GROUP-PLAY PACING FAILED: %d" % failures)
		quit(1)
