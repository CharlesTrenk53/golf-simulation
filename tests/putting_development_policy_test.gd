extends SceneTree

const QuietGolfer = preload("res://tests/quiet_golfer.gd")
const TechniqueSkillDevelopment = preload("res://simulation/technique_skill_development.gd")

const PUTT := 3
const DRIVE := 0

var failures: int = 0


func _init() -> void:
	print("POC-15C.5: putting development policy")
	_test_chronological_age_does_not_erode_putting()
	_test_putting_learning_rates_create_different_growth()

	if failures == 0:
		print("POC-15C.5 PUTTING DEVELOPMENT POLICY TESTS PASSED")
		quit(0)
	else:
		push_error("POC-15C.5 PUTTING DEVELOPMENT POLICY TESTS FAILED: %d" % failures)
		quit(1)


func _test_chronological_age_does_not_erode_putting() -> void:
	var golfer = QuietGolfer.new()
	golfer.profile = 1
	golfer.apply_profile()

	var model = TechniqueSkillDevelopment.new()
	model.initialize_from_golfer(golfer)
	model.set_current_age(70.0)
	model.skill_delta[DRIVE] = 10.0
	model.skill_delta[PUTT] = 10.0

	var drive_before: float = float(model.skill_delta[DRIVE])
	var putting_before: float = float(model.skill_delta[PUTT])
	model.advance_year()
	var drive_after: float = float(model.skill_delta[DRIVE])
	var putting_after: float = float(model.skill_delta[PUTT])

	_expect(model.age_retention_rate_for(DRIVE) > 0.0, "age 70 still applies technical retention pressure outside putting")
	_expect(model.age_retention_rate_for(PUTT) == 0.0, "putting has no chronological age-retention penalty")
	_expect(drive_after < drive_before, "age 70 can modestly erode acquired non-putting skill")
	_expect(absf(putting_after - putting_before) < 0.000001, "age alone does not erode acquired putting skill")

	golfer.free()


func _test_putting_learning_rates_create_different_growth() -> void:
	var slow_learner = QuietGolfer.new()
	slow_learner.profile = 1
	slow_learner.apply_profile()
	slow_learner.putting = 60.0
	slow_learner.age = 35
	slow_learner.career_shot_experience[PUTT] = 1000
	slow_learner.skill_learning_rates[PUTT] = 0.60

	var fast_learner = QuietGolfer.new()
	fast_learner.profile = 1
	fast_learner.apply_profile()
	fast_learner.putting = 60.0
	fast_learner.age = 35
	fast_learner.career_shot_experience[PUTT] = 1000
	fast_learner.skill_learning_rates[PUTT] = 1.40

	var slow_model = TechniqueSkillDevelopment.new()
	slow_model.initialize_from_golfer(slow_learner)
	var fast_model = TechniqueSkillDevelopment.new()
	fast_model.initialize_from_golfer(fast_learner)

	for _rep in range(180):
		slow_model.record_execution(PUTT, 92.0, 0.0, 0.0)
		fast_model.record_execution(PUTT, 92.0, 0.0, 0.0)

	var slow_state: Dictionary = slow_model.development_state(PUTT)
	var fast_state: Dictionary = fast_model.development_state(PUTT)
	var slow_gain: float = float(slow_state["skill_delta"])
	var fast_gain: float = float(fast_state["skill_delta"])

	_expect(slow_gain > 0.0, "slower putting learner still improves with sustained strong practice")
	_expect(fast_gain > slow_gain, "higher putting learning aptitude produces faster skill growth under equal practice")
	_expect(absf(float(slow_state["baseline_skill"]) - float(fast_state["baseline_skill"])) < 0.000001, "learning-rate comparison starts from equal putting ability")
	_expect(int(slow_state["total_experience"]) == int(fast_state["total_experience"]), "learning-rate comparison uses equal putting exposure")

	slow_learner.free()
	fast_learner.free()


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)
