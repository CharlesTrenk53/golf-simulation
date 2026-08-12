extends SceneTree

const QuietGolfer = preload("res://tests/quiet_golfer.gd")
const PuttingReadModel = preload("res://simulation/putting_read_model.gd")
const PuttingStrategyModel = preload("res://simulation/putting_strategy_model.gd")

var failures: int = 0


func _init() -> void:
	print("POC-15D: putting decision strategy")
	var read_model = PuttingReadModel.new()
	var strategy_model = PuttingStrategyModel.new()

	var bold = _golfer(88.0, 90.0, 88.0)
	var cautious = _golfer(58.0, 10.0, 55.0)
	var strong_cautious = _golfer(88.0, 10.0, 70.0)

	var short_level: Dictionary = read_model.plan_putt(10.0, 0.0, 0.0, 10.0)
	var bold_short: Dictionary = strategy_model.choose_strategy(bold, short_level)
	var cautious_short: Dictionary = strategy_model.choose_strategy(cautious, short_level)
	_assert_true(str(bold_short["strategy"]) == "ATTACK", "skilled bold golfer attacks a makeable short putt")
	_assert_true(float(bold_short["intended_distance_feet"]) > float(short_level["intended_distance_feet"]), "attack strategy adds assertive pace")
	_assert_true(float(cautious_short["intended_distance_feet"]) <= float(bold_short["intended_distance_feet"]), "cautious golfer uses no more pace than bold golfer from same read")

	var long_level: Dictionary = read_model.plan_putt(50.0, 0.0, 0.0, 10.0)
	var bold_long: Dictionary = strategy_model.choose_strategy(bold, long_level)
	_assert_true(str(bold_long["strategy"]) == "LAG", "very long putt becomes a lag even for bold golfer")
	_assert_true(float(bold_long["intended_distance_feet"]) < float(long_level["intended_distance_feet"]), "lag strategy reduces pace beyond the cup")

	var downhill_fast: Dictionary = read_model.plan_putt(28.0, 0.0, -3.5, 13.0)
	var downhill_choice: Dictionary = strategy_model.choose_strategy(strong_cautious, downhill_fast)
	_assert_true(str(downhill_choice["strategy"]) != "ATTACK", "fast downhill putt suppresses attack strategy")

	var level_28: Dictionary = read_model.plan_putt(28.0, 0.0, 0.0, 10.0)
	var level_choice: Dictionary = strategy_model.choose_strategy(strong_cautious, level_28)
	_assert_true(float(downhill_choice["strategy_caution_pressure"]) > float(level_choice["strategy_caution_pressure"]), "downhill fast context creates more caution pressure")

	_assert_near(float(bold_short["aim_offset_feet"]), float(short_level["aim_offset_feet"]), 0.000001, "strategy does not rewrite the green read")
	_assert_true(str(bold_short.get("signature", "")) == str(short_level.get("signature", "")), "strategy preserves planned putt identity")

	bold.free()
	cautious.free()
	strong_cautious.free()

	if failures == 0:
		print("POC-15D PUTTING STRATEGY TESTS PASSED")
		quit(0)
	else:
		push_error("POC-15D PUTTING STRATEGY TESTS FAILED: %d" % failures)
		quit(1)


func _golfer(putting: float, risk: float, confidence: float) -> Node:
	var golfer = QuietGolfer.new()
	golfer.profile = 1
	golfer.apply_profile()
	golfer.putting = putting
	golfer.risk_tolerance = risk
	golfer.confidence = confidence
	return golfer


func _assert_true(value: bool, label: String) -> void:
	if value:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)


func _assert_near(actual: float, expected: float, tolerance: float, label: String) -> void:
	_assert_true(absf(actual - expected) <= tolerance, label)
