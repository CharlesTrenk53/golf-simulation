extends SceneTree

const TechniqueSkillDevelopment = preload("res://simulation/technique_skill_development.gd")
const QuietGolfer = preload("res://tests/quiet_golfer.gd")

const DRIVE := 0
const PUTT := 3

func _init() -> void:
	_test_skill_specific_rates_diverge_new_learning()
	_test_aptitude_does_not_accelerate_deterioration()
	print("POC-08 SKILL LEARNING APTITUDE TESTS PASSED")
	quit(0)

func _test_skill_specific_rates_diverge_new_learning() -> void:
	var golfer = _golfer(50.0, 100)
	golfer.skill_learning_rates = {DRIVE: 1.40, PUTT: 0.70}
	var model = TechniqueSkillDevelopment.new()
	model.initialize_from_golfer(golfer)

	for _shot in range(4000):
		model.record_execution(DRIVE, 75.0, 0.0, 0.0)
		model.record_execution(PUTT, 75.0, 0.0, 0.0)

	var drive_state: Dictionary = model.development_state(DRIVE)
	var putt_state: Dictionary = model.development_state(PUTT)
	assert(is_equal_approx(float(drive_state["learning_aptitude"]), 1.40))
	assert(is_equal_approx(float(putt_state["learning_aptitude"]), 0.70))
	assert(float(drive_state["skill_delta"]) > float(putt_state["skill_delta"]))
	assert(float(drive_state["skill_delta"]) > float(putt_state["skill_delta"]) * 1.20)
	golfer.free()

func _test_aptitude_does_not_accelerate_deterioration() -> void:
	var slow_learner = _golfer(70.0, 100)
	var fast_learner = _golfer(70.0, 100)
	slow_learner.skill_learning_rates = {DRIVE: 0.50}
	fast_learner.skill_learning_rates = {DRIVE: 1.50}
	var slow_model = TechniqueSkillDevelopment.new()
	var fast_model = TechniqueSkillDevelopment.new()
	slow_model.initialize_from_golfer(slow_learner)
	fast_model.initialize_from_golfer(fast_learner)

	for _shot in range(1500):
		slow_model.record_execution(DRIVE, 50.0, 1.0, -1.0)
		fast_model.record_execution(DRIVE, 50.0, 1.0, -1.0)

	var slow_delta: float = float(slow_model.development_state(DRIVE)["skill_delta"])
	var fast_delta: float = float(fast_model.development_state(DRIVE)["skill_delta"])
	assert(abs(slow_delta - fast_delta) < 0.000001)
	slow_learner.free()
	fast_learner.free()

func _golfer(base_skill: float, prior_experience: int):
	var golfer = QuietGolfer.new()
	golfer.profile = 2
	golfer.apply_profile()
	golfer.driving = base_skill
	golfer.putting = base_skill
	golfer.career_shot_experience[DRIVE] = prior_experience
	golfer.career_shot_experience[PUTT] = prior_experience
	return golfer
