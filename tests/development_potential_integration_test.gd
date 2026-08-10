extends SceneTree

const QuietGolfer = preload("res://tests/quiet_golfer.gd")
const TechniqueSkillDevelopment = preload("res://simulation/technique_skill_development.gd")

var failures := 0

func _init() -> void:
	_test_higher_potential_supports_more_long_run_growth()
	_test_potential_does_not_change_deterioration_channel()

	if failures == 0:
		print("POC-09 POTENTIAL INTEGRATION TESTS PASSED")
		quit(0)
	else:
		push_error("POC-09 POTENTIAL INTEGRATION TESTS FAILED: %d" % failures)
		quit(1)

func _test_higher_potential_supports_more_long_run_growth() -> void:
	var low_golfer = QuietGolfer.new()
	low_golfer.profile = 1
	low_golfer.apply_profile()
	low_golfer.driving = 50.0
	low_golfer.age = 24

	var high_golfer = QuietGolfer.new()
	high_golfer.profile = 1
	high_golfer.apply_profile()
	high_golfer.driving = 50.0
	high_golfer.age = 24

	var low_model = TechniqueSkillDevelopment.new()
	low_model.initialize_from_golfer(low_golfer)
	low_model.set_skill_potential(0, 62.0)

	var high_model = TechniqueSkillDevelopment.new()
	high_model.initialize_from_golfer(high_golfer)
	high_model.set_skill_potential(0, 90.0)

	for _shot in range(8000):
		low_model.record_execution(0, 80.0, 0.0, 0.0, 80.0)
		high_model.record_execution(0, 80.0, 0.0, 0.0, 80.0)

	var low_skill = float(low_model.development_state(0)["effective_skill"])
	var high_skill = float(high_model.development_state(0)["effective_skill"])

	_expect(high_skill > low_skill, "higher latent potential produces greater long-run skill under identical evidence")
	_expect(low_skill > 50.0, "lower potential remains a soft resistance rather than a hard cap")
	_expect(float(low_model.development_state(0)["potential_resistance"]) < float(high_model.development_state(0)["potential_resistance"]), "lower-potential golfer experiences more acquisition resistance")

	low_golfer.free()
	high_golfer.free()

func _test_potential_does_not_change_deterioration_channel() -> void:
	var low_golfer = QuietGolfer.new()
	low_golfer.profile = 1
	low_golfer.apply_profile()

	var high_golfer = QuietGolfer.new()
	high_golfer.profile = 1
	high_golfer.apply_profile()

	var low_model = TechniqueSkillDevelopment.new()
	low_model.initialize_from_golfer(low_golfer)
	low_model.set_skill_potential(0, 65.0)
	low_model.skill_delta[0] = 6.0

	var high_model = TechniqueSkillDevelopment.new()
	high_model.initialize_from_golfer(high_golfer)
	high_model.set_skill_potential(0, 95.0)
	high_model.skill_delta[0] = 6.0

	for _shot in range(120):
		low_model.record_execution(0, 45.0, 0.0, 0.0, 45.0)
		high_model.record_execution(0, 45.0, 0.0, 0.0, 45.0)

	var low_delta = float(low_model.development_state(0)["skill_delta"])
	var high_delta = float(high_model.development_state(0)["skill_delta"])

	_expect(abs(low_delta - high_delta) < 0.000001, "potential does not accelerate or protect deterioration")

	low_golfer.free()
	high_golfer.free()

func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)
