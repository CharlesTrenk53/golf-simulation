extends SceneTree

const PuttingReadModel = preload("res://simulation/putting_read_model.gd")
const PuttingRollModel = preload("res://simulation/putting_roll_model.gd")

var failures: int = 0


func _init() -> void:
	print("POC-15C: putting roll and outcome")
	var read_model = PuttingReadModel.new()
	var roll_model = PuttingRollModel.new()

	var level: Dictionary = read_model.plan_putt(12.0, 0.0, 0.0, 10.0)
	var level_execution := _perfect_execution(level)
	var level_outcome: Dictionary = roll_model.resolve(level, level_execution)
	_assert_true(bool(level_outcome["holed"]), "well-read level putt with good pace holes out")
	_assert_near(float(level_outcome["final_lateral_feet"]), 0.0, 0.001, "level roll stays centered")

	var underhit := level_execution.duplicate(true)
	underhit["actual_distance_feet"] = 10.5
	var short_outcome: Dictionary = roll_model.resolve(level, underhit)
	_assert_true(not bool(short_outcome["holed"]), "underhit putt does not hole")
	_assert_true(float(short_outcome["distance_short_of_hole_feet"]) > 1.0, "underhit putt finishes short")

	var blasted := level_execution.duplicate(true)
	blasted["actual_distance_feet"] = 18.0
	var fast_outcome: Dictionary = roll_model.resolve(level, blasted)
	_assert_true(not bool(fast_outcome["holed"]), "excessive pace prevents cup capture")
	_assert_true(float(fast_outcome["distance_past_hole_feet"]) > 3.0, "blasted putt runs well past")

	var pushed := level_execution.duplicate(true)
	pushed["actual_aim_offset_feet"] = 0.5
	var pushed_outcome: Dictionary = roll_model.resolve(level, pushed)
	_assert_true(not bool(pushed_outcome["holed"]), "large line error misses the cup")
	_assert_true(str(pushed_outcome["miss_side"]) == "POSITIVE", "positive residual line misses positive side")

	var breaking: Dictionary = read_model.plan_putt(20.0, 2.0, 0.0, 10.0)
	var compensated_outcome: Dictionary = roll_model.resolve(breaking, _perfect_execution(breaking))
	_assert_near(float(compensated_outcome["final_lateral_feet"]), 0.0, 0.001, "correct cross-slope read cancels deterministic break")
	_assert_true(bool(compensated_outcome["holed"]), "correctly compensated breaking putt can hole")

	var straight_at_break := _perfect_execution(breaking)
	straight_at_break["actual_aim_offset_feet"] = 0.0
	var uncompensated_outcome: Dictionary = roll_model.resolve(breaking, straight_at_break)
	_assert_true(float(uncompensated_outcome["final_lateral_feet"]) < 0.0, "uncompensated positive cross slope breaks negative")
	_assert_true(not bool(uncompensated_outcome["holed"]), "uncompensated breaking putt misses")

	var uphill: Dictionary = read_model.plan_putt(20.0, 0.0, 2.0, 10.0)
	var uphill_outcome: Dictionary = roll_model.resolve(uphill, _perfect_execution(uphill))
	_assert_true(bool(uphill_outcome["holed"]), "uphill pace read converts back to a makeable roll")

	var downhill: Dictionary = read_model.plan_putt(20.0, 0.0, -2.0, 10.0)
	var downhill_outcome: Dictionary = roll_model.resolve(downhill, _perfect_execution(downhill))
	_assert_true(bool(downhill_outcome["holed"]), "downhill pace read converts back to a makeable roll")

	# Regression: the cup is a circular capture area, not a centerline checkpoint.
	# A centered putt that reaches the front portion of the cup opening must fall;
	# one that stops before the opening must remain short.
	var one_foot: Dictionary = read_model.plan_putt(1.0, 0.0, 0.0, 10.0)
	var enters_cup := _perfect_execution(one_foot)
	enters_cup["actual_distance_feet"] = 0.85
	var enters_cup_outcome: Dictionary = roll_model.resolve(one_foot, enters_cup)
	_assert_true(bool(enters_cup_outcome["holed"]), "putt holes when centered path reaches circular cup opening before center")
	_assert_true(bool(enters_cup_outcome["reached_capture_zone"]), "front-edge cup entry is recognized as capture-zone reach")
	_assert_true(not bool(enters_cup_outcome["reached_hole"]), "front-edge capture does not require reaching cup center")

	var before_cup := _perfect_execution(one_foot)
	before_cup["actual_distance_feet"] = 0.75
	var before_cup_outcome: Dictionary = roll_model.resolve(one_foot, before_cup)
	_assert_true(not bool(before_cup_outcome["holed"]), "putt stopping before cup opening remains short")
	_assert_true(not bool(before_cup_outcome["reached_capture_zone"]), "short putt does not falsely enter capture zone")

	# Safety normalization for an impossible legacy state: if a ball is already
	# represented with its center inside the cup radius, execution noise must never
	# produce repeated zero-distance misses.
	var inside_cup: Dictionary = read_model.plan_putt(0.10, 0.0, 0.0, 10.0)
	var wild_inside_execution := {
		"actual_aim_offset_feet": 1.0,
		"actual_distance_feet": 5.0
	}
	var inside_cup_outcome: Dictionary = roll_model.resolve(inside_cup, wild_inside_execution)
	_assert_true(bool(inside_cup_outcome["already_in_cup"]), "near-zero legacy state is recognized inside cup radius")
	_assert_true(bool(inside_cup_outcome["holed"]), "ball already inside cup radius cannot miss repeatedly from zero distance")
	_assert_near(float(inside_cup_outcome["finish_distance_from_hole_feet"]), 0.0, 0.0001, "inside-cup safety state resolves at hole")

	if failures == 0:
		print("POC-15C PUTTING ROLL TESTS PASSED")
		quit(0)
	else:
		push_error("POC-15C PUTTING ROLL TESTS FAILED: %d" % failures)
		quit(1)


func _perfect_execution(planned_putt: Dictionary) -> Dictionary:
	return {
		"actual_aim_offset_feet": float(planned_putt.get("aim_offset_feet", 0.0)),
		"actual_distance_feet": float(planned_putt.get("intended_distance_feet", 0.0))
	}


func _assert_true(value: bool, label: String) -> void:
	if value:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)


func _assert_near(actual: float, expected: float, tolerance: float, label: String) -> void:
	_assert_true(absf(actual - expected) <= tolerance, label)
