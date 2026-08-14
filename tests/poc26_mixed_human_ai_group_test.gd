extends SceneTree

const CourseDefinition = preload("res://simulation/course_definition.gd")
const CoursePopulation = preload("res://simulation/course_population.gd")
const GroupProgressionCoordinator = preload("res://simulation/group_progression_coordinator.gd")
const GroupTeeOrderModel = preload("res://simulation/group_tee_order_model.gd")
const Golfer = preload("res://scenes/golfer.gd")

var failures: int = 0
var created_golfers: Array = []


func _init() -> void:
	print("POC-26C: mixed human/AI golfer group")
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
	_assert_true(population.add_group("mixed_group", golfers), "mixed threesome enters normal population")
	_assert_true(population.start_group("mixed_group"), "mixed group starts normally")
	var group = population.group_by_id("mixed_group")

	# Pick the second member in the deterministic opening tee order as the human.
	# This guarantees an AI turn exists immediately before the first human turn,
	# which lets the proof exercise out-of-turn rejection and automatic AI play.
	var seed_value: int = 26201
	var tee_model = GroupTeeOrderModel.new()
	var expected_order: Array = tee_model.first_tee_order(group.member_count(), seed_value + 7919)
	_assert_equal(expected_order.size(), 3, "deterministic opening order contains all three members")
	if expected_order.size() != 3:
		_finish()
		return
	var human_member: int = int(expected_order[1])
	var first_ai_member: int = int(expected_order[0])

	var coordinator = GroupProgressionCoordinator.new()
	var session = coordinator.begin_session(group, seed_value, human_member)
	_assert_true(session != null, "mixed authoritative group session begins")
	if session == null:
		_finish()
		return

	_assert_equal(session.tee_order, expected_order, "mixed session preserves normal seeded tee order")
	_assert_equal(session.human_member_index, human_member, "one ordinary group member is designated human-controlled")
	var first_turn: Dictionary = session.current_turn()
	_assert_equal(int(first_turn.get("member_index", -1)), first_ai_member, "first tee slot belongs to autonomous partner")
	_assert_equal(str(first_turn.get("control_source", "")), "AI", "first tee slot is identified as AI-controlled")

	var human_round = group.rounds[human_member]
	var human_strokes_before: int = int(human_round.active_hole_state.strokes)
	var out_of_turn: Dictionary = session.submit_human_choice(human_member, 0)
	_assert_true(bool(out_of_turn.get("rejected", false)), "human command before human turn is rejected")
	_assert_equal(str(out_of_turn.get("reason", "")), "OUT_OF_TURN", "out-of-turn rejection is explicit")
	_assert_equal(int(human_round.active_hole_state.strokes), human_strokes_before, "out-of-turn command cannot mutate human ball state")
	_assert_equal(session.turn_history.size(), 0, "out-of-turn command cannot create a played turn")

	var ai_tee: Dictionary = session.play_current_turn()
	_assert_true(bool(ai_tee.get("played", false)), "AI partner automatically plays authoritative first tee shot")
	_assert_equal(str(ai_tee.get("shot", {}).get("choice_source", "")), "AI", "AI tee shot uses shared decision contract")
	_assert_equal(session.turn_history.size(), 1, "AI tee shot creates exactly one group turn-history event")

	var human_turn: Dictionary = session.current_turn()
	_assert_equal(int(human_turn.get("member_index", -1)), human_member, "normal tee order reaches designated human member")
	_assert_equal(str(human_turn.get("control_source", "")), "HUMAN", "human turn is identified by session authority")
	var human_history_before: int = session.turn_history.size()
	var pause_one: Dictionary = session.play_current_turn()
	_assert_true(not bool(pause_one.get("played", true)), "human turn does not silently auto-play")
	_assert_true(bool(pause_one.get("awaiting_human", false)), "human turn yields a pending decision")
	var decision_one: Dictionary = pause_one.get("decision", {})
	_assert_true(not decision_one.is_empty(), "pending human decision exposes authoritative choices")
	var decision_id: String = str(decision_one.get("decision_id", ""))
	_assert_true(not decision_id.is_empty(), "pending human decision has stable identity")
	_assert_equal(int(human_round.active_hole_state.strokes), human_strokes_before, "preparing human decision does not play a stroke")
	_assert_equal(session.turn_history.size(), human_history_before, "waiting for human input does not create turn history")

	var pause_two: Dictionary = session.play_current_turn()
	_assert_true(bool(pause_two.get("awaiting_human", false)), "repeated advance attempt still waits for human")
	_assert_equal(str(pause_two.get("decision", {}).get("decision_id", "")), decision_id, "pending human decision remains stable while waiting")
	_assert_equal(int(human_round.active_hole_state.strokes), human_strokes_before, "repeated wait cannot move human ball")

	var first_choices: Array = decision_one.get("choices", [])
	var invalid_choice: Dictionary = session.submit_human_choice(human_member, first_choices.size() + 5)
	_assert_true(bool(invalid_choice.get("rejected", false)), "invalid in-turn human candidate is rejected")
	_assert_equal(str(invalid_choice.get("reason", "")), "INVALID_CANDIDATE_INDEX", "invalid human candidate preserves contract rejection reason")
	_assert_equal(int(human_round.active_hole_state.strokes), human_strokes_before, "invalid in-turn choice cannot play a stroke")
	_assert_equal(session.turn_history.size(), human_history_before, "invalid in-turn choice cannot create turn history")

	var first_human_choice: int = _preferred_human_candidate(decision_one)
	_assert_true(first_human_choice >= 0, "human has at least one selectable authoritative candidate")
	var human_tee: Dictionary = session.submit_human_choice(human_member, first_human_choice)
	_assert_true(bool(human_tee.get("played", false)), "valid human tee choice executes authoritatively")
	_assert_equal(str(human_tee.get("shot", {}).get("choice_source", "")), "HUMAN", "human tee shot records human provenance")
	_assert_equal(str(human_tee.get("shot", {}).get("decision_id", "")), decision_id, "human tee shot executes the pending decision identity")
	_assert_equal(session.turn_history.size(), human_history_before + 1, "human tee execution appears exactly once in group turn history")

	var human_turns: int = 1
	var ai_turns: int = 1
	var continuation_turns: int = 0
	while not session.is_complete() and not session.has_failed() and continuation_turns < 100:
		var turn: Dictionary = session.current_turn()
		if turn.is_empty():
			break
		var member_index: int = int(turn.get("member_index", -1))
		if member_index == human_member:
			var waiting: Dictionary = session.play_current_turn()
			if not bool(waiting.get("awaiting_human", false)):
				failures += 1
				push_error("FAIL: later human turn must pause for explicit input")
				break
			var decision: Dictionary = waiting.get("decision", {})
			var candidate_index: int = _preferred_human_candidate(decision)
			if candidate_index < 0:
				failures += 1
				push_error("FAIL: later human turn has no selectable candidate")
				break
			var played_human: Dictionary = session.submit_human_choice(human_member, candidate_index)
			if not bool(played_human.get("played", false)):
				failures += 1
				push_error("FAIL: later human choice failed to execute")
				break
			human_turns += 1
		else:
			var played_ai: Dictionary = session.play_current_turn()
			if not bool(played_ai.get("played", false)):
				failures += 1
				push_error("FAIL: autonomous partner turn failed to execute")
				break
			ai_turns += 1
		continuation_turns += 1

	_assert_true(not session.has_failed(), "mixed group completes without authority failure")
	_assert_true(session.is_complete(), "mixed human/AI group completes the hole")
	_assert_true(continuation_turns < 100, "mixed group play remains bounded")
	_assert_true(human_turns > 0, "human participates in at least one real golf turn")
	_assert_true(ai_turns > 0, "autonomous partners participate in real golf turns")
	_assert_equal(session.turn_history.size(), human_turns + ai_turns, "every completed mixed turn appears exactly once in history")
	_assert_equal(int(session.member_shots_played[human_member]), human_turns, "human shot counter equals submitted human decisions")

	var provenance_ok: bool = true
	for event_value in session.turn_history:
		var event: Dictionary = event_value
		var event_member: int = int(event.get("member_index", -1))
		var expected_source: String = "HUMAN" if event_member == human_member else "AI"
		if str(event.get("choice_source", "")) != expected_source:
			provenance_ok = false
			break
	_assert_true(provenance_ok, "turn history preserves human versus AI decision provenance")

	var result: Dictionary = session.result()
	_assert_true(bool(result.get("completed", false)), "mixed session result records completed hole")
	_assert_equal(result.get("member_results", []).size(), 3, "all mixed-group members own final authoritative results")
	var member_history_provenance_ok: bool = true
	for member_result_value in result.get("member_results", []):
		var member_result: Dictionary = member_result_value
		var member_index: int = int(member_result.get("member_index", -1))
		var expected_source: String = "HUMAN" if member_index == human_member else "AI"
		for shot_value in member_result.get("history", []):
			var shot: Dictionary = shot_value
			if str(shot.get("choice_source", "")) != expected_source:
				member_history_provenance_ok = false
				break
	_assert_true(member_history_provenance_ok, "authoritative round histories preserve mixed control provenance")

	_assert_equal(group.current_hole_number(), 2, "group advances only after human and AI members all finish")
	for member_index in range(group.member_count()):
		_assert_equal(group.rounds[member_index].round_state.holes_completed(), 1, "mixed member %d owns exactly one completed hole" % member_index)

	print("POC26C_MIXED_GROUP_SUMMARY tee_order=%s human_member=%d human_turns=%d ai_turns=%d next_hole=%d" % [
		str(session.tee_order),
		human_member,
		human_turns,
		ai_turns,
		group.current_hole_number()
	])
	_finish()


func _preferred_human_candidate(decision: Dictionary) -> int:
	var choices: Array = decision.get("choices", [])
	if str(decision.get("decision_kind", "")) == "PUTTING":
		for index in range(choices.size()):
			var choice: Dictionary = choices[index]
			if bool(choice.get("human_selectable", false)) and str(choice.get("putting_strategy", "")) == "NEUTRAL":
				return index
	for index in range(choices.size()):
		if bool(choices[index].get("human_selectable", false)):
			return index
	return -1


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
		print("POC-26C MIXED HUMAN/AI GOLFER GROUP PASSED")
		quit(0)
	else:
		push_error("POC-26C MIXED HUMAN/AI GOLFER GROUP FAILED: %d" % failures)
		quit(1)
