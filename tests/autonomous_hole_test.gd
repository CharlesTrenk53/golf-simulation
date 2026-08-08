extends SceneTree

const GolferScript = preload("res://scenes/golfer.gd")
const CourseState = preload("res://simulation/course_state.gd")
const ShotOptionGenerator = preload("res://simulation/shot_option_generator.gd")
const AutonomousHole = preload("res://simulation/autonomous_hole.gd")

var failures: int = 0


func _init() -> void:
	_test_course_state()
	_test_dynamic_options()
	_test_autonomous_hole()

	if failures == 0:
		print("POC-05 TESTS PASSED")
		quit(0)
	else:
		push_error("POC-05 TESTS FAILED: %d" % failures)
		quit(1)


func _test_course_state() -> void:
	var state = CourseState.new(Vector3(0, 0, 100), Vector3.ZERO, 4)
	_assert_near(state.remaining_distance(), 100.0, 0.01, "initial distance")
	state.advance_to(Vector3(0, 0, 40))
	_assert_true(state.strokes == 1, "state counts strokes")
	_assert_near(state.remaining_distance(), 40.0, 0.01, "state updates position")


func _test_dynamic_options() -> void:
	var golfer = GolferScript.new()
	golfer.profile = golfer.GolferProfile.CAREFUL_CARL
	golfer.apply_profile()
	var state = CourseState.new(Vector3(0, 0, 100), Vector3.ZERO, 4)
	var generator = ShotOptionGenerator.new()
	var options = generator.generate_options(golfer, state, [
		{"position": Vector3(0, 0, 55), "radius": 8.0, "risk": 90.0}
	])
	_assert_true(options.size() == 3, "long situation creates three choices")
	_assert_true(options[2]["risk"] >= 90.0, "hazard affects attack risk")

	state.ball_position = Vector3(0, 0, 6)
	options = generator.generate_options(golfer, state)
	_assert_true(options.size() == 1, "green situation collapses to putt")
	_assert_true(options[0]["name"] == "PUTT", "green situation generates putt")
	golfer.free()


func _test_autonomous_hole() -> void:
	var golfer = GolferScript.new()
	golfer.profile = golfer.GolferProfile.WILD_BILL
	golfer.apply_profile()
	golfer.decision_variability = 0.0

	var simulation = AutonomousHole.new()
	var result = simulation.play_hole(
		golfer,
		Vector3(0, 0, 120),
		Vector3.ZERO,
		[],
		4,
		42
	)

	_assert_true(result["history"].size() > 1, "hole requires repeated decisions")
	_assert_true(result["strokes"] <= 12, "hole respects stroke limit")
	_assert_true(result["remaining_distance"] < 120.0, "golfer advances toward hole")
	golfer.free()


func _assert_true(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error("FAIL: " + label)
	else:
		print("PASS: ", label)


func _assert_near(value: float, expected: float, tolerance: float, label: String) -> void:
	_assert_true(abs(value - expected) <= tolerance, label)
