extends SceneTree

const GolferScript = preload("res://scenes/golfer.gd")
const HoleDefinition = preload("res://simulation/hole_definition.gd")
const DataDefinedAutonomousHole = preload("res://simulation/data_defined_autonomous_hole.gd")

var failures: int = 0


func _init() -> void:
	print("POC-13D/F: autonomous club + target strategy selection")
	var hole = HoleDefinition.load_json("res://data/courses/poc11_test_hole.json")
	_assert_true(hole != null, "Decision Point loads")
	if hole == null:
		quit(1)
		return

	var playable = DataDefinedAutonomousHole.new(hole)
	var state = playable.create_state(13130)
	var golfer = GolferScript.new()
	golfer.profile = golfer.GolferProfile.CAREFUL_CARL
	golfer.apply_profile()
	golfer.set_meta("course_management", 88.0)

	var decision: Dictionary = playable.choose_course_strategy(golfer, state)
	var chosen: Dictionary = decision.get("chosen", {})
	var evaluated: Array = decision.get("evaluated", [])

	_assert_true(not chosen.is_empty(), "data-defined hole produces an autonomous course-management choice")
	_assert_true(evaluated.size() >= 18, "strategy considers a real menu of club-target combinations")
	_assert_true(not str(chosen.get("club_id", "")).is_empty(), "chosen strategy names a real club")
	_assert_true(not str(chosen.get("target_variant", "")).is_empty(), "chosen strategy names a spatial target variant")
	_assert_true(str(chosen.get("name", "")).begins_with("EMERGENT_"), "choice no longer depends on LAYUP/BAILOUT/ATTACK labels")
	_assert_true(chosen.has("target_position"), "chosen strategy is directly executable")
	_assert_true(chosen.has("expected_strokes_to_hole"), "choice retains objective scoring expectation")
	_assert_true(chosen.has("perceived_expected_strokes_to_hole"), "choice retains golfer perception")
	_assert_near(float(chosen.get("course_management", 0.0)), 88.0, 0.001, "explicit Course Management reaches autonomous selection")

	var best_perceived: float = INF
	var variants_seen: Dictionary = {}
	for option in evaluated:
		best_perceived = min(best_perceived, float(option.get("perceived_expected_strokes_to_hole", INF)))
		variants_seen[str(option.get("target_variant", ""))] = true
		_assert_true(option.has("expected_strokes_to_hole"), "every considered target has objective expected strokes")
		_assert_true(option.has("perceived_expected_strokes_to_hole"), "every considered target has perceived expected strokes")
	_assert_true(variants_seen.has("LEFT") and variants_seen.has("CENTER") and variants_seen.has("RIGHT"), "selector sees left, center, and right targets")
	_assert_near(float(chosen.get("perceived_expected_strokes_to_hole", INF)), best_perceived, 0.0001, "golfer chooses the club-target option believed to minimize strokes")

	# Course Management changes perception, not objective reality. Compare every
	# exact club-target combination rather than collapsing three targets into one club.
	var high_management_decision: Dictionary = decision
	golfer.set_meta("course_management", 25.0)
	var low_management_decision: Dictionary = playable.choose_course_strategy(golfer, state)
	var high_options: Array = high_management_decision.get("evaluated", [])
	var low_options: Array = low_management_decision.get("evaluated", [])
	var comparable_count: int = 0
	for high_option in high_options:
		var low_option: Dictionary = _find_option(low_options, str(high_option.get("club_id", "")), str(high_option.get("target_variant", "")))
		if low_option.is_empty():
			continue
		comparable_count += 1
		var label := "%s/%s" % [str(high_option.get("club_id", "")), str(high_option.get("target_variant", ""))]
		_assert_near(float(high_option.get("expected_strokes_to_hole", 0.0)), float(low_option.get("expected_strokes_to_hole", 0.0)), 0.0001, "%s objective scoring stays golfer-independent" % label)
		if float(high_option.get("expected_penalty_strokes", 0.0)) + float(high_option.get("expected_recovery_strokes", 0.0)) > 0.001:
			_assert_true(float(low_option.get("perceived_expected_strokes_to_hole", INF)) <= float(high_option.get("perceived_expected_strokes_to_hole", INF)), "lower Course Management is at least as optimistic about risky %s" % label)
	_assert_true(comparable_count == high_options.size(), "Course Management comparison preserves the same feasible club-target menu")

	golfer.free()
	if failures == 0:
		print("POC-13D/F COURSE STRATEGY SELECTOR TESTS PASSED")
		quit(0)
	else:
		push_error("POC-13D/F COURSE STRATEGY SELECTOR TESTS FAILED: %d" % failures)
		quit(1)


func _find_option(options: Array, club_id: String, target_variant: String) -> Dictionary:
	for option in options:
		if str(option.get("club_id", "")) == club_id and str(option.get("target_variant", "")) == target_variant:
			return option
	return {}


func _assert_true(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error("FAIL: " + label)
	else:
		print("PASS: ", label)


func _assert_near(value: float, expected: float, tolerance: float, label: String) -> void:
	_assert_true(abs(value - expected) <= tolerance, label)
