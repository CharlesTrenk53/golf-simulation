extends SceneTree

const RoundState = preload("res://simulation/round_state.gd")
const RoundContext = preload("res://simulation/round_context.gd")
const StrategicCourseFixture = preload("res://tests/fixtures/poc19_strategic_course_fixture.gd")

var failures := 0


func _init() -> void:
	print("POC-20A: round context model")
	var course = StrategicCourseFixture.new().build_course()
	_assert_true(course != null, "strategic proving course builds")
	if course == null:
		_finish()
		return

	var state = RoundState.new(course, "back")
	var model = RoundContext.new()

	var opening: Dictionary = model.build(state)
	_assert_equal(int(opening.get("holes_completed", -1)), 0, "opening context has no completed holes")
	_assert_equal(int(opening.get("holes_remaining", -1)), 18, "opening context sees all holes remaining")
	_assert_near(float(opening.get("round_progress", -1.0)), 0.0, 0.0001, "opening round progress is zero")
	_assert_equal(int(opening.get("score_to_par", 99)), 0, "opening score to par is even")
	_assert_equal(int(opening.get("recent_holes_count", -1)), 0, "opening recent window is empty")
	_assert_equal(int(opening.get("current_hole_number", -1)), 1, "opening context points to hole 1")

	# Hole pars are 4, 4, 3, 5. Record E, +1, -1, +2.
	_assert_true(state.record_current_hole(4), "records hole 1")
	_assert_true(state.record_current_hole(5), "records hole 2")
	_assert_true(state.record_current_hole(2), "records hole 3")
	_assert_true(state.record_current_hole(7), "records hole 4")

	var context: Dictionary = model.build(state)
	_assert_equal(int(context.get("holes_completed", -1)), 4, "context tracks completed holes")
	_assert_equal(int(context.get("holes_remaining", -1)), 14, "context tracks remaining holes")
	_assert_near(float(context.get("round_progress", -1.0)), 4.0 / 18.0, 0.0001, "round progress is derived from course progression")
	_assert_equal(int(context.get("strokes_played", -1)), 18, "context tracks objective stroke workload")
	_assert_equal(int(context.get("par_played", -1)), 16, "context tracks par played")
	_assert_equal(int(context.get("score_to_par", 99)), 2, "context tracks current score to par")
	_assert_equal(int(context.get("last_hole_to_par", 99)), 2, "context tracks last-hole result")
	_assert_equal(int(context.get("recent_holes_count", -1)), 3, "recent context uses three-hole window")
	_assert_equal(int(context.get("recent_total_to_par", 99)), 2, "recent context sums last three holes")
	_assert_near(float(context.get("recent_average_to_par", 99.0)), 2.0 / 3.0, 0.0001, "recent context averages last three holes")
	_assert_true(context.get("recent_scores_to_par", []) == [1, -1, 2], "recent context preserves hole order")
	_assert_equal(int(context.get("under_par_holes", -1)), 1, "context counts under-par holes")
	_assert_equal(int(context.get("par_holes", -1)), 1, "context counts pars")
	_assert_equal(int(context.get("over_par_holes", -1)), 2, "context counts over-par holes")
	_assert_equal(int(context.get("current_hole_number", -1)), 5, "context advances to next hole")
	_assert_true(not bool(context.get("round_complete", true)), "partial round remains incomplete")

	print("POC20_CONTEXT_SUMMARY holes=4 remaining=14 score_to_par=+2 recent=[1,-1,2] progress=%.3f strokes=18" % float(context.get("round_progress", 0.0)))
	_finish()


func _assert_true(value: bool, label: String) -> void:
	if value:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)


func _assert_equal(actual, expected, label: String) -> void:
	_assert_true(actual == expected, "%s (actual=%s expected=%s)" % [label, str(actual), str(expected)])


func _assert_near(actual: float, expected: float, tolerance: float, label: String) -> void:
	_assert_true(absf(actual - expected) <= tolerance, "%s (actual=%.6f expected=%.6f)" % [label, actual, expected])


func _finish() -> void:
	if failures == 0:
		print("POC-20A ROUND CONTEXT MODEL PASSED")
		quit(0)
	else:
		push_error("POC-20A ROUND CONTEXT MODEL FAILED: %d" % failures)
		quit(1)
