extends SceneTree

const QuietGolfer = preload("res://tests/quiet_golfer.gd")
const TechniqueSkillDevelopment = preload("res://simulation/technique_skill_development.gd")

var failures := 0

func _init() -> void:
	_test_youth_has_no_annual_retention_erosion()
	_test_older_age_has_modest_annual_retention_erosion()
	_test_annual_retention_is_independent_of_shot_count()

	if failures == 0:
		print("POC-08 AGE RETENTION TESTS PASSED")
		quit(0)
	else:
		push_error("POC-08 AGE RETENTION TESTS FAILED: %d" % failures)
		quit(1)

func _test_youth_has_no_annual_retention_erosion() -> void:
	var golfer = QuietGolfer.new()
	golfer.profile = 1
	golfer.apply_profile()

	var model = TechniqueSkillDevelopment.new()
	model.initialize_from_golfer(golfer)
	model.set_current_age(55.0)
	model.skill_delta[0] = 10.0

	var before = float(model.skill_delta[0])
	model.advance_year()
	var after = float(model.skill_delta[0])

	_expect(
		abs(after - before) < 0.000001,
		"age 55 has no annual technical-retention erosion"
	)

	golfer.free()

func _test_older_age_has_modest_annual_retention_erosion() -> void:
	var golfer = QuietGolfer.new()
	golfer.profile = 1
	golfer.apply_profile()

	var model = TechniqueSkillDevelopment.new()
	model.initialize_from_golfer(golfer)
	model.set_current_age(70.0)
	model.skill_delta[0] = 10.0

	var before = float(model.skill_delta[0])
	var expected_rate = model.age_retention_rate()
	model.advance_year()
	var after = float(model.skill_delta[0])
	var expected_after = before * (1.0 - expected_rate)

	_expect(expected_rate > 0.0, "age 70 has positive annual retention pressure")
	_expect(after < before, "age 70 modestly erodes acquired above-baseline skill")
	_expect(
		abs(after - expected_after) < 0.000001,
		"age 70 annual erosion matches the configured retention rate"
	)
	_expect(
		(before - after) < 0.10,
		"one year of age-70 retention erosion remains modest"
	)

	golfer.free()

func _test_annual_retention_is_independent_of_shot_count() -> void:
	var low_exposure_golfer = QuietGolfer.new()
	low_exposure_golfer.profile = 1
	low_exposure_golfer.apply_profile()

	var high_exposure_golfer = QuietGolfer.new()
	high_exposure_golfer.profile = 1
	high_exposure_golfer.apply_profile()

	var low_exposure_model = TechniqueSkillDevelopment.new()
	low_exposure_model.initialize_from_golfer(low_exposure_golfer)
	low_exposure_model.set_current_age(70.0)

	var high_exposure_model = TechniqueSkillDevelopment.new()
	high_exposure_model.initialize_from_golfer(high_exposure_golfer)
	high_exposure_model.set_current_age(70.0)

	for _shot in range(200):
		high_exposure_model.record_execution(0, 62.0, 0.0, 0.0)

	# Give both golfers the exact same acquired skill immediately before the
	# between-season transition. Their different shot histories must not alter
	# the annual time-based retention effect.
	low_exposure_model.skill_delta[0] = 10.0
	high_exposure_model.skill_delta[0] = 10.0

	low_exposure_model.advance_year()
	high_exposure_model.advance_year()

	var low_after = float(low_exposure_model.skill_delta[0])
	var high_after = float(high_exposure_model.skill_delta[0])

	_expect(
		int(low_exposure_model.development_state(0)["evidence_count"]) == 0,
		"low-exposure comparison golfer has no recorded shots"
	)
	_expect(
		int(high_exposure_model.development_state(0)["evidence_count"]) == 200,
		"high-exposure comparison golfer has 200 recorded shots"
	)
	_expect(
		abs(low_after - high_after) < 0.000001,
		"annual retention erosion is independent of prior shot count"
	)

	low_exposure_golfer.free()
	high_exposure_golfer.free()

func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)
