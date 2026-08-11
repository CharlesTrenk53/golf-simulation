extends SceneTree

const GolferScript = preload("res://scenes/golfer.gd")
const HoleDefinition = preload("res://simulation/hole_definition.gd")
const DataDefinedAutonomousHole = preload("res://simulation/data_defined_autonomous_hole.gd")

var failures: int = 0


func _init() -> void:
	print("POC-11C: load data-defined hole")
	var hole = HoleDefinition.load_json("res://data/courses/poc11_test_hole.json")
	_assert_true(hole != null, "test hole loads")
	if hole == null:
		quit(1)
		return

	var playable = DataDefinedAutonomousHole.new(hole)
	var state = playable.create_state(11)
	_assert_true(state != null, "autonomous state builds from HoleDefinition")
	if state == null:
		quit(1)
		return

	_assert_true(playable.autonomous.option_generator.bag.is_using_literal_yardages(), "data-defined option generation uses literal yards")
	_assert_true(playable.autonomous.bag.is_using_literal_yardages(), "data-defined shot execution uses literal yards")
	_assert_true(state.ball_position == hole.tee_position("default"), "state starts at data-defined tee")
	_assert_true(state.hole_position == hole.pin_position, "state targets data-defined pin")
	_assert_true(state.par == hole.par, "state inherits data-defined par")
	_assert_true(state.surface_name() == "TEE", "legacy CourseState resolves tee through polygon adapter")
	_assert_near(state.current_lie_quality, 1.0, 0.001, "tee lie quality survives adapter")

	var tee_snapshot = playable.course_snapshot(state.ball_position)
	_assert_true(str(tee_snapshot.get("surface", "")) == "TEE", "autonomous wrapper exposes authoritative spatial snapshot")
	_assert_true(float(tee_snapshot.get("distance_to_pin", 0.0)) > 400.0, "tee snapshot derives full-hole distance")

	var golfer = GolferScript.new()
	golfer.profile = golfer.GolferProfile.CAREFUL_CARL
	golfer.apply_profile()

	print("POC-11C: autonomous golfer takes first data-defined shot")
	var result = playable.play_step(golfer, state)
	_assert_true(not result.is_empty(), "autonomous golfer generates and executes a shot")
	if not result.is_empty():
		_assert_true(str(result.get("surface_before", "")) == "TEE", "first shot context comes from data-defined tee")
		_assert_true(not str(result.get("option", "")).is_empty(), "autonomous golfer selects an option")
		_assert_true(not str(result.get("club_id", "")).is_empty(), "opening shot selects a real club")
		_assert_true(float(result.get("intended_distance", 0.0)) > 100.0, "full-length opening strategy advances a realistic distance")
		_assert_true(float(result.get("club_effective_carry", 0.0)) > 100.0, "selected club executes on literal-yard scale")
		_assert_true(state.strokes >= 1, "executed shot advances course state")
		_assert_true(str(result.get("surface_after", "")).length() > 0, "landing lie is resolved from hole geometry")

	golfer.free()

	if failures == 0:
		print("POC-11C DATA-DEFINED AUTONOMOUS INTEGRATION TESTS PASSED")
		quit(0)
	else:
		push_error("POC-11C DATA-DEFINED AUTONOMOUS INTEGRATION TESTS FAILED: %d" % failures)
		quit(1)


func _assert_true(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error("FAIL: " + label)
	else:
		print("PASS: ", label)


func _assert_near(value: float, expected: float, tolerance: float, label: String) -> void:
	_assert_true(abs(value - expected) <= tolerance, label)
