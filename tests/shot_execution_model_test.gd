extends SceneTree

const ShotExecutionModel = preload("res://simulation/shot_execution_model.gd")

var failures: int = 0


func _init() -> void:
	print("POC-14D: stochastic execution realization")
	var model = ShotExecutionModel.new()

	var predicted := {
		"intent_signature": "NORMAL|DRAW|FULL|STOCK",
		"carry_yards": 220.0,
		"rollout_yards": 24.0,
		"curve_yards": -18.0,
		"apex_factor": 1.0,
		"dispersion_yards": 10.0
	}
	var high_skill := {
		"execution_reliability": 0.90,
		"expected_dispersion_multiplier": 0.80
	}
	var low_skill := {
		"execution_reliability": 0.38,
		"expected_dispersion_multiplier": 1.35
	}

	var a: Dictionary = model.realize(predicted, high_skill, 42)
	var b: Dictionary = model.realize(predicted, high_skill, 42)
	var c: Dictionary = model.realize(predicted, high_skill, 43)
	_assert_true(a == b, "same seed produces identical actual shot")
	_assert_true(a != c, "different seed produces a different actual shot")
	_assert_true(a["intent_signature"] == predicted["intent_signature"], "execution preserves requested intent identity")
	_assert_true(a["actual_carry_yards"] > 0.0, "actual carry remains physical")
	_assert_true(a["actual_total_yards"] >= a["actual_carry_yards"], "total distance includes nonnegative rollout")

	var high_abs_lateral := 0.0
	var low_abs_lateral := 0.0
	var high_abs_carry_error := 0.0
	var low_abs_carry_error := 0.0
	var trials := 250
	for i in range(trials):
		var seed := 1000 + i
		var high: Dictionary = model.realize(predicted, high_skill, seed)
		var low: Dictionary = model.realize(predicted, low_skill, seed)
		high_abs_lateral += abs(float(high["lateral_error_yards"]))
		low_abs_lateral += abs(float(low["lateral_error_yards"]))
		high_abs_carry_error += abs(float(high["carry_error_yards"]))
		low_abs_carry_error += abs(float(low["carry_error_yards"]))

	_assert_true(low_abs_lateral > high_abs_lateral * 1.45, "lower reliability creates materially wider lateral execution error")
	_assert_true(low_abs_carry_error > high_abs_carry_error * 1.45, "lower reliability creates materially wider distance execution error")

	var draw_sum := 0.0
	var fade_sum := 0.0
	var draw_predicted := predicted.duplicate(true)
	var fade_predicted := predicted.duplicate(true)
	fade_predicted["intent_signature"] = "NORMAL|FADE|FULL|STOCK"
	fade_predicted["curve_yards"] = 18.0
	for i in range(trials):
		var seed := 5000 + i
		draw_sum += float(model.realize(draw_predicted, high_skill, seed)["actual_curve_yards"])
		fade_sum += float(model.realize(fade_predicted, high_skill, seed)["actual_curve_yards"])
	_assert_true(draw_sum / trials < -12.0, "intended draw remains left-curving on average after execution noise")
	_assert_true(fade_sum / trials > 12.0, "intended fade remains right-curving on average after execution noise")

	if failures == 0:
		print("POC-14D SHOT EXECUTION TESTS PASSED")
		quit(0)
	else:
		push_error("POC-14D SHOT EXECUTION TESTS FAILED: %d" % failures)
		quit(1)


func _assert_true(value: bool, label: String) -> void:
	if value:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)
