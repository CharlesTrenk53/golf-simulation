extends SceneTree

const GolferScript = preload("res://scenes/golfer.gd")
const HoleDefinition = preload("res://simulation/hole_definition.gd")
const DataDefinedAutonomousHole = preload("res://simulation/data_defined_autonomous_hole.gd")
const ClubCandidateGenerator = preload("res://simulation/club_candidate_generator.gd")
const ClubCandidateEvaluator = preload("res://simulation/club_candidate_evaluator.gd")

var failures: int = 0


func _init() -> void:
	print("POC-13B/C: expected-strokes candidate evaluation")
	var hole = HoleDefinition.load_json("res://data/courses/poc11_test_hole.json")
	_assert_true(hole != null, "Decision Point loads")
	if hole == null:
		quit(1)
		return

	var playable = DataDefinedAutonomousHole.new(hole)
	var state = playable.create_state(1313)
	var golfer = GolferScript.new()
	golfer.profile = golfer.GolferProfile.CAREFUL_CARL
	golfer.apply_profile()

	var generator = ClubCandidateGenerator.new()
	generator.bag.use_literal_yardages(true)
	var evaluator = ClubCandidateEvaluator.new()
	evaluator.bag.use_literal_yardages(true)
	var candidates: Array = generator.generate(golfer, state)

	golfer.set_meta("course_management", 90.0)
	var seasoned: Array = evaluator.evaluate_all(golfer, state, candidates)
	_assert_true(not seasoned.is_empty(), "real bag candidates receive expected-strokes evaluations")
	var last_perceived: float = -INF
	for entry in seasoned:
		_assert_true(entry.has("true_expected_strokes_to_hole"), "objective expected strokes are retained")
		_assert_true(entry.has("perceived_expected_strokes_to_hole"), "golfer perceived expected strokes are retained")
		_assert_true(entry.has("course_management"), "course management is visible in diagnostics")
		_assert_true(float(entry["true_expected_strokes_to_hole"]) >= 1.0, "objective scoring estimate is expressed in strokes")
		var perceived: float = float(entry["perceived_expected_strokes_to_hole"])
		_assert_true(perceived + 0.0001 >= last_perceived, "candidates rank lowest perceived expected strokes first")
		last_perceived = perceived

	# The visible POC-13 demo exposed an important calibration flaw: several clubs
	# with materially different leaves could tie because the old continuation model
	# used coarse distance buckets. Exact leave distance must now matter continuously.
	_assert_true(evaluator._distance_baseline(205.0) < evaluator._distance_baseline(225.0), "20-yard improvement inside former 175-225 bucket saves expected strokes")
	_assert_true(evaluator._distance_baseline(225.0) < evaluator._distance_baseline(245.0), "distance curve remains monotonic across former bucket boundary")
	_assert_true(evaluator._distance_baseline(245.0) < evaluator._distance_baseline(285.0), "different long-approach leaves remain distinguishable")

	var driver_candidate: Dictionary = _candidate(candidates, "DRIVER")
	_assert_true(not driver_candidate.is_empty(), "driver candidate available for calibration comparison")
	if not driver_candidate.is_empty():
		golfer.set_meta("course_management", 90.0)
		var high_management: Dictionary = evaluator.evaluate(golfer, state, driver_candidate)
		golfer.set_meta("course_management", 30.0)
		var low_management: Dictionary = evaluator.evaluate(golfer, state, driver_candidate)
		_assert_near(float(high_management["true_expected_strokes_to_hole"]), float(low_management["true_expected_strokes_to_hole"]), 0.0001, "course management does not change objective shot consequence")
		_assert_true(float(low_management["perceived_expected_strokes_to_hole"]) <= float(high_management["perceived_expected_strokes_to_hole"]), "lower management is at least as optimistic about the same long shot")

	var three_wood_candidate: Dictionary = _candidate(candidates, "3_WOOD")
	if not driver_candidate.is_empty() and not three_wood_candidate.is_empty():
		golfer.set_meta("course_management", 90.0)
		var driver_eval: Dictionary = evaluator.evaluate(golfer, state, driver_candidate)
		var three_wood_eval: Dictionary = evaluator.evaluate(golfer, state, three_wood_candidate)
		if str(driver_candidate.get("expected_surface", "")) == str(three_wood_candidate.get("expected_surface", "")) and int(driver_candidate.get("corridor_hazard_count", 0)) == 0 and int(three_wood_candidate.get("corridor_hazard_count", 0)) == 0:
			_assert_true(abs(float(driver_eval["true_expected_strokes_to_hole"]) - float(three_wood_eval["true_expected_strokes_to_hole"])) > 0.001, "distinct same-surface club leaves no longer collapse to an exact expected-strokes tie")

	golfer.free()
	if failures == 0:
		print("POC-13B/C CLUB CANDIDATE EVALUATOR TESTS PASSED")
		quit(0)
	else:
		push_error("POC-13B/C CLUB CANDIDATE EVALUATOR TESTS FAILED: %d" % failures)
		quit(1)


func _candidate(candidates: Array, club_id: String) -> Dictionary:
	for candidate in candidates:
		if str(candidate.get("club_id", "")) == club_id:
			return candidate
	return {}


func _assert_true(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error("FAIL: " + label)
	else:
		print("PASS: ", label)


func _assert_near(value: float, expected: float, tolerance: float, label: String) -> void:
	_assert_true(abs(value - expected) <= tolerance, label)
