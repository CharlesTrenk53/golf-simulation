extends SceneTree

const QuietGolfer = preload("res://tests/fixtures/poc19_quiet_golfer.gd")
const CourseFixture = preload("res://tests/fixtures/poc19_strategic_course_fixture.gd")
const RoundBehaviorAdjustmentModel = preload("res://simulation/round_behavior_adjustment_model.gd")
const DataDefinedAutonomousHole = preload("res://simulation/data_defined_autonomous_hole.gd")

var failures: int = 0


func _init() -> void:
	print("POC-20D: contextual behavior adjustments")
	var golfer = QuietGolfer.new()
	golfer.profile = golfer.GolferProfile.CAREFUL_CARL
	golfer.apply_profile()
	golfer.decision_variability = 0.0

	var model = RoundBehaviorAdjustmentModel.new()
	var original_risk: float = golfer.risk_tolerance

	var neutral: Dictionary = model.build(golfer, {
		"confidence_momentum_signal": 0.0,
		"physical_load_exposure": 0.0
	})
	var good_form: Dictionary = model.build(golfer, {
		"confidence_momentum_signal": 0.85,
		"physical_load_exposure": 0.0
	})
	var bad_form: Dictionary = model.build(golfer, {
		"confidence_momentum_signal": -0.85,
		"physical_load_exposure": 0.0
	})
	var loaded: Dictionary = model.build(golfer, {
		"confidence_momentum_signal": 0.0,
		"physical_load_exposure": 0.75
	})

	_assert_float_close(float(neutral.get("effective_risk_tolerance", -1.0)), original_risk, 0.0001, "neutral context preserves baseline risk tolerance")
	_assert_true(float(good_form.get("effective_risk_tolerance", 0.0)) > original_risk, "positive recent form modestly raises effective risk tolerance")
	_assert_true(float(bad_form.get("effective_risk_tolerance", 100.0)) < original_risk, "negative recent form modestly lowers effective risk tolerance")
	_assert_float_close(
		float(good_form.get("risk_tolerance_shift", 0.0)),
		-float(bad_form.get("risk_tolerance_shift", 0.0)),
		0.0001,
		"equal good and bad form create symmetric risk shifts"
	)
	_assert_float_close(float(neutral.get("execution_dispersion_multiplier", 0.0)), 1.0, 0.0001, "zero load leaves execution dispersion neutral")
	_assert_true(float(loaded.get("execution_dispersion_multiplier", 1.0)) > 1.0, "physical load widens execution dispersion")
	_assert_true(float(loaded.get("execution_dispersion_multiplier", 99.0)) <= 1.20, "execution dispersion increase remains bounded")
	_assert_float_close(golfer.risk_tolerance, original_risk, 0.0001, "transient adjustment does not rewrite golfer risk tolerance")

	var course = CourseFixture.new().build_course()
	_assert_true(course != null, "strategic proving course builds")
	if course != null:
		var hole = course.hole_at(0)
		var neutral_playable = DataDefinedAutonomousHole.new(hole, "back")
		neutral_playable.set_round_context({}, {}, neutral)
		var neutral_state = neutral_playable.create_state(200401)
		var neutral_selection: Dictionary = neutral_playable.choose_course_strategy(golfer, neutral_state)
		var neutral_chosen: Dictionary = neutral_selection.get("chosen", {})
		_assert_float_close(float(neutral_chosen.get("risk_tolerance", -1.0)), original_risk, 0.0001, "strategy sees neutral effective risk tolerance")

		var good_playable = DataDefinedAutonomousHole.new(hole, "back")
		good_playable.set_round_context({}, {}, good_form)
		var good_state = good_playable.create_state(200401)
		var good_selection: Dictionary = good_playable.choose_course_strategy(golfer, good_state)
		var good_chosen: Dictionary = good_selection.get("chosen", {})
		_assert_true(float(good_chosen.get("risk_tolerance", 0.0)) > float(neutral_chosen.get("risk_tolerance", 0.0)), "strategy receives positive-form risk shift")

		var loaded_playable = DataDefinedAutonomousHole.new(hole, "back")
		loaded_playable.set_round_context({}, {}, loaded)
		var loaded_state = loaded_playable.create_state(200402)
		var loaded_shot: Dictionary = loaded_playable.play_step(golfer, loaded_state)
		_assert_true(not loaded_shot.is_empty(), "loaded context executes a course shot")
		_assert_float_close(
			float(loaded_shot.get("round_execution_dispersion_multiplier", 0.0)),
			float(loaded.get("execution_dispersion_multiplier", 0.0)),
			0.0001,
			"execution receives round dispersion multiplier"
		)
		_assert_true(float(loaded_shot.get("round_execution_dispersion_multiplier", 1.0)) > 1.0, "late-round load reaches execution without rewriting skill")

	print("POC20_BEHAVIOR_SUMMARY base_risk=%.1f good_risk=%.1f bad_risk=%.1f loaded_dispersion=%.3f" % [
		original_risk,
		float(good_form.get("effective_risk_tolerance", 0.0)),
		float(bad_form.get("effective_risk_tolerance", 0.0)),
		float(loaded.get("execution_dispersion_multiplier", 0.0))
	])

	golfer.free()
	_finish()


func _assert_true(value: bool, label: String) -> void:
	if value:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)


func _assert_float_close(actual: float, expected: float, tolerance: float, label: String) -> void:
	if absf(actual - expected) <= tolerance:
		print("PASS: %s (actual=%.6f expected=%.6f)" % [label, actual, expected])
	else:
		failures += 1
		push_error("FAIL: %s (actual=%.6f expected=%.6f)" % [label, actual, expected])


func _finish() -> void:
	if failures == 0:
		print("POC-20D CONTEXTUAL BEHAVIOR ADJUSTMENTS PASSED")
		quit(0)
	else:
		push_error("POC-20D CONTEXTUAL BEHAVIOR ADJUSTMENTS FAILED: %d" % failures)
		quit(1)
