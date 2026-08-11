extends SceneTree

const GolferScript = preload("res://scenes/golfer.gd")
const HoleDefinition = preload("res://simulation/hole_definition.gd")
const DataDefinedAutonomousHole = preload("res://simulation/data_defined_autonomous_hole.gd")

var failures: int = 0


func _init() -> void:
	print("POC-13E: emergent course strategy drives live execution")
	var hole = HoleDefinition.load_json("res://data/courses/poc11_test_hole.json")
	_assert_true(hole != null, "Decision Point loads")
	if hole == null:
		quit(1)
		return

	var playable = DataDefinedAutonomousHole.new(hole)
	var state = playable.create_state(13131)
	var golfer = GolferScript.new()
	golfer.profile = golfer.GolferProfile.CAREFUL_CARL
	golfer.apply_profile()
	golfer.set_meta("course_management", 90.0)

	var preview: Dictionary = playable.choose_course_strategy(golfer, state)
	var preview_choice: Dictionary = preview.get("chosen", {})
	_assert_true(not preview_choice.is_empty(), "course management produces a pre-shot club choice")
	_assert_true(not str(preview_choice.get("club_id", "")).is_empty(), "pre-shot choice identifies a real club")
	_assert_true(preview_choice.has("expected_strokes_to_hole"), "pre-shot choice carries objective expected strokes")
	_assert_true(preview_choice.has("perceived_expected_strokes_to_hole"), "pre-shot choice carries perceived expected strokes")

	var starting_position: Vector3 = state.ball_position
	var result: Dictionary = playable.play_step(golfer, state)
	_assert_true(not result.is_empty(), "live data-defined play executes the selected strategy")
	if not result.is_empty():
		_assert_true(str(result.get("decision_system", "")) == "EXPECTED_STROKES_COURSE_MANAGEMENT", "live shot reports the new decision system")
		_assert_true(str(result.get("club_id", "")) == str(preview_choice.get("club_id", "")), "executed club matches the course-management selection")
		_assert_true(str(result.get("option", "")).begins_with("EMERGENT_"), "live shot no longer depends on layup/bailout/attack vocabulary")
		_assert_true(result.has("objective_expected_strokes"), "execution preserves objective scoring estimate")
		_assert_true(result.has("perceived_expected_strokes"), "execution preserves golfer perception")
		_assert_true(result.has("course_management"), "execution records course-management rating")
		_assert_true(Array(result.get("strategy_candidates", [])).size() >= 5, "execution retains the evaluated bag menu for diagnostics")
		_assert_true(Vector3(result.get("target_position", starting_position)).distance_to(starting_position) > 50.0, "selected shot has a meaningful club-specific target")
		_assert_true(state.strokes >= 1, "selected shot advances scoring state")
		_assert_true(state.ball_position != starting_position, "selected shot advances the ball")

	golfer.free()
	if failures == 0:
		print("POC-13E COURSE STRATEGY EXECUTION TESTS PASSED")
		quit(0)
	else:
		push_error("POC-13E COURSE STRATEGY EXECUTION TESTS FAILED: %d" % failures)
		quit(1)


func _assert_true(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error("FAIL: " + label)
	else:
		print("PASS: ", label)
