extends SceneTree

const GolferScript = preload("res://scenes/golfer.gd")
const CourseManagementModel = preload("res://simulation/course_management_model.gd")

var failures: int = 0


func _init() -> void:
	print("POC-13C: course management calibration")
	var model = CourseManagementModel.new()
	var golfer = GolferScript.new()
	golfer.profile = golfer.GolferProfile.CAREFUL_CARL
	golfer.apply_profile()

	var objective := {
		"expected_strokes_to_hole": 4.20,
		"expected_penalty_strokes": 0.50,
		"expected_recovery_strokes": 0.35
	}
	var aggressive_candidate := {
		"intended_distance": 220.0
	}

	golfer.set_meta("course_management", 90.0)
	var seasoned: Dictionary = model.perception_for(golfer, objective, aggressive_candidate, 425.0)
	golfer.set_meta("course_management", 30.0)
	var inexperienced: Dictionary = model.perception_for(golfer, objective, aggressive_candidate, 425.0)

	_assert_near(float(seasoned["course_management"]), 90.0, 0.001, "explicit course management is honored")
	_assert_near(float(inexperienced["course_management"]), 30.0, 0.001, "low course management is independently configurable")
	_assert_true(abs(float(seasoned["calibration_gap"])) < abs(float(inexperienced["calibration_gap"])), "seasoned golfer perceives objective scoring consequence more accurately")
	_assert_true(float(inexperienced["perceived_expected_strokes_to_hole"]) < float(seasoned["perceived_expected_strokes_to_hole"]), "inexperienced golfer is more optimistic about risky long advance")
	_assert_true(float(inexperienced["underestimated_bad_outcomes"]) > float(seasoned["underestimated_bad_outcomes"]), "lower management underprices penalty and recovery cost")
	_assert_true(float(inexperienced["advancement_optimism"]) > float(seasoned["advancement_optimism"]), "lower management overvalues raw advancement")
	_assert_near(float(objective["expected_strokes_to_hole"]), 4.20, 0.001, "objective expected strokes remain unchanged by golfer perception")

	# Experience supplies a default when no explicit rating exists. This proves
	# course management can improve over a career without being identical to age,
	# risk tolerance, confidence, or shotmaking ability.
	golfer.remove_meta("course_management")
	golfer.profile = golfer.GolferProfile.RECKLESS_RICK
	golfer.apply_profile()
	var rick_management: float = model.rating_for(golfer)
	golfer.profile = golfer.GolferProfile.CAREFUL_CARL
	golfer.apply_profile()
	var carl_management: float = model.rating_for(golfer)
	_assert_true(carl_management > rick_management, "greater career shot exposure produces better default course management")

	golfer.free()
	if failures == 0:
		print("POC-13C COURSE MANAGEMENT TESTS PASSED")
		quit(0)
	else:
		push_error("POC-13C COURSE MANAGEMENT TESTS FAILED: %d" % failures)
		quit(1)


func _assert_true(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error("FAIL: " + label)
	else:
		print("PASS: ", label)


func _assert_near(value: float, expected: float, tolerance: float, label: String) -> void:
	_assert_true(abs(value - expected) <= tolerance, label)
