extends SceneTree

const CourseDefinition = preload("res://simulation/course_definition.gd")
const CoursePopulation = preload("res://simulation/course_population.gd")
const GroupProgressionCoordinator = preload("res://simulation/group_progression_coordinator.gd")
const Golfer = preload("res://scenes/golfer.gd")

var failures: int = 0
var created_golfers: Array = []


func _init() -> void:
	print("POC-26A: authoritative incremental group hole session")
	var course = CourseDefinition.load_json("res://data/courses/poc12_proving_course.json")
	_assert_true(course != null, "three-hole proving course loads")
	if course == null:
		_finish()
		return

	var population = CoursePopulation.new()
	_assert_true(population.configure(course), "course population configures")
	var golfers: Array = [
		_new_golfer(Golfer.GolferProfile.CAREFUL_CARL),
		_new_golfer(Golfer.GolferProfile.WILD_BILL),
		_new_golfer(Golfer.GolferProfile.RECKLESS_RICK)
	]
	_assert_true(population.add_group("player_group", golfers), "threesome enters population")
	_assert_true(population.start_group("player_group"), "group starts")

	var group = population.group_by_id("player_group")
	var coordinator = GroupProgressionCoordinator.new()
	var session = coordinator.begin_session(group, 26001)
	_assert_true(session != null, "incremental group session begins")
	if session == null:
		_finish()
		return

	_assert_equal(session.hole_number, 1, "session owns hole one authority")
	_assert_equal(session.tee_order.size(), 3, "session establishes one tee slot per golfer")
	_assert_equal(str(session.tee_order_source), "RANDOM_FIRST_TEE", "opening tee uses seeded random order")
	_assert_equal(group.current_tee_order(), session.tee_order, "group stores authoritative tee order")

	var tee_order: Array = session.tee_order.duplicate()
	for tee_sequence in range(tee_order.size()):
		var expected_member: int = int(tee_order[tee_sequence])
		var turn: Dictionary = session.current_turn()
		_assert_equal(int(turn.get("member_index", -1)), expected_member, "next tee golfer follows honors order at slot %d" % tee_sequence)
		_assert_equal(str(turn.get("order_reason", "")), "TEE_ORDER", "tee turn is explicitly authoritative")

		var before_counts: Array = session.member_shots_played.duplicate()
		var played: Dictionary = session.play_current_turn()
		_assert_true(bool(played.get("played", false)), "authoritative tee shot executes at slot %d" % tee_sequence)
		_assert_equal(session.turn_history.size(), tee_sequence + 1, "one turn-history event is added per tee shot")
		for member_index in range(group.member_count()):
			var expected_count: int = int(before_counts[member_index]) + (1 if member_index == expected_member else 0)
			_assert_equal(int(session.member_shots_played[member_index]), expected_count, "only selected golfer advances on tee turn %d member %d" % [tee_sequence, member_index])

	var hole = course.hole_by_number(1)
	var expected_away: int = _farthest_active_member(group, hole.pin_position)
	_assert_true(expected_away >= 0, "at least one golfer remains active after tee shots")
	if expected_away >= 0:
		var away_turn: Dictionary = session.current_turn()
		_assert_equal(str(away_turn.get("order_reason", "")), "AWAY", "away order takes over only after all tee shots")
		_assert_equal(int(away_turn.get("member_index", -1)), expected_away, "live farthest golfer is selected next")

	var additional_turns: int = 0
	while not session.is_complete() and not session.has_failed() and additional_turns < 100:
		var step: Dictionary = session.play_current_turn()
		if step.is_empty():
			break
		additional_turns += 1

	_assert_true(not session.has_failed(), "incremental session completes without authority failure")
	_assert_true(session.is_complete(), "incremental session completes the whole group hole")
	_assert_true(additional_turns < 100, "incremental group play remains bounded")

	var result: Dictionary = session.result()
	_assert_true(bool(result.get("completed", false)), "session result reports completed hole")
	_assert_equal(result.get("member_results", []).size(), 3, "one final authoritative result exists per golfer")
	for member_result_value in result.get("member_results", []):
		var member_result: Dictionary = member_result_value
		_assert_true(bool(member_result.get("recorded", false)), "member hole result is recorded into round authority")
		_assert_true(not member_result.get("history", []).is_empty(), "member result retains authoritative shot history")

	_assert_equal(group.current_hole_number(), 2, "group advances only after every member finishes hole one")
	for member_index in range(group.member_count()):
		_assert_equal(group.rounds[member_index].round_state.holes_completed(), 1, "member %d owns exactly one completed hole" % member_index)

	# Backward compatibility: the old whole-hole API now drives the same live
	# session automatically and must preserve the POC-23 contract.
	var legacy_result: Dictionary = coordinator.play_current_hole(group, 26101)
	_assert_true(bool(legacy_result.get("completed", false)), "whole-hole compatibility facade still completes hole two")
	_assert_equal(legacy_result.get("member_results", []).size(), 3, "whole-hole facade still returns one result per golfer")
	_assert_equal(group.current_hole_number(), 3, "whole-hole facade advances group to hole three")

	print("POC26A_INCREMENTAL_SESSION_SUMMARY tee_order=%s hole1_turns=%d next_hole=%d" % [str(tee_order), session.turn_history.size(), group.current_hole_number()])
	_finish()


func _farthest_active_member(group, pin_position: Vector3) -> int:
	var selected_member: int = -1
	var selected_distance: float = -1.0
	for member_index in range(group.member_count()):
		var autonomous_round = group.rounds[member_index]
		if autonomous_round == null or not autonomous_round.has_active_hole():
			continue
		var distance: float = autonomous_round.active_hole_state.ball_position.distance_to(pin_position)
		if selected_member < 0 or distance > selected_distance + 0.001 or (abs(distance - selected_distance) <= 0.001 and member_index < selected_member):
			selected_member = member_index
			selected_distance = distance
	return selected_member


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
		print("POC-26A AUTHORITATIVE INCREMENTAL GROUP HOLE SESSION PASSED")
		quit(0)
	else:
		push_error("POC-26A AUTHORITATIVE INCREMENTAL GROUP HOLE SESSION FAILED: %d" % failures)
		quit(1)
