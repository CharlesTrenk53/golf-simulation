extends SceneTree

const TechniqueSkillDevelopment = preload("res://simulation/technique_skill_development.gd")
const GolferLifecycle = preload("res://simulation/golfer_lifecycle.gd")
const GolfBag = preload("res://simulation/golf_bag.gd")
const QuietGolfer = preload("res://tests/quiet_golfer.gd")

const SHOT_TYPE := 0
const START_SKILL := 60.0
const START_PHYSICAL := 70.0
const PRIOR_EXPERIENCE := 100
const ROUNDS_PER_SEASON := 100
const DRIVER_SHOTS_PER_ROUND := 12
const SHOTS_PER_SEASON := ROUNDS_PER_SEASON * DRIVER_SHOTS_PER_ROUND
const SEASONS := 10
const TARGET_EXECUTION := 72.0
const EXECUTION_SD := 12.0
const START_AGES := [35, 55, 65]

var rng := RandomNumberGenerator.new()

func _init() -> void:
	print("AGEDEVCSV,start_age,current_age,season,shots,age_plasticity,physical_power,mobility,coordination,technical_skill,driver_carry,skill_change,carry_change")
	for start_age in START_AGES:
		_run_age_cohort(start_age)
	print("POC-08 AGE X TECHNICAL DEVELOPMENT DIAGNOSTIC COMPLETE")
	quit(0)

func _run_age_cohort(start_age: int) -> void:
	var golfer = _golfer(start_age)
	var model = TechniqueSkillDevelopment.new()
	var lifecycle = GolferLifecycle.new()
	var bag = GolfBag.new()
	model.initialize_from_golfer(golfer)
	# Reuse the same stochastic execution stream for every age cohort. Any difference
	# in technical development therefore comes from age plasticity, not shot quality.
	rng.seed = 52026

	var driver = bag.get_club("DRIVER")
	var start_carry = _carry_with_effective_skill(bag, driver, golfer, START_SKILL)
	_emit(start_age, 0, 0, golfer, model, bag, driver, START_SKILL, start_carry)

	var total_shots := 0
	for season in range(1, SEASONS + 1):
		# Technical plasticity follows chronological age during the career rather than
		# being frozen at initialization. Every shot in this season uses the golfer's
		# current age before lifecycle aging advances them into the following season.
		model.set_current_age(float(golfer.age))
		for _shot in range(SHOTS_PER_SEASON):
			var score = clamp(rng.randfn(TARGET_EXECUTION, EXECUTION_SD), 0.0, 100.0)
			var severity = (62.0 - score) / 37.0
			var lateral = clamp(severity * 4.0 + rng.randfn(0.0, 1.2), -4.0, 8.0)
			var distance = clamp(severity * -3.0 + rng.randfn(0.0, 0.8), -7.0, 3.0)
			model.record_execution(SHOT_TYPE, score, lateral, distance)
			total_shots += 1

		lifecycle.advance_year(golfer)
		model.set_current_age(float(golfer.age))
		var technical_skill = float(model.development_state(SHOT_TYPE)["effective_skill"])
		_emit(start_age, season, total_shots, golfer, model, bag, driver, technical_skill, start_carry)

	golfer.free()

func _golfer(start_age: int):
	var golfer = QuietGolfer.new()
	golfer.profile = 2
	golfer.apply_profile()
	golfer.golfer_name = "Age Development Calibration Golfer"
	golfer.age = start_age
	golfer.driving = START_SKILL
	golfer.physical_power = START_PHYSICAL
	golfer.mobility = START_PHYSICAL
	golfer.coordination = START_PHYSICAL
	golfer.endurance = START_PHYSICAL
	golfer.career_shot_experience[SHOT_TYPE] = PRIOR_EXPERIENCE
	golfer.skill_learning_rates[SHOT_TYPE] = 1.0
	return golfer

func _carry_with_effective_skill(bag, driver: Dictionary, golfer, technical_skill: float) -> float:
	var original_driving = golfer.driving
	golfer.driving = technical_skill
	var carry = bag.effective_carry(driver, golfer, "TEE", 1.0)
	golfer.driving = original_driving
	return carry

func _emit(start_age: int, season: int, shots: int, golfer, model, bag, driver: Dictionary, technical_skill: float, start_carry: float) -> void:
	var carry = _carry_with_effective_skill(bag, driver, golfer, technical_skill)
	var plasticity = float(model.development_state(SHOT_TYPE)["age_learning_plasticity"])
	print("AGEDEVCSV,%d,%d,%d,%d,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f" % [
		start_age,
		int(golfer.age),
		season,
		shots,
		plasticity,
		float(golfer.physical_power),
		float(golfer.mobility),
		float(golfer.coordination),
		technical_skill,
		carry,
		technical_skill - START_SKILL,
		carry - start_carry
	])
