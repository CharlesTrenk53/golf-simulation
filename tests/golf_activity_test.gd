extends SceneTree

const GolfActivity = preload("res://simulation/golf_activity.gd")

var failures := 0

func _init() -> void:
	_test_round_accounting()
	_test_practice_focus_allocation()
	_test_quality_bookkeeping()
	_test_zero_and_invalid_inputs()

	if failures == 0:
		print("POC-10 GOLF ACTIVITY TESTS PASSED")
		quit(0)
	else:
		push_error("POC-10 GOLF ACTIVITY TESTS FAILED: %d" % failures)
		quit(1)

func _test_round_accounting() -> void:
	var activity := GolfActivity.new()
	var result := activity.record_rounds(10)
	_expect(int(result["rounds"]) == 10, "round accounting preserves requested round count")
	_expect(int(result["on_course_exposure"][0]) == 140, "ten rounds create expected Driver exposure")
	_expect(int(result["on_course_exposure"][1]) == 220, "ten rounds create expected Approach exposure")
	_expect(int(result["on_course_exposure"][2]) == 120, "ten rounds create expected Short Game exposure")
	_expect(int(result["on_course_exposure"][3]) == 300, "ten rounds create expected Putt exposure")
	_expect(activity.total_on_course_exposure() == 780, "round exposure totals across shot families")
	_expect(activity.total_practice_repetitions() == 0, "playing does not masquerade as practice")

func _test_practice_focus_allocation() -> void:
	var activity := GolfActivity.new()
	var focus := {0: 0.50, 1: 0.30, 2: 0.15, 3: 0.05}
	var result := activity.record_practice(1000, focus, 0.80)
	_expect(int(result["practice_repetitions"][0]) == 500, "practice focus routes Driver repetitions")
	_expect(int(result["practice_repetitions"][1]) == 300, "practice focus routes Approach repetitions")
	_expect(int(result["practice_repetitions"][2]) == 150, "practice focus routes Short Game repetitions")
	_expect(int(result["practice_repetitions"][3]) == 50, "practice focus routes Putt repetitions")
	_expect(activity.total_practice_repetitions() == 1000, "practice allocation preserves total repetitions")
	_expect(activity.total_on_course_exposure() == 0, "practice does not masquerade as on-course play")

func _test_quality_bookkeeping() -> void:
	var activity := GolfActivity.new()
	activity.record_practice(100, {0: 1.0}, 0.25)
	activity.record_practice(300, {0: 1.0}, 0.75)
	_expect(activity.total_practice_repetitions() == 400, "multiple practice sessions accumulate repetitions")
	_expect(abs(activity.average_practice_quality(0) - 0.625) < 0.0001, "practice quality is repetition-weighted")
	_expect(activity.average_practice_quality(1) == 0.0, "unpracticed skill has zero recorded practice quality")
	var before_state := activity.state()
	_expect(not before_state.has("skill_delta"), "Golf Activity state contains no direct skill award")

func _test_zero_and_invalid_inputs() -> void:
	var activity := GolfActivity.new()
	activity.record_rounds(-5)
	_expect(activity.career_rounds_played == 0, "negative rounds cannot create activity")
	activity.record_practice(-100, {0: 1.0}, 2.0)
	_expect(activity.total_practice_repetitions() == 0, "negative practice repetitions cannot create activity")
	var empty_focus_result := activity.record_practice(8, {}, 1.0)
	_expect(activity.total_practice_repetitions() == 8, "empty focus still preserves total repetitions")
	_expect(int(empty_focus_result["practice_repetitions"][0]) == 2, "empty focus defaults to equal Driver allocation")
	_expect(int(empty_focus_result["practice_repetitions"][1]) == 2, "empty focus defaults to equal Approach allocation")
	_expect(int(empty_focus_result["practice_repetitions"][2]) == 2, "empty focus defaults to equal Short Game allocation")
	_expect(int(empty_focus_result["practice_repetitions"][3]) == 2, "empty focus defaults to equal Putt allocation")
	var clipped_quality := activity.record_practice(4, {3: 1.0}, 1.5)
	_expect(abs(float(clipped_quality["quality"]) - 1.0) < 0.0001, "practice quality is clipped to valid range")

func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)
