extends SceneTree

const GolferScript = preload("res://scenes/golfer.gd")
const CourseState = preload("res://simulation/course_state.gd")
const CourseContext = preload("res://simulation/course_context.gd")
const ShotOptionGenerator = preload("res://simulation/shot_option_generator.gd")
const AutonomousHole = preload("res://simulation/autonomous_hole.gd")
const AutonomousDemoScene = preload("res://scenes/autonomous_demo.tscn")

var failures: int = 0


func _init() -> void:
	_test_course_state()
	_test_dynamic_options()
	_test_course_context()
	_test_lie_aware_options()
	_test_autonomous_hole()
	_test_autonomous_demo_scene()

	if failures == 0:
		print("POC-06A TESTS PASSED")
		quit(0)
	else:
		push_error("POC-06A TESTS FAILED: %d" % failures)
		quit(1)


func _test_course_state() -> void:
	var state = CourseState.new(Vector3(0, 0, 100), Vector3.ZERO, 4)
	_assert_near(state.remaining_distance(), 100.0, 0.01, "initial distance")
	state.advance_to(Vector3(0, 0, 40))
	_assert_true(state.strokes == 1, "state counts strokes")
	_assert_near(state.remaining_distance(), 40.0, 0.01, "state updates position")
	_assert_true(state.surface_name() == "FAIRWAY", "legacy state defaults to fairway")
	_assert_near(state.current_lie_quality, 1.0, 0.001, "legacy state preserves baseline lie")


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
	_assert_true(options.size() == 1, "near-hole situation collapses to putt")
	_assert_true(options[0]["name"] == "PUTT", "near-hole situation generates putt")
	golfer.free()


func _build_context() -> RefCounted:
	var context = CourseContext.new()
	context.add_zone("Fairway", CourseContext.Surface.FAIRWAY, Vector3(0, 0, 50), Vector2(12, 50))
	context.add_zone("Tee", CourseContext.Surface.TEE, Vector3(0, 0, 100), Vector2(8, 5))
	context.add_zone("Green", CourseContext.Surface.GREEN, Vector3(0, 0, 0), Vector2(14, 10))
	context.add_zone("Water", CourseContext.Surface.WATER, Vector3(0, 0, 45), Vector2(16, 6))
	return context


func _test_course_context() -> void:
	var context = _build_context()
	_assert_true(context.surface_name(context.surface_at(Vector3(0, 0, 100))) == "TEE", "tee surface resolves")
	_assert_true(context.surface_name(context.surface_at(Vector3(0, 0, 70))) == "FAIRWAY", "fairway surface resolves")
	_assert_true(context.surface_name(context.surface_at(Vector3(20, 0, 70))) == "ROUGH", "outside fairway resolves to rough")
	_assert_true(context.surface_name(context.surface_at(Vector3(0, 0, 3))) == "GREEN", "green surface resolves")
	_assert_true(context.surface_name(context.surface_at(Vector3(0, 0, 45))) == "WATER", "water surface resolves")

	var rough_state = CourseState.new(Vector3(20, 0, 70), Vector3.ZERO, 4, context)
	_assert_true(rough_state.surface_name() == "ROUGH", "state tracks rough lie")
	_assert_near(rough_state.current_lie_quality, 0.72, 0.001, "rough reduces lie quality")
	rough_state.advance_to(Vector3(0, 0, 3))
	_assert_true(rough_state.surface_name() == "GREEN", "landing updates surface")


func _test_lie_aware_options() -> void:
	var context = _build_context()
	var golfer = GolferScript.new()
	golfer.profile = golfer.GolferProfile.WILD_BILL
	golfer.apply_profile()
	var generator = ShotOptionGenerator.new()

	var fairway_state = CourseState.new(Vector3(0, 0, 70), Vector3.ZERO, 4, context)
	var rough_state = CourseState.new(Vector3(20, 0, 70), Vector3.ZERO, 4, context)
	var fairway_options = generator.generate_options(golfer, fairway_state)
	var rough_options = generator.generate_options(golfer, rough_state)

	_assert_true(rough_options[0]["reward"] < fairway_options[0]["reward"], "rough lowers option reward")
	_assert_true(rough_options[0]["risk"] > fairway_options[0]["risk"], "rough raises option risk")
	_assert_true(rough_options[2]["model_success_chance"] < fairway_options[2]["model_success_chance"], "rough lowers attack success")

	var green_state = CourseState.new(Vector3(0, 0, 7), Vector3.ZERO, 4, context)
	var green_options = generator.generate_options(golfer, green_state)
	_assert_true(green_options.size() == 1 and green_options[0]["name"] == "PUTT", "green lie forces putting context")
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


func _test_autonomous_demo_scene() -> void:
	var demo = AutonomousDemoScene.instantiate()
	_assert_true(demo != null, "autonomous visual demo scene loads")
	demo.free()


func _assert_true(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error("FAIL: " + label)
	else:
		print("PASS: ", label)


func _assert_near(value: float, expected: float, tolerance: float, label: String) -> void:
	_assert_true(abs(value - expected) <= tolerance, label)
