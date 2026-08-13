extends SceneTree

const StrategicCourseFixture = preload("res://tests/fixtures/poc19_strategic_course_fixture.gd")
const QuietGolfer = preload("res://tests/fixtures/poc19_quiet_golfer.gd")
const AutonomousRound = preload("res://simulation/autonomous_round.gd")
const DataDefinedAutonomousHole = preload("res://simulation/data_defined_autonomous_hole.gd")

var failures: int = 0


func _init() -> void:
	print("POC-20C: round context propagation")
	var course = StrategicCourseFixture.new().build_course()
	_assert_true(course != null, "strategic proving course builds")
	if course == null:
		_finish()
		return

	var golfer = _build_golfer()
	var round = AutonomousRound.new(course, "back")
	var first: Dictionary = round.play_current_hole(golfer, 200301)
	var second: Dictionary = round.play_current_hole(golfer, 200302)
	var third: Dictionary = round.play_current_hole(golfer, 200303)

	_assert_true(bool(first.get("recorded", false)), "first hole records")
	_assert_true(bool(second.get("recorded", false)), "second hole records")
	_assert_true(bool(third.get("recorded", false)), "third hole records")

	var first_context: Dictionary = first.get("pre_hole_round_context", {})
	var second_context: Dictionary = second.get("pre_hole_round_context", {})
	var third_context: Dictionary = third.get("pre_hole_round_context", {})
	var first_adaptation: Dictionary = first.get("pre_hole_adaptation", {})
	var third_adaptation: Dictionary = third.get("pre_hole_adaptation", {})

	_assert_equal(int(first_context.get("holes_completed", -1)), 0, "hole 1 receives opening context")
	_assert_equal(int(second_context.get("holes_completed", -1)), 1, "hole 2 receives context after hole 1")
	_assert_equal(int(third_context.get("holes_completed", -1)), 2, "hole 3 receives context after two holes")
	_assert_equal(int(second_context.get("current_hole_number", -1)), 2, "hole 2 context identifies current hole")
	_assert_equal(int(third_context.get("current_hole_number", -1)), 3, "hole 3 context identifies current hole")
	_assert_true(float(third_context.get("round_progress", 0.0)) > float(first_context.get("round_progress", 0.0)), "round progress grows between holes")
	_assert_float_close(float(first_adaptation.get("physical_load_exposure", -1.0)), 0.0, 0.000001, "opening hole adaptation has zero physical load")
	_assert_true(float(third_adaptation.get("physical_load_exposure", 0.0)) > 0.0, "later hole receives accumulated physical load signal")
	_assert_true(first.has("round_context") and first.has("round_adaptation"), "authored hole result carries context diagnostics")

	# Context is diagnostic-only in 20C. Supplying arbitrary context directly to
	# an otherwise identical hole must not alter deterministic play at the same seed.
	var control_golfer = _build_golfer()
	var context_golfer = _build_golfer()
	var control_hole = DataDefinedAutonomousHole.new(course.hole_at(0), "back")
	var context_hole = DataDefinedAutonomousHole.new(course.hole_at(0), "back")
	context_hole.set_round_context({"round_progress": 0.95, "score_to_par": 12}, {"physical_load_exposure": 0.9, "confidence_momentum_signal": -1.0})
	var control_result: Dictionary = control_hole.play_hole(control_golfer, 200399)
	var contextual_result: Dictionary = context_hole.play_hole(context_golfer, 200399)
	_assert_equal(int(contextual_result.get("strokes", -1)), int(control_result.get("strokes", -2)), "diagnostic context does not change hole score")
	_assert_equal(_history_signature(contextual_result.get("history", [])), _history_signature(control_result.get("history", [])), "diagnostic context does not change deterministic shot sequence")

	print("POC20_CONTEXT_PROPAGATION_SUMMARY first_progress=%.3f third_progress=%.3f third_load=%.3f third_score_to_par=%+d" % [
		float(first_context.get("round_progress", 0.0)),
		float(third_context.get("round_progress", 0.0)),
		float(third_adaptation.get("physical_load_exposure", 0.0)),
		int(third_context.get("score_to_par", 0))
	])

	golfer.free()
	control_golfer.free()
	context_golfer.free()
	_finish()


func _build_golfer() -> Node:
	var golfer = QuietGolfer.new()
	golfer.profile = golfer.GolferProfile.CAREFUL_CARL
	golfer.apply_profile()
	golfer.decision_variability = 0.0
	return golfer


func _history_signature(history: Array) -> String:
	var parts: Array[String] = []
	for shot in history:
		parts.append("%s|%s|%s|%s" % [
			str(shot.get("club_id", "")),
			str(shot.get("intent_signature", "")),
			str(shot.get("outcome", "")),
			str(shot.get("landing_position", Vector3.ZERO))
		])
	return ";".join(parts)


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


func _assert_float_close(actual: float, expected: float, tolerance: float, label: String) -> void:
	if absf(actual - expected) <= tolerance:
		print("PASS: %s (actual=%.6f expected=%.6f)" % [label, actual, expected])
	else:
		failures += 1
		push_error("FAIL: %s (actual=%.6f expected=%.6f)" % [label, actual, expected])


func _finish() -> void:
	if failures == 0:
		print("POC-20C ROUND CONTEXT PROPAGATION PASSED")
		quit(0)
	else:
		push_error("POC-20C ROUND CONTEXT PROPAGATION FAILED: %d" % failures)
		quit(1)
