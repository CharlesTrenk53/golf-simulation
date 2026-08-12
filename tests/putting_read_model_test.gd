extends SceneTree

const PuttingReadModel = preload("res://simulation/putting_read_model.gd")

var failures: int = 0


func _init() -> void:
	print("POC-15A: deterministic putting read")
	var model = PuttingReadModel.new()

	var level := model.plan_putt(12.0, 0.0, 0.0, 10.0)
	_assert_near(float(level["aim_offset_feet"]), 0.0, 0.001, "level putt aims straight")
	_assert_true(float(level["intended_distance_feet"]) > 12.0, "level putt carries modest pace past the cup")

	var right_break := model.plan_putt(20.0, 2.0, 0.0, 10.0)
	var left_break := model.plan_putt(20.0, -2.0, 0.0, 10.0)
	_assert_true(float(right_break["aim_offset_feet"]) > 0.0, "positive cross slope produces right-break compensation")
	_assert_true(float(left_break["aim_offset_feet"]) < 0.0, "negative cross slope produces left-break compensation")
	_assert_near(absf(float(right_break["aim_offset_feet"])), absf(float(left_break["aim_offset_feet"])), 0.001, "equal opposite slopes produce symmetric reads")

	var short_break := model.plan_putt(8.0, 2.0, 0.0, 10.0)
	var long_break := model.plan_putt(30.0, 2.0, 0.0, 10.0)
	_assert_true(absf(float(long_break["aim_offset_feet"])) > absf(float(short_break["aim_offset_feet"])), "longer putt requires more break allowance")

	var uphill := model.plan_putt(20.0, 0.0, 2.0, 10.0)
	var downhill := model.plan_putt(20.0, 0.0, -2.0, 10.0)
	_assert_true(float(uphill["intended_distance_feet"]) > float(level_for_distance(model, 20.0)["intended_distance_feet"]), "uphill putt needs more pace")
	_assert_true(float(downhill["intended_distance_feet"]) < float(level_for_distance(model, 20.0)["intended_distance_feet"]), "downhill putt needs less pace")

	var fast := model.plan_putt(20.0, 2.0, 0.0, 13.0)
	var slow := model.plan_putt(20.0, 2.0, 0.0, 8.0)
	_assert_true(absf(float(fast["aim_offset_feet"])) > absf(float(slow["aim_offset_feet"])), "faster green requires more break allowance")

	if failures == 0:
		print("POC-15A PUTTING READ TESTS PASSED")
		quit(0)
	else:
		push_error("POC-15A PUTTING READ TESTS FAILED: %d" % failures)
		quit(1)


func level_for_distance(model, distance: float) -> Dictionary:
	return model.plan_putt(distance, 0.0, 0.0, 10.0)


func _assert_true(value: bool, label: String) -> void:
	if value:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)


func _assert_near(actual: float, expected: float, tolerance: float, label: String) -> void:
	_assert_true(absf(actual - expected) <= tolerance, label)
