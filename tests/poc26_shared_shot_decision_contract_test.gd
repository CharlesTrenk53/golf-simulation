extends SceneTree

const CourseDefinition = preload("res://simulation/course_definition.gd")
const DataDefinedAutonomousHole = preload("res://simulation/data_defined_autonomous_hole.gd")
const ShotDecisionContract = preload("res://simulation/shot_decision_contract.gd")
const Golfer = preload("res://scenes/golfer.gd")

var failures: int = 0
var golfer = null


func _init() -> void:
	print("POC-26B: shared AI/human shot decision contract")
	var course = CourseDefinition.load_json("res://data/courses/poc12_proving_course.json")
	_assert_true(course != null, "three-hole proving course loads")
	if course == null:
		_finish()
		return
	var hole = course.hole_by_number(1)
	_assert_true(hole != null, "hole one loads")
	if hole == null:
		_finish()
		return

	golfer = Golfer.new()
	golfer.profile = Golfer.GolferProfile.CAREFUL_CARL
	golfer.apply_profile()
	get_root().add_child(golfer)

	_test_course_strategy_contract(hole)
	_test_ai_contract(hole)
	_test_putting_contract(hole)
	_finish()


func _test_course_strategy_contract(hole) -> void:
	var playable = DataDefinedAutonomousHole.new(hole, "default")
	var state = playable.create_state(26101)
	var contract = ShotDecisionContract.new()
	var package: Dictionary = contract.prepare(playable, golfer, state)
	_assert_true(not package.is_empty(), "authority prepares a tee-shot decision")
	_assert_equal(str(package.get("decision_kind", "")), "COURSE_STRATEGY", "tee shot uses course-strategy decision contract")
	var choices: Array = package.get("choices", [])
	_assert_true(not choices.is_empty(), "decision exposes at least one authoritative candidate")
	_assert_true(_has_course_intent(choices), "course candidates expose shot intent as part of the human choice")
	_assert_equal(int(package.get("situation", {}).get("shot_number", 0)), 1, "decision situation identifies first shot")
	_assert_equal(str(package.get("situation", {}).get("surface", "")), "TEE", "decision situation exposes authoritative lie")

	var strokes_before: int = int(state.strokes)
	var invalid: Dictionary = contract.execute_candidate(choices.size() + 10, "HUMAN")
	_assert_true(not bool(invalid.get("executed", false)), "invalid human candidate is rejected")
	_assert_equal(str(invalid.get("reason", "")), "INVALID_CANDIDATE_INDEX", "invalid candidate has explicit rejection reason")
	_assert_equal(int(state.strokes), strokes_before, "rejected command cannot mutate authoritative state")
	_assert_true(contract.has_pending_decision(), "valid pending decision survives rejected command")

	var human_index: int = _last_human_selectable_index(choices)
	_assert_true(human_index >= 0, "course strategy offers a human-selectable intent")
	var decision_id: String = str(package.get("decision_id", ""))
	var execution: Dictionary = contract.execute_candidate(human_index, "HUMAN")
	_assert_true(bool(execution.get("executed", false)), "human-selected intent executes authoritatively")
	_assert_equal(str(execution.get("choice_source", "")), "HUMAN", "execution records human decision source")
	_assert_equal(str(execution.get("decision_id", "")), decision_id, "execution preserves decision identity")
	var shot: Dictionary = execution.get("shot", {})
	_assert_equal(
		int(state.strokes),
		strokes_before + 1 + int(shot.get("penalty_strokes", 0)),
		"human choice records one played stroke plus authoritative penalties"
	)
	_assert_equal(str(shot.get("choice_source", "")), "HUMAN", "authoritative shot history carries human provenance")
	_assert_equal(str(shot.get("decision_id", "")), decision_id, "authoritative shot carries matching decision id")
	_assert_true(not shot.get("selected_option", {}).is_empty(), "human shot retains exact authoritative selected option")
	_assert_true(not shot.get("predicted_flight", {}).is_empty(), "human course shot uses existing shot-intent flight pipeline")
	_assert_equal(playable.autonomous.shot_history.size(), 1, "human execution appears exactly once in authoritative shot history")
	_assert_equal(str(playable.autonomous.shot_history[0].get("decision_id", "")), decision_id, "stored history preserves decision provenance")
	_assert_true(not contract.has_pending_decision(), "executed decision cannot be replayed")


func _test_ai_contract(hole) -> void:
	var playable = DataDefinedAutonomousHole.new(hole, "default")
	var state = playable.create_state(26102)
	var contract = ShotDecisionContract.new()
	var package: Dictionary = contract.prepare(playable, golfer, state)
	_assert_true(not package.is_empty(), "same contract prepares an AI decision")
	var ai_index: int = contract.choose_ai_candidate()
	_assert_true(ai_index >= 0, "AI resolves one candidate index from shared contract")
	var choices: Array = package.get("choices", [])
	_assert_true(ai_index < choices.size(), "AI candidate index belongs to authority-issued choices")
	var execution: Dictionary = contract.execute_candidate(ai_index, "AI")
	_assert_true(bool(execution.get("executed", false)), "AI candidate executes through shared authority")
	_assert_equal(str(execution.get("choice_source", "")), "AI", "AI execution records AI decision source")
	var shot: Dictionary = execution.get("shot", {})
	_assert_equal(
		int(state.strokes),
		1 + int(shot.get("penalty_strokes", 0)),
		"AI shared-contract execution records one played stroke plus authoritative penalties"
	)
	_assert_equal(playable.autonomous.shot_history.size(), 1, "AI execution also appears exactly once in authoritative history")


func _test_putting_contract(hole) -> void:
	var playable = DataDefinedAutonomousHole.new(hole, "default")
	var state = playable.create_state(26103)
	# Put the ball safely inside the authored green so this test can exercise the
	# putting decision seam directly without depending on preceding stochastic shots.
	state.ball_position = hole.pin_position + Vector3(1.0, 0.0, 0.0)
	state._refresh_lie()
	_assert_equal(state.surface_name(), "GREEN", "direct putting proof starts on authored green")

	var contract = ShotDecisionContract.new()
	var package: Dictionary = contract.prepare(playable, golfer, state)
	_assert_true(not package.is_empty(), "authority prepares a putting decision")
	_assert_equal(str(package.get("decision_kind", "")), "PUTTING", "green play uses putting decision contract")
	var choices: Array = package.get("choices", [])
	_assert_true(choices.size() >= 4, "putting contract contains AI profile plus human pace choices")
	var labels: Array = _human_putting_labels(choices)
	_assert_true(labels.has("LAG"), "human can choose lag pace")
	_assert_true(labels.has("NEUTRAL"), "human can choose neutral pace")
	_assert_true(labels.has("ATTACK"), "human can choose attack pace")

	var ai_index: int = contract.choose_ai_candidate()
	_assert_true(ai_index >= 0, "putting AI has a recommended contract candidate")
	_assert_true(not bool(choices[ai_index].get("human_selectable", true)), "exact AI putting profile is not masqueraded as a human choice")
	var rejected_auto: Dictionary = contract.execute_candidate(ai_index, "HUMAN")
	_assert_true(not bool(rejected_auto.get("executed", false)), "human cannot submit hidden AI-profile candidate")
	_assert_equal(int(state.strokes), 0, "rejected AI-profile submission cannot move the ball")

	var attack_index: int = _putting_choice_index(choices, "ATTACK")
	_assert_true(attack_index >= 0, "attack putting choice resolves to authority candidate")
	var execution: Dictionary = contract.execute_candidate(attack_index, "HUMAN")
	_assert_true(bool(execution.get("executed", false)), "human attack putt executes through putting models")
	var shot: Dictionary = execution.get("shot", {})
	_assert_equal(str(shot.get("putting_strategy", "")), "ATTACK", "selected human putting pace reaches authoritative execution")
	_assert_equal(str(shot.get("choice_source", "")), "HUMAN", "putt records human decision source")
	_assert_true(shot.has("putting"), "human putt retains full POC-15 putting diagnostics")
	_assert_equal(str(shot.get("putting", {}).get("strategy", {}).get("strategy", "")), "ATTACK", "POC-15 execution receives selected putting strategy")
	_assert_equal(int(state.strokes), 1, "human putt advances exactly one stroke")
	_assert_equal(playable.autonomous.shot_history.size(), 1, "human putt is stored exactly once in authoritative history")


func _has_course_intent(choices: Array) -> bool:
	for choice in choices:
		if typeof(choice) == TYPE_DICTIONARY and not choice.get("intent", {}).is_empty():
			return true
	return false


func _last_human_selectable_index(choices: Array) -> int:
	for index in range(choices.size() - 1, -1, -1):
		if bool(choices[index].get("human_selectable", false)):
			return index
	return -1


func _human_putting_labels(choices: Array) -> Array:
	var labels: Array = []
	for choice in choices:
		if bool(choice.get("human_selectable", false)):
			labels.append(str(choice.get("putting_strategy", "")))
	return labels


func _putting_choice_index(choices: Array, label: String) -> int:
	for index in range(choices.size()):
		if bool(choices[index].get("human_selectable", false)) and str(choices[index].get("putting_strategy", "")) == label:
			return index
	return -1


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
	if golfer != null:
		golfer.queue_free()
	if failures == 0:
		print("POC-26B SHARED AI/HUMAN SHOT DECISION CONTRACT PASSED")
		quit(0)
	else:
		push_error("POC-26B SHARED AI/HUMAN SHOT DECISION CONTRACT FAILED: %d" % failures)
		quit(1)
