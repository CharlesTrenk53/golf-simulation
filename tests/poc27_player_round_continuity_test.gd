extends SceneTree

const POC27Course = preload("res://simulation/poc27_eighteen_hole_course.gd")
const ShotProgressiveLivingCourseController = preload("res://simulation/shot_progressive_living_course_controller.gd")
const QuietGolfer = preload("res://tests/quiet_golfer.gd")
const Golfer = preload("res://scenes/golfer.gd")

const PLAYER_GROUP := "player_group"
const OTHER_GROUP := "other_group"
const HUMAN_MEMBER := 0
const STEP_SECONDS := 30.0
const THINK_WAIT_SECONDS := 240.0
const MAX_ITERATIONS := 2500

var failures: int = 0
var created_golfers: Array = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("POC-27D: full 18-hole player round continuity")
	var course = POC27Course.build()
	_assert_true(course != null, "POC-27 18-hole course builds")
	if course == null:
		_finish()
		return

	var runtime = ShotProgressiveLivingCourseController.new()
	_assert_true(runtime.configure(course), "ordinary shot-progressive living controller configures")

	var player_group_golfers := [
		_new_golfer(Golfer.GolferProfile.CAREFUL_CARL),
		_new_golfer(Golfer.GolferProfile.WILD_BILL),
		_new_golfer(Golfer.GolferProfile.RECKLESS_RICK),
		_new_golfer(Golfer.GolferProfile.CAREFUL_CARL)
	]
	var other_group_golfers := [
		_new_golfer(Golfer.GolferProfile.WILD_BILL),
		_new_golfer(Golfer.GolferProfile.RECKLESS_RICK),
		_new_golfer(Golfer.GolferProfile.CAREFUL_CARL),
		_new_golfer(Golfer.GolferProfile.WILD_BILL)
	]

	_assert_true(runtime.add_group(PLAYER_GROUP, player_group_golfers, "default", HUMAN_MEMBER, 30100), "human joins as one ordinary member of a normal foursome")
	_assert_true(runtime.add_group(OTHER_GROUP, other_group_golfers, "default", -1, 31100), "autonomous foursome joins the same living course")
	_assert_equal_int(int(runtime.group_controls[PLAYER_GROUP].get("human_member_index", -1)), HUMAN_MEMBER, "human control designation is persistent group configuration")

	var opening: Dictionary = runtime.release_next_group()
	_assert_true(bool(opening.get("released", false)), "player group releases first through normal tee queue")
	var blocked_opening: Dictionary = runtime.release_next_group()
	_assert_true(not bool(blocked_opening.get("released", false)), "following group initially obeys live first-tee safety")

	var player_group = runtime.living_course.population.group_by_id(PLAYER_GROUP)
	var other_group = runtime.living_course.population.group_by_id(OTHER_GROUP)
	_assert_true(player_group != null and other_group != null, "both groups retain ordinary living-course identity")
	if player_group == null or other_group == null:
		_finish()
		return

	var player_holes_seen: Dictionary = {}
	var human_decision_holes: Dictionary = {}
	var human_shot_holes: Dictionary = {}
	var think_wait_performed: bool = false
	var think_wait_other_progress: bool = false
	var saw_front_nine_human_turn: bool = false
	var saw_back_nine_human_turn: bool = false
	var human_turns: int = 0
	var iterations: int = 0

	while iterations < MAX_ITERATIONS and not _world_complete(runtime, player_group, other_group):
		iterations += 1

		for group_id in [PLAYER_GROUP, OTHER_GROUP]:
			if runtime.live_sessions.has(group_id):
				var live_session = runtime.live_sessions[group_id]
				if live_session != null and live_session.has_failed():
					push_error("POC27D FAILED SESSION group=%s snapshot=%s" % [group_id, str(live_session.snapshot())])
					failures += 1
					_finish()
					return

		var player_hole: int = int(runtime.traffic.group_hole(PLAYER_GROUP))
		var other_hole: int = int(runtime.traffic.group_hole(OTHER_GROUP))
		if player_hole > 0:
			player_holes_seen[player_hole] = true

		if iterations <= 20 or iterations % 100 == 0:
			print("POC27D PROGRESS iteration=%d time=%.1f player_hole=%d other_hole=%d player_shots=%d other_shots=%d blocked=%d" % [
				iterations,
				runtime.current_time_seconds,
				player_hole,
				other_hole,
				runtime.group_live_shot_count(PLAYER_GROUP),
				runtime.group_live_shot_count(OTHER_GROUP),
				runtime.blocked_transitions.size()
			])

		var decision: Dictionary = runtime.pending_human_decision(PLAYER_GROUP)
		if not decision.is_empty():
			var decision_hole: int = player_hole if player_hole > 0 else player_group.current_hole_number()
			human_decision_holes[decision_hole] = true
			if decision_hole <= 9:
				saw_front_nine_human_turn = true
			else:
				saw_back_nine_human_turn = true

			if not think_wait_performed and decision_hole >= 2 and other_hole > 0 and str(other_group.status) != "FINISHED":
				var before_time: float = runtime.current_time_seconds
				var before_player_shots: int = runtime.group_live_shot_count(PLAYER_GROUP)
				var before_other_shots: int = runtime.group_live_shot_count(OTHER_GROUP)
				var before_decision_id: String = str(decision.get("decision_id", ""))
				var human_round = player_group.rounds[HUMAN_MEMBER]
				var before_ball: Vector3 = human_round.active_hole_state.ball_position
				var before_strokes: int = int(human_round.active_hole_state.strokes)

				runtime.advance_time(THINK_WAIT_SECONDS)
				think_wait_performed = true
				_assert_near(runtime.current_time_seconds, before_time + THINK_WAIT_SECONDS, 0.0001, "global course clock advances during deliberate human think time")
				_assert_equal_int(runtime.group_live_shot_count(PLAYER_GROUP), before_player_shots, "player group does not autoplay through pending human turn")
				_assert_true(human_round.active_hole_state.ball_position == before_ball, "human authoritative lie remains unchanged while deciding")
				_assert_equal_int(int(human_round.active_hole_state.strokes), before_strokes, "human stroke count remains unchanged while deciding")
				var after_wait_decision: Dictionary = runtime.pending_human_decision(PLAYER_GROUP)
				_assert_equal_str(str(after_wait_decision.get("decision_id", "")), before_decision_id, "same authoritative decision survives think time")
				think_wait_other_progress = runtime.group_live_shot_count(OTHER_GROUP) > before_other_shots
				_assert_true(think_wait_other_progress, "other group continues real golf while human thinks")
				decision = after_wait_decision

			var candidate_index: int = _preferred_human_candidate(decision)
			_assert_true(candidate_index >= 0, "pending human turn exposes a selectable authoritative candidate")
			if candidate_index < 0:
				break
			var submitted: Dictionary = runtime.submit_human_choice(PLAYER_GROUP, candidate_index)
			_assert_true(bool(submitted.get("played", false)), "human choice executes through the normal authoritative contract")
			if not bool(submitted.get("played", false)):
				break
			human_turns += 1
			var shot_event: Dictionary = submitted.get("shot_event", {})
			var shot_hole: int = int(shot_event.get("hole_number", decision_hole))
			human_shot_holes[shot_hole] = true
			continue

		runtime.advance_time(STEP_SECONDS)

	_assert_true(iterations < MAX_ITERATIONS, "18-hole mixed player round remains bounded")
	_assert_true(_world_complete(runtime, player_group, other_group), "player and autonomous group both finish the full living round")
	_assert_true(think_wait_performed, "round contains a deliberate live human think period")
	_assert_true(think_wait_other_progress, "living course continues during that think period")
	_assert_true(saw_front_nine_human_turn and saw_back_nine_human_turn, "human control persists across both nines")
	_assert_equal_int(player_holes_seen.size(), 18, "same player group reaches all 18 holes")
	_assert_equal_int(human_decision_holes.size(), 18, "human receives authoritative decisions on every hole")
	_assert_equal_int(human_shot_holes.size(), 18, "human executes at least one authoritative shot on every hole")
	_assert_true(human_decision_holes.has(2) and human_decision_holes.has(17), "Hole 17 uses the same player decision seam already proven on Hole 2")

	var live_start_count: int = 0
	var live_finish_count: int = 0
	var wait_count: int = 0
	var human_live_shots: int = 0
	var ai_live_shots: int = 0
	var human_putts: int = 0
	var human_full_shots: int = 0
	var penalty_events: int = 0
	var provenance_ok: bool = true
	var order_contract_ok: bool = true
	var player_finished_holes: Dictionary = {}

	for event_value in runtime.event_history:
		if typeof(event_value) != TYPE_DICTIONARY:
			continue
		var event: Dictionary = event_value
		var event_type: String = str(event.get("type", ""))
		if event_type == "LIVE_HOLE_START":
			live_start_count += 1
		elif event_type == "LIVE_INTER_HOLE_WAIT":
			wait_count += 1
		elif event_type == "LIVE_HOLE_FINISH":
			live_finish_count += 1
			if str(event.get("group_id", "")) == PLAYER_GROUP:
				var hole_number: int = int(event.get("hole_number", 0))
				player_finished_holes[hole_number] = true
				var play_result: Dictionary = event.get("play_result", {})
				if int(play_result.get("human_member_index", -1)) != HUMAN_MEMBER:
					order_contract_ok = false
				var tee_order: Array = play_result.get("tee_order", [])
				var turn_history: Array = play_result.get("turn_history", [])
				if tee_order.size() != 4 or turn_history.size() < 4:
					order_contract_ok = false
				else:
					for turn_index in range(mini(4, turn_history.size())):
						var turn: Dictionary = turn_history[turn_index]
						if str(turn.get("order_reason", "")) != "TEE_ORDER" or int(turn.get("member_index", -1)) != int(tee_order[turn_index]):
							order_contract_ok = false
					for turn_index in range(4, turn_history.size()):
						if str(turn_history[turn_index].get("order_reason", "")) != "AWAY":
							order_contract_ok = false
		elif event_type == "LIVE_SHOT":
			var event_group: String = str(event.get("group_id", ""))
			var member_index: int = int(event.get("member_index", -1))
			var expected_source: String = "HUMAN" if event_group == PLAYER_GROUP and member_index == HUMAN_MEMBER else "AI"
			if str(event.get("control_source", "")) != expected_source or str(event.get("choice_source", "")) != expected_source:
				provenance_ok = false
			if str(event.get("decision_id", "")).is_empty():
				provenance_ok = false
			if expected_source == "HUMAN":
				human_live_shots += 1
				var shot: Dictionary = event.get("shot", {})
				if str(shot.get("club_id", "")) == "PUTTER" or int(shot.get("shot_type", -1)) == 3 or not shot.get("putting", {}).is_empty():
					human_putts += 1
				else:
					human_full_shots += 1
			else:
				ai_live_shots += 1
			if int(event.get("penalty_strokes", 0)) > 0:
				penalty_events += 1

	_assert_equal_int(live_start_count, 36, "two groups start exactly 18 authoritative holes each")
	_assert_equal_int(live_finish_count, 36, "two groups finish exactly 18 authoritative holes each")
	_assert_equal_int(player_finished_holes.size(), 18, "player group records one authoritative finish for every hole")
	_assert_true(wait_count > 0, "real inter-hole traffic waits occur during the player round")
	_assert_true(provenance_ok, "every live shot retains correct HUMAN versus AI provenance and decision identity")
	_assert_true(order_contract_ok, "all 18 player-group holes preserve tee honors before away order")
	_assert_true(human_live_shots == human_turns and human_live_shots > 18, "every scripted human turn maps to exactly one authoritative human shot")
	_assert_true(ai_live_shots > 0, "AI partners and the other group remain active throughout the same round")
	_assert_true(human_full_shots > 0 and human_putts > 0, "human continuity spans both full-shot and putting pipelines")

	_assert_equal_str(str(player_group.status), "FINISHED", "same ordinary player group finishes Hole 18")
	_assert_equal_str(str(other_group.status), "FINISHED", "autonomous group also finishes normally")
	_assert_equal_int(runtime.traffic.group_hole(PLAYER_GROUP), 0, "player group clears traffic after Hole 18")
	_assert_equal_int(runtime.traffic.group_hole(OTHER_GROUP), 0, "other group clears traffic after Hole 18")
	_assert_true(runtime.live_sessions.is_empty(), "no live sessions remain after the round")
	_assert_true(runtime.blocked_transitions.is_empty(), "no blocked transitions remain after the round")

	for group_value in [player_group, other_group]:
		for autonomous_round in group_value.rounds:
			_assert_true(autonomous_round.round_state.complete, "%s member RoundState completes" % str(group_value.group_id))
			_assert_equal_int(autonomous_round.round_state.holes_completed(), 18, "%s member records all 18 holes" % str(group_value.group_id))
			_assert_equal_int(autonomous_round.hole_results.size(), 18, "%s member retains 18 authoritative hole results" % str(group_value.group_id))

	print("POC27D_PLAYER_CONTINUITY_SUMMARY time=%.1f human_turns=%d human_full_shots=%d human_putts=%d ai_shots=%d waits=%d penalties=%d iterations=%d" % [
		runtime.current_time_seconds,
		human_live_shots,
		human_full_shots,
		human_putts,
		ai_live_shots,
		wait_count,
		penalty_events,
		iterations
	])
	_finish()


func _world_complete(runtime, player_group, other_group) -> bool:
	if str(player_group.status) != "FINISHED" or str(other_group.status) != "FINISHED":
		return false
	if runtime.traffic.group_hole(PLAYER_GROUP) != 0 or runtime.traffic.group_hole(OTHER_GROUP) != 0:
		return false
	return runtime.live_sessions.is_empty() and runtime.blocked_transitions.is_empty()


func _preferred_human_candidate(decision: Dictionary) -> int:
	var choices: Array = decision.get("choices", [])
	if str(decision.get("decision_kind", "")) == "PUTTING":
		for index in range(choices.size()):
			if typeof(choices[index]) == TYPE_DICTIONARY:
				var choice: Dictionary = choices[index]
				if bool(choice.get("human_selectable", false)) and str(choice.get("putting_strategy", "")) == "NEUTRAL":
					return int(choice.get("index", index))
	for index in range(choices.size()):
		if typeof(choices[index]) == TYPE_DICTIONARY and bool(choices[index].get("human_selectable", false)):
			return int(choices[index].get("index", index))
	return -1


func _new_golfer(profile: int):
	var golfer = QuietGolfer.new()
	golfer.profile = profile
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
		print("PASS: %s (actual=%.4f expected=%.4f)" % [label, actual, expected])
	else:
		failures += 1
		push_error("FAIL: %s (actual=%.4f expected=%.4f)" % [label, actual, expected])


func _finish() -> void:
	for golfer in created_golfers:
		if golfer != null and is_instance_valid(golfer):
			golfer.queue_free()
	if failures == 0:
		print("POC-27D FULL 18-HOLE PLAYER ROUND CONTINUITY PASSED")
		quit(0)
	else:
		push_error("POC-27D FULL 18-HOLE PLAYER ROUND CONTINUITY FAILED: %d" % failures)
		quit(1)
