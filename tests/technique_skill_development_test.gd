extends SceneTree

const QuietGolfer = preload("res://tests/quiet_golfer.gd")
const TechniqueSkillDevelopment = preload("res://simulation/technique_skill_development.gd")

var failures := 0

func _init() -> void:
	var novice = QuietGolfer.new()
	novice.profile = 1
	novice.apply_profile()
	novice.career_shot_experience[0] = 100
	var veteran = QuietGolfer.new()
	veteran.profile = 1
	veteran.apply_profile()
	veteran.career_shot_experience[0] = 8000

	var novice_model = TechniqueSkillDevelopment.new()
	novice_model.initialize_from_golfer(novice)
	var veteran_model = TechniqueSkillDevelopment.new()
	veteran_model.initialize_from_golfer(veteran)

	var novice_base = novice_model.development_state(0)
	var veteran_base = veteran_model.development_state(0)
	_expect(abs(float(novice_base["skill_delta"])) < 0.001, "skill starts at established baseline")
	_expect(float(veteran_base["experience_stability"]) > float(novice_base["experience_stability"]), "large experience history creates stronger skill stability")

	# Short slumps can affect confidence/technique but must not alter true skill.
	for i in range(20):
		novice_model.record_execution(0, 22.0, 8.0, -5.0)
		veteran_model.record_execution(0, 22.0, 8.0, -5.0)
	var novice_short = novice_model.development_state(0)
	var veteran_short = veteran_model.development_state(0)
	_expect(abs(float(novice_short["skill_delta"])) < 0.001, "short slump does not change novice true skill")
	_expect(abs(float(veteran_short["skill_delta"])) < 0.001, "short slump does not change veteran true skill")
	_expect(float(novice_short["technique_bias"]["lateral"]) > 0.0, "repeated directional misses begin forming a technique pattern")

	# Same sustained slump, different experience. Both may drift, but the veteran's
	# established motor pattern should strongly resist permanent deterioration.
	for i in range(580):
		novice_model.record_execution(0, 20.0, 8.5, -5.5)
		veteran_model.record_execution(0, 20.0, 8.5, -5.5)
	var novice_slump = novice_model.development_state(0)
	var veteran_slump = veteran_model.development_state(0)
	_expect(float(novice_slump["skill_delta"]) < 0.0, "hundreds of poor executions can eventually lower true skill")
	_expect(float(novice_slump["skill_delta"]) > -2.5, "true skill decline remains slow over hundreds of repetitions")
	_expect(float(veteran_slump["skill_delta"]) > float(novice_slump["skill_delta"]), "established experience limits skill decline under the same slump")
	_expect(abs(float(veteran_slump["skill_delta"])) < 1.25, "highly established skill remains strongly anchored")
	_expect(float(veteran_slump["technique_bias"]["dispersion"]) < float(novice_slump["technique_bias"]["dispersion"]), "experience also resists embedding a bad technique pattern")

	# Excellent recent execution should begin recovery for both. The veteran's
	# stronger established pattern should help pull skill back toward baseline.
	var novice_before_recovery = float(novice_slump["skill_delta"])
	var veteran_before_recovery = float(veteran_slump["skill_delta"])
	for i in range(40):
		novice_model.record_execution(0, 92.0, 0.0, 0.0)
		veteran_model.record_execution(0, 92.0, 0.0, 0.0)
	var novice_recovery = novice_model.development_state(0)
	var veteran_recovery = veteran_model.development_state(0)
	var novice_gain = float(novice_recovery["skill_delta"]) - novice_before_recovery
	var veteran_gain = float(veteran_recovery["skill_delta"]) - veteran_before_recovery
	_expect(novice_gain > 0.0, "excellent execution begins gradual novice recovery")
	_expect(veteran_gain > 0.0, "excellent execution begins gradual veteran recovery")
	_expect(veteran_gain > novice_gain, "established golfer self-corrects more efficiently once execution improves")
	_expect(float(novice_recovery["skill_delta"]) < -0.05, "short recovery streak cannot instantly erase a long slump")

	print("============================================================")
	print("POC-08 EXPERIENCE-STABILIZED SKILL DEVELOPMENT")
	print("Novice stability: %.3f | slump delta: %.3f | recovery delta: %.3f" % [float(novice_base["experience_stability"]), float(novice_slump["skill_delta"]), float(novice_recovery["skill_delta"])])
	print("Veteran stability: %.3f | slump delta: %.3f | recovery delta: %.3f" % [float(veteran_base["experience_stability"]), float(veteran_slump["skill_delta"]), float(veteran_recovery["skill_delta"])])
	print("============================================================")
	novice.free()
	veteran.free()
	if failures == 0:
		print("POC-08 TECHNIQUE & SKILL DEVELOPMENT TESTS PASSED")
		quit(0)
	else:
		push_error("POC-08 TECHNIQUE & SKILL DEVELOPMENT TESTS FAILED: %d" % failures)
		quit(1)

func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)
