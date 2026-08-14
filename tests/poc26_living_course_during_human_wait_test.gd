extends SceneTree

const CourseDefinition = preload("res://simulation/course_definition.gd")
const ShotProgressiveLivingCourseController = preload("res://simulation/shot_progressive_living_course_controller.gd")
const Golfer = preload("res://scenes/golfer.gd")

var failures: int = 0
var created_golfers: Array = []


func _init() -> void:
	print("POC-26D: living course continues while human decides")
	var course = CourseDefinition.load_json("res://data/courses/poc12_proving_course.json")
	_assert_true(course != null, "three-hole proving course loads")
	if course == null:
		_finish()
		return

	var runtime = ShotProgressiveLivingCourseController.new()
	_assert_true(runtime.configure(course), "shot-progressive living course configures")

	var player_golfers: Array = [
		_new_golfer(Golfer.GolferProfile.CAREFUL_CARL),
		_new_golfer(Golfer.GolferProfile.WILD_BILL)
	]
	var autonomous_golfers: Array = [
		_new_golfer(Golfer.GolferProfile.RECKLESS_RICK),
		_new_golfer(Golfer.GolferProfile.WILD_BILL)
	]
	_assert_true(runtime.add_group("player_group", player_golfers, "default", 0, 26401), "mixed player group joins generic live runtime")
	_assert_true(runtime.add_group("autonomous_group", autonomous_golfers, "default", -1, 26501), "AI-only group joins same generic live runtime")

	var first_release: Dictionary = runtime.release_next_group()
	_assert_true(bool(first_release.get("released", false)), "lead player group releases onto open first hole")
	_assert_equal(str(first_release.get("group_id", "")), "player_group", "FIFO start order releases player group first")
	_assert_equal(runtime.traffic.group_hole("player_group"), 1, "player group owns first-hole traffic authority")

	var premature_release: Dictionary = runtime.release_next_group()
	_assert_true(not bool(premature_release.get("released", false)), "following group cannot release immediately")
	_assert_equal(str(premature_release.get("group_id", "")), "autonomous_group", "following group remains next in start queue")
	_assert_true(not bool(premature_release.get("spacing", {}).get("safe", false)), "live spacing gate is initially unsafe")
	_assert_equal(str(premature_release.get("spacing", {}).get("release_rule", "")), "RANGE_SAFE_AND_ALL_LEAD_GOLFERS_ON_GREEN", "live gate preserves POC-24 range-plus-green rule")

	# Drive the lead group normally, supplying deterministic human commands only
	# when its live turn is ready, until the follower is mechanically released.
	var drive_iterations: int = 0
	while runtime.traffic.group_hole("autonomous_group") == 0 and drive_iterations < 240:
		runtime.advance_time(45.0)
		var decision: Dictionary = runtime.pending_human_decision("player_group")
		if not decision.is_empty():
			var choice_index: int = _first_human_choice(decision)
			_assert_true(choice_index >= 0, "pending lead decision exposes a human-selectable authoritative choice")
			if choice_index >= 0:
				var submission: Dictionary = runtime.submit_human_choice("player_group", choice_index)
				_assert_true(bool(submission.get("played", false)), "scripted lead human choice executes while establishing safe release")
		drive_iterations += 1

	_assert_true(drive_iterations < 240, "following group release remains bounded")
	_assert_equal(runtime.traffic.group_hole("autonomous_group"), 1, "following group enters first hole only after live safety gate")
	var release_event: Dictionary = _latest_event(runtime.event_history, "LIVE_TEE_RELEASE", "autonomous_group")
	_assert_true(not release_event.is_empty(), "safe following-group release is recorded")
	_assert_true(bool(release_event.get("spacing", {}).get("safe", false)), "recorded following release was mechanically safe")
	_assert_true(bool(release_event.get("spacing", {}).get("range_safe", false)), "credible-reach condition is satisfied at release")
	_assert_true(bool(release_event.get("spacing", {}).get("all_lead_golfers_green_or_holed", false)), "green gate is satisfied at release")

	# Find the next actual player decision after the autonomous group is already
	# live. Do not submit it. This is the state POC-26D must preserve while the
	# rest of the course keeps running.
	var wait_decision: Dictionary = runtime.pending_human_decision("player_group")
	var wait_search_iterations: int = 0
	while wait_decision.is_empty() and wait_search_iterations < 180:
		runtime.advance_time(30.0)
		wait_decision = runtime.pending_human_decision("player_group")
		wait_search_iterations += 1
	_assert_true(not wait_decision.is_empty(), "player reaches a pending decision while another group is live")
	_assert_true(wait_search_iterations < 180, "human-wait state is reached in bounded live time")
	if wait_decision.is_empty():
		_finish()
		return

	var decision_id: String = str(wait_decision.get("decision_id", ""))
	var player_shots_before: int = runtime.group_live_shot_count("player_group")
	var autonomous_shots_before: int = runtime.group_live_shot_count("autonomous_group")
	var player_snapshot_before: Dictionary = runtime.live_session_snapshot("player_group")
	var player_turns_before: int = player_snapshot_before.get("turn_history", []).size()
	var player_group = runtime.living_course.population.group_by_id("player_group")
	var human_strokes_before: int = int(player_group.rounds[0].active_hole_state.strokes) if player_group != null and player_group.rounds[0].has_active_hole() else -1
	var time_before: float = runtime.current_time_seconds

	var world_events: Array = runtime.advance_time(360.0)
	_assert_equal(runtime.current_time_seconds, time_before + 360.0, "global course clock advances while human is deciding")
	_assert_equal(runtime.group_live_shot_count("player_group"), player_shots_before, "pending human turn prevents player group autoplay")
	_assert_equal(runtime.live_session_snapshot("player_group").get("turn_history", []).size(), player_turns_before, "waiting creates no phantom player turn history")
	if human_strokes_before >= 0 and player_group.rounds[0].has_active_hole():
		_assert_equal(int(player_group.rounds[0].active_hole_state.strokes), human_strokes_before, "human authoritative ball state is frozen while waiting")
	_assert_true(runtime.group_live_shot_count("autonomous_group") > autonomous_shots_before, "autonomous group keeps taking real shots during human wait")
	_assert_true(_contains_group_shot(world_events, "autonomous_group"), "world-clock advance reports autonomous golf events during human wait")
	var still_pending: Dictionary = runtime.pending_human_decision("player_group")
	_assert_equal(str(still_pending.get("decision_id", "")), decision_id, "same authoritative human decision remains pending after world advances")

	# Resume the player. The waiting period must not poison group authority or
	# course progression. Wait for the authoritative whole-group hole-finish event,
	# not merely the human member's scorecard, because the AI partner may still have
	# a scheduled live turn after the human holes out.
	var resume_choice: int = _first_human_choice(still_pending)
	_assert_true(resume_choice >= 0, "pending human decision remains selectable after world wait")
	if resume_choice >= 0:
		var resumed: Dictionary = runtime.submit_human_choice("player_group", resume_choice)
		_assert_true(bool(resumed.get("played", false)), "human play resumes through same authoritative decision after wait")

	var completion_iterations: int = 0
	var player_hole_finish: Dictionary = _latest_event(runtime.event_history, "LIVE_HOLE_FINISH", "player_group")
	while player_hole_finish.is_empty() and completion_iterations < 240:
		runtime.advance_time(30.0)
		var next_decision: Dictionary = runtime.pending_human_decision("player_group")
		if not next_decision.is_empty():
			var next_choice: int = _first_human_choice(next_decision)
			if next_choice >= 0:
				var next_submission: Dictionary = runtime.submit_human_choice("player_group", next_choice)
				_assert_true(bool(next_submission.get("played", false)), "resumed human group continues through subsequent live turns")
		player_hole_finish = _latest_event(runtime.event_history, "LIVE_HOLE_FINISH", "player_group")
		completion_iterations += 1

	_assert_true(completion_iterations < 240, "player group can complete hole after extended human wait")
	_assert_true(not player_hole_finish.is_empty(), "whole mixed group records authoritative hole completion after resume")
	_assert_true(player_group.rounds[0].round_state.holes_completed() >= 1, "human golfer records completed authoritative hole after resume")
	_assert_true(player_group.rounds[1].round_state.holes_completed() >= 1, "AI partner records same completed group hole")
	_assert_true(runtime.group_live_shot_count("autonomous_group") > autonomous_shots_before, "other-group progression survives player resume")

	print("POC26D_LIVING_WAIT_SUMMARY wait_seconds=360 player_shots_before=%d autonomous_before=%d autonomous_after=%d traffic_player=%d traffic_ai=%d" % [
		player_shots_before,
		autonomous_shots_before,
		runtime.group_live_shot_count("autonomous_group"),
		runtime.traffic.group_hole("player_group"),
		runtime.traffic.group_hole("autonomous_group")
	])
	_finish()


func _first_human_choice(decision: Dictionary) -> int:
	var choices: Array = decision.get("choices", [])
	for index in range(choices.size()):
		if typeof(choices[index]) == TYPE_DICTIONARY and bool(choices[index].get("human_selectable", false)):
			return index
	return -1


func _latest_event(events: Array, event_type: String, group_id: String) -> Dictionary:
	for index in range(events.size() - 1, -1, -1):
		if typeof(events[index]) != TYPE_DICTIONARY:
			continue
		var event: Dictionary = events[index]
		if str(event.get("type", "")) == event_type and str(event.get("group_id", "")) == group_id:
			return event.duplicate(true)
	return {}


func _contains_group_shot(events: Array, group_id: String) -> bool:
	for event_value in events:
		if typeof(event_value) != TYPE_DICTIONARY:
			continue
		var event: Dictionary = event_value
		if str(event.get("type", "")) == "LIVE_SHOT" and str(event.get("group_id", "")) == group_id:
			return true
	return false


func _new_golfer(profile_value: int):
	var golfer = Golfer.new()
	golfer.profile = profile_value
	golfer.apply_profile()
	get_root().add_child(golfer)
	created_golfers.append(golfer)
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
	for golfer in created_golfers:
		if golfer != null:
			golfer.queue_free()
	if failures == 0:
		print("POC-26D LIVING COURSE CONTINUES DURING HUMAN WAIT PASSED")
		quit(0)
	else:
		push_error("POC-26D LIVING COURSE CONTINUES DURING HUMAN WAIT FAILED: %d" % failures)
		quit(1)
