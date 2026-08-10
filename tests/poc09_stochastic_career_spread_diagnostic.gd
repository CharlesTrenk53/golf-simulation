extends SceneTree

const TechniqueSkillDevelopment = preload("res://simulation/technique_skill_development.gd")
const GolferLifecycle = preload("res://simulation/golfer_lifecycle.gd")
const QuietGolfer = preload("res://tests/quiet_golfer.gd")

# POC-09 stochastic career-spread diagnostic
# ------------------------------------------
# This is the first realism-oriented POC-09 test rather than an isolating pair test.
# Each golfer has distinct starting ability, skill-specific aptitude, latent potential,
# physical capacity, practice/exposure, and stochastic form/execution. Existing POC-08
# age plasticity, annual technical retention, and physical lifecycle aging all apply.

const START_AGE := 16
const END_AGE := 76
const EXECUTION_NEUTRAL := 62.0
const LEARNING_SIGNAL := 3.0
const EXECUTION_SD := 10.0
const FORM_PERSISTENCE := 0.72
const FORM_INNOVATION_SD := 2.2
const FORM_TO_PERSISTENT_SKILL_SHARE := 0.20
const OUTPUT_PATH := "res://poc09_stochastic_career_spread.csv"

const SHOT_TYPES := [0, 1, 2, 3]
const SHOTS_PER_ROUND := {0: 14, 1: 22, 2: 12, 3: 30}
const PRACTICE_MIX := {0: 0.90, 1: 1.15, 2: 1.20, 3: 1.00}

const ARCHETYPES := [
	{
		"id": "early_phenom", "label": "Early Phenom", "seed": 91001,
		"skills": {0: 54.0, 1: 51.0, 2: 49.0, 3: 50.0},
		"aptitude": {0: 1.25, 1: 1.20, 2: 1.15, 3: 1.15},
		"potential": {0: 72.0, 1: 74.0, 2: 72.0, 3: 70.0},
		"physical": [76.0, 76.0, 78.0, 74.0], "exposure": 1.10
	},
	{
		"id": "late_bloomer", "label": "Late Bloomer", "seed": 91002,
		"skills": {0: 41.0, 1: 40.0, 2: 39.0, 3: 41.0},
		"aptitude": {0: 0.88, 1: 0.90, 2: 0.92, 3: 0.88},
		"potential": {0: 82.0, 1: 84.0, 2: 83.0, 3: 80.0},
		"physical": [68.0, 72.0, 72.0, 70.0], "exposure": 1.05
	},
	{
		"id": "grinder", "label": "Grinder", "seed": 91003,
		"skills": {0: 44.0, 1: 44.0, 2: 43.0, 3: 44.0},
		"aptitude": {0: 1.00, 1: 1.02, 2: 1.05, 3: 1.00},
		"potential": {0: 69.0, 1: 72.0, 2: 73.0, 3: 70.0},
		"physical": [70.0, 73.0, 74.0, 75.0], "exposure": 1.30
	},
	{
		"id": "talented_underachiever", "label": "Talented Underachiever", "seed": 91004,
		"skills": {0: 51.0, 1: 50.0, 2: 48.0, 3: 49.0},
		"aptitude": {0: 1.20, 1: 1.20, 2: 1.18, 3: 1.15},
		"potential": {0: 82.0, 1: 84.0, 2: 82.0, 3: 80.0},
		"physical": [75.0, 74.0, 77.0, 69.0], "exposure": 0.62
	},
	{
		"id": "steady_competitor", "label": "Steady Competitor", "seed": 91005,
		"skills": {0: 47.0, 1: 47.0, 2: 46.0, 3: 47.0},
		"aptitude": {0: 1.02, 1: 1.05, 2: 1.02, 3: 1.00},
		"potential": {0: 72.0, 1: 74.0, 2: 73.0, 3: 72.0},
		"physical": [72.0, 74.0, 75.0, 74.0], "exposure": 1.00
	},
	{
		"id": "club_golfer", "label": "Club Golfer", "seed": 91006,
		"skills": {0: 39.0, 1: 40.0, 2: 40.0, 3: 42.0},
		"aptitude": {0: 0.95, 1: 0.95, 2: 1.00, 3: 0.95},
		"potential": {0: 60.0, 1: 62.0, 2: 64.0, 3: 63.0},
		"physical": [64.0, 68.0, 69.0, 66.0], "exposure": 0.55
	}
]

var rng := RandomNumberGenerator.new()
var output_rows: Array[String] = []

func _init() -> void:
	output_rows.append("archetype,label,seed,age,rounds,annual_shots,cumulative_shots,form,physical_capacity,driver_carry,technical_composite,performance_index,drive_skill,approach_skill,short_game_skill,putt_skill,mean_aptitude,mean_potential")
	for config in ARCHETYPES:
		_run_career(config)
	_write_output()
	print("POC-09 STOCHASTIC CAREER SPREAD DIAGNOSTIC COMPLETE")
	quit(0)

func _run_career(config: Dictionary) -> void:
	var golfer = _create_golfer(config)
	var lifecycle = GolferLifecycle.new()
	var development = TechniqueSkillDevelopment.new()
	development.initialize_from_golfer(golfer)
	for shot_type in SHOT_TYPES:
		development.set_skill_potential(shot_type, float(config["potential"][shot_type]))

	rng.seed = int(config["seed"])
	var cumulative_shots := 0
	var career_form := 0.0

	for age in range(START_AGE, END_AGE + 1):
		golfer.age = age
		development.set_current_age(age)
		career_form = FORM_PERSISTENCE * career_form + rng.randfn(0.0, FORM_INNOVATION_SD)
		var exposure_multiplier: float = float(config["exposure"]) * _career_stage_exposure_multiplier(config, age)
		var exposure := _annual_exposure(age, exposure_multiplier)
		var rounds := int(exposure["rounds"])
		var annual_shots := 0

		for shot_type in SHOT_TYPES:
			var shot_count := int(exposure["shots"][shot_type])
			var physical_execution_modifier := _physical_execution_modifier(golfer, shot_type)
			var target_mean := EXECUTION_NEUTRAL + LEARNING_SIGNAL + career_form + physical_execution_modifier
			for _shot in range(shot_count):
				var score := clampf(rng.randfn(target_mean, EXECUTION_SD), 0.0, 100.0)
				var persistent_score := clampf(score - career_form * (1.0 - FORM_TO_PERSISTENT_SKILL_SHARE), 0.0, 100.0)
				annual_shots += 1
				_record_execution(development, shot_type, score, persistent_score)

		cumulative_shots += annual_shots
		_emit_year(config, golfer, development, age, rounds, annual_shots, cumulative_shots, career_form)
		if age < END_AGE:
			development.advance_year()
			lifecycle.advance_year(golfer)
	golfer.free()

func _create_golfer(config: Dictionary):
	var golfer = QuietGolfer.new()
	golfer.profile = 2
	golfer.apply_profile()
	golfer.golfer_name = str(config["label"])
	golfer.age = START_AGE
	golfer.driving = float(config["skills"][0])
	golfer.approach = float(config["skills"][1])
	golfer.short_game = float(config["skills"][2])
	golfer.putting = float(config["skills"][3])
	golfer.driving_distance = 55.0
	golfer.physical_power = float(config["physical"][0])
	golfer.mobility = float(config["physical"][1])
	golfer.coordination = float(config["physical"][2])
	golfer.endurance = float(config["physical"][3])
	golfer.career_shot_experience = {0: 800, 1: 1200, 2: 900, 3: 1400}
	golfer.skill_learning_rates = config["aptitude"].duplicate(true)
	return golfer

func _career_stage_exposure_multiplier(config: Dictionary, age: int) -> float:
	if str(config["id"]) != "late_bloomer":
		return 1.0
	# A late bloomer is modeled as someone whose developmental opportunity arrives
	# later rather than someone whose biology suddenly changes. Early exposure is
	# deliberately limited; the largest sustained practice/playing window comes
	# between roughly 30 and 50 while the golfer still retains meaningful plasticity.
	if age <= 24:
		return 0.55
	if age <= 29:
		return 0.75
	if age <= 39:
		return 1.35
	if age <= 50:
		return 1.25
	return 1.0

func _annual_exposure(age: int, exposure_multiplier: float) -> Dictionary:
	var base_rounds: int
	var practice_multiplier: float
	if age <= 18:
		base_rounds = 75; practice_multiplier = 2.20
	elif age <= 24:
		base_rounds = 95; practice_multiplier = 2.50
	elif age <= 45:
		base_rounds = 80; practice_multiplier = 1.80
	elif age <= 60:
		base_rounds = 65; practice_multiplier = 1.40
	elif age <= 70:
		base_rounds = 50; practice_multiplier = 1.00
	else:
		base_rounds = 35; practice_multiplier = 0.70
	var stochastic_round_factor := clampf(rng.randfn(1.0, 0.12), 0.65, 1.35)
	var rounds := maxi(8, int(round(base_rounds * exposure_multiplier * stochastic_round_factor)))
	var shots: Dictionary = {}
	for shot_type in SHOT_TYPES:
		var on_course := rounds * int(SHOTS_PER_ROUND[shot_type])
		var practice := int(round(on_course * practice_multiplier * float(PRACTICE_MIX[shot_type]) * exposure_multiplier))
		shots[shot_type] = maxi(40, on_course + practice)
	return {"rounds": rounds, "shots": shots}

func _physical_execution_modifier(golfer, shot_type: int) -> float:
	var factor: float = float(golfer.physical_distance_factor(shot_type))
	var sensitivity := 0.0
	match shot_type:
		0: sensitivity = 2.0
		1: sensitivity = 1.2
		2: sensitivity = 0.4
		3: sensitivity = 0.1
	return (factor - 1.0) * sensitivity

func _record_execution(development, shot_type: int, score: float, persistent_score: float) -> void:
	var severity := (EXECUTION_NEUTRAL - score) / 37.0
	var lateral := clampf(severity * 4.0 + rng.randfn(0.0, 1.2), -4.0, 8.0)
	var distance := clampf(severity * -3.0 + rng.randfn(0.0, 0.8), -7.0, 3.0)
	development.record_execution(shot_type, score, lateral, distance, persistent_score)

func _emit_year(config: Dictionary, golfer, development, age: int, rounds: int, annual_shots: int, cumulative_shots: int, career_form: float) -> void:
	var states: Dictionary = {}
	var technical_sum := 0.0
	for shot_type in SHOT_TYPES:
		var state: Dictionary = development.development_state(shot_type)
		states[shot_type] = state
		technical_sum += float(state["effective_skill"])
	var technical_composite := technical_sum / float(SHOT_TYPES.size())
	var physical_capacity: float = (float(golfer.physical_power) + float(golfer.mobility) + float(golfer.coordination) + float(golfer.endurance)) / 4.0
	var driver_carry := _effective_driver_carry(golfer, float(states[0]["effective_skill"]))
	var normalized_carry := clampf(driver_carry / 70.0 * 50.0, 0.0, 100.0)
	var performance_index: float = float(technical_composite) * 0.72 + float(normalized_carry) * 0.20 + float(golfer.endurance) * 0.08
	var mean_aptitude := _dict_mean(config["aptitude"])
	var mean_potential := _dict_mean(config["potential"])
	output_rows.append("%s,%s,%d,%d,%d,%d,%d,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f" % [
		str(config["id"]), str(config["label"]), int(config["seed"]), age, rounds, annual_shots, cumulative_shots,
		career_form, physical_capacity, driver_carry, technical_composite, performance_index,
		float(states[0]["effective_skill"]), float(states[1]["effective_skill"]), float(states[2]["effective_skill"]), float(states[3]["effective_skill"]),
		mean_aptitude, mean_potential
	])

func _dict_mean(values: Dictionary) -> float:
	var total := 0.0
	for shot_type in SHOT_TYPES:
		total += float(values[shot_type])
	return total / float(SHOT_TYPES.size())

func _effective_driver_carry(golfer, effective_driving_skill: float) -> float:
	var base_carry := 70.0
	var strike_factor := lerpf(0.94, 1.04, clampf(effective_driving_skill, 0.0, 100.0) / 100.0)
	return base_carry * strike_factor * golfer.physical_distance_factor(0)

func _write_output() -> void:
	var output = FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if output == null:
		push_error("Could not write POC-09 stochastic career CSV: %s" % OUTPUT_PATH)
		quit(1)
		return
	for row in output_rows:
		output.store_line(row)
	output.close()
	print("Wrote POC-09 stochastic career CSV: %s" % OUTPUT_PATH)
