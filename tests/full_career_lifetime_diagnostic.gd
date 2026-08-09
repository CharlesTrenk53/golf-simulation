extends SceneTree

const TechniqueSkillDevelopment = preload("res://simulation/technique_skill_development.gd")
const GolferLifecycle = preload("res://simulation/golfer_lifecycle.gd")
const QuietGolfer = preload("res://tests/quiet_golfer.gd")

# POC-08 full-career stress test
# ------------------------------
# This diagnostic intentionally does not retune any POC-08 coefficient. It combines
# the existing physical-aging and technical-development systems over a full lifetime
# and varies only annual exposure plus persistent stochastic good/bad stretches.
#
# Execution quality is development evidence, not the golfer's absolute ability score.
# A stable +3 point learning environment above the model's neutral 62.0 center gives
# the golfer a consistent opportunity to improve at every age. Age plasticity,
# experience, resistance, exposure, and random career form decide how much sticks.

const START_AGE := 16
const END_AGE := 76
const CAREER_COUNT := 12
const EXECUTION_NEUTRAL := 62.0
const LEARNING_SIGNAL := 3.0
const EXECUTION_SD := 10.0
const FORM_PERSISTENCE := 0.72
const FORM_INNOVATION_SD := 2.2

const SHOT_TYPES := [0, 1, 2, 3]
const SHOTS_PER_ROUND := {
	0: 14,
	1: 22,
	2: 12,
	3: 30
}
const PRACTICE_MIX := {
	0: 0.90,
	1: 1.15,
	2: 1.20,
	3: 1.00
}

var rng := RandomNumberGenerator.new()

func _init() -> void:
	print("career,seed,age,rounds,annual_shots,cumulative_shots,form,execution_mean,physical_capacity,power,mobility,coordination,endurance,driver_carry,technical_composite,performance_index,drive_skill,approach_skill,short_game_skill,putt_skill,age_plasticity,drive_experience,approach_experience,short_game_experience,putt_experience")

	for career_index in range(CAREER_COUNT):
		var seed_value: int = 88001 + career_index
		_run_career(career_index + 1, seed_value)

	print("POC-08 FULL CAREER LIFETIME DIAGNOSTIC COMPLETE")
	quit(0)

func _run_career(career_number: int, seed_value: int) -> void:
	var golfer = _create_golfer()
	var lifecycle = GolferLifecycle.new()
	var development = TechniqueSkillDevelopment.new()
	development.initialize_from_golfer(golfer)
	rng.seed = seed_value

	var cumulative_shots: int = 0
	var career_form: float = 0.0

	for age in range(START_AGE, END_AGE + 1):
		golfer.age = age
		development.set_current_age(age)

		# AR(1)-style form creates multi-year good/bad stretches instead of unrelated
		# annual noise. It changes the evidence produced that year, not innate aptitude.
		career_form = FORM_PERSISTENCE * career_form + rng.randfn(0.0, FORM_INNOVATION_SD)

		var exposure: Dictionary = _annual_exposure(age)
		var rounds: int = int(exposure["rounds"])
		var annual_shots: int = 0
		var execution_sum: float = 0.0

		for shot_type in SHOT_TYPES:
			var shot_count: int = int(exposure["shots"][shot_type])
			var physical_execution_modifier: float = _physical_execution_modifier(golfer, shot_type)
			var target_mean: float = EXECUTION_NEUTRAL + LEARNING_SIGNAL + career_form + physical_execution_modifier

			for _shot in range(shot_count):
				var score: float = clampf(rng.randfn(target_mean, EXECUTION_SD), 0.0, 100.0)
				execution_sum += score
				annual_shots += 1
				_record_execution(development, shot_type, score)

		cumulative_shots += annual_shots
		_emit_year(career_number, seed_value, golfer, development, age, rounds, annual_shots, cumulative_shots, career_form, execution_sum / float(maxi(annual_shots, 1)))

		if age < END_AGE:
			lifecycle.advance_year(golfer)

	golfer.free()

func _create_golfer():
	var golfer = QuietGolfer.new()
	golfer.profile = 2
	golfer.apply_profile()
	golfer.golfer_name = "POC-08 Lifetime Golfer"

	# Same starting person for every seed. Only stochastic realization differs.
	golfer.age = START_AGE
	golfer.driving = 48.0
	golfer.approach = 45.0
	golfer.short_game = 42.0
	golfer.putting = 44.0
	golfer.driving_distance = 55.0

	golfer.physical_power = 68.0
	golfer.mobility = 72.0
	golfer.coordination = 70.0
	golfer.endurance = 70.0

	golfer.career_shot_experience = {
		0: 800,
		1: 1200,
		2: 900,
		3: 1400
	}
	golfer.skill_learning_rates = {
		0: 1.05,
		1: 1.00,
		2: 1.10,
		3: 0.95
	}
	return golfer

func _annual_exposure(age: int) -> Dictionary:
	var base_rounds: int
	var practice_multiplier: float

	if age <= 18:
		base_rounds = 75
		practice_multiplier = 2.20
	elif age <= 24:
		base_rounds = 95
		practice_multiplier = 2.50
	elif age <= 45:
		base_rounds = 80
		practice_multiplier = 1.80
	elif age <= 60:
		base_rounds = 65
		practice_multiplier = 1.40
	elif age <= 70:
		base_rounds = 50
		practice_multiplier = 1.00
	else:
		base_rounds = 35
		practice_multiplier = 0.70

	# Opportunity varies year to year but does not collapse to unrealistic zero-use
	# seasons in this first integrated test. Life events/injury belong in later POCs.
	var rounds: int = maxi(12, int(round(base_rounds * clampf(rng.randfn(1.0, 0.12), 0.65, 1.35))))
	var shots: Dictionary = {}
	for shot_type in SHOT_TYPES:
		var on_course: int = rounds * int(SHOTS_PER_ROUND[shot_type])
		var practice: int = int(round(on_course * practice_multiplier * float(PRACTICE_MIX[shot_type])))
		shots[shot_type] = maxi(60, on_course + practice)

	return {"rounds": rounds, "shots": shots}

func _physical_execution_modifier(golfer, shot_type: int) -> float:
	# Physical decline is already expressed strongly through carry. Keep its effect
	# on execution evidence deliberately small so aging does not secretly become a
	# second direct technical-skill penalty. Long shots are affected most.
	var factor: float = golfer.physical_distance_factor(shot_type)
	var sensitivity: float = 0.0
	match shot_type:
		0:
			sensitivity = 2.0
		1:
			sensitivity = 1.2
		2:
			sensitivity = 0.4
		3:
			sensitivity = 0.1
	return (factor - 1.0) * sensitivity

func _record_execution(development, shot_type: int, score: float) -> void:
	# Preserve the same score-to-error relationship used by the prior stochastic
	# career diagnostic so this test adds integration rather than a new error model.
	var severity: float = (EXECUTION_NEUTRAL - score) / 37.0
	var lateral: float = clampf(severity * 4.0 + rng.randfn(0.0, 1.2), -4.0, 8.0)
	var distance: float = clampf(severity * -3.0 + rng.randfn(0.0, 0.8), -7.0, 3.0)
	development.record_execution(shot_type, score, lateral, distance)

func _emit_year(career_number: int, seed_value: int, golfer, development, age: int, rounds: int, annual_shots: int, cumulative_shots: int, career_form: float, execution_mean: float) -> void:
	var states: Dictionary = {}
	var technical_sum: float = 0.0
	for shot_type in SHOT_TYPES:
		var state: Dictionary = development.development_state(shot_type)
		states[shot_type] = state
		technical_sum += float(state["effective_skill"])

	var technical_composite: float = technical_sum / float(SHOT_TYPES.size())
	var physical_capacity: float = (golfer.physical_power + golfer.mobility + golfer.coordination + golfer.endurance) / 4.0
	var driver_carry: float = _effective_driver_carry(golfer, float(states[0]["effective_skill"]))

	# Reporting-only index. It does not feed back into development. Technique is the
	# majority component, while carry and endurance let late-life physical decline
	# show up in one inspectable summary measure without erasing accumulated skill.
	var normalized_carry: float = clampf(driver_carry / 70.0 * 50.0, 0.0, 100.0)
	var performance_index: float = technical_composite * 0.72 + normalized_carry * 0.20 + golfer.endurance * 0.08

	print("LIFETIMECSV,%d,%d,%d,%d,%d,%d,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%d,%d,%d,%d" % [
		career_number,
		seed_value,
		age,
		rounds,
		annual_shots,
		cumulative_shots,
		career_form,
		execution_mean,
		physical_capacity,
		golfer.physical_power,
		golfer.mobility,
		golfer.coordination,
		golfer.endurance,
		driver_carry,
		technical_composite,
		performance_index,
		float(states[0]["effective_skill"]),
		float(states[1]["effective_skill"]),
		float(states[2]["effective_skill"]),
		float(states[3]["effective_skill"]),
		float(states[0]["age_learning_plasticity"]),
		int(states[0]["total_experience"]),
		int(states[1]["total_experience"]),
		int(states[2]["total_experience"]),
		int(states[3]["total_experience"])
	])

func _effective_driver_carry(golfer, effective_driving_skill: float) -> float:
	# Mirrors GolfBag.effective_carry for the Driver, but uses the development
	# model's effective skill rather than the golfer's immutable starting ability.
	var base_carry: float = 70.0
	var strike_factor: float = lerpf(0.94, 1.04, clampf(effective_driving_skill, 0.0, 100.0) / 100.0)
	return base_carry * strike_factor * golfer.physical_distance_factor(0)
