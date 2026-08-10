extends SceneTree

const GolfActivity = preload("res://simulation/golf_activity.gd")
const DevelopmentEvidenceBridge = preload("res://simulation/development_evidence_bridge.gd")
const TechniqueSkillDevelopment = preload("res://simulation/technique_skill_development.gd")
const GolferLifecycle = preload("res://simulation/golfer_lifecycle.gd")
const QuietGolfer = preload("res://tests/quiet_golfer.gd")

# POC-10 golf-life career diagnostic
# ----------------------------------
# Replaces a generic exposure scalar with actual golf lifestyles: rounds, practice
# volume, practice focus, practice quality, career-stage changes, and inactivity.
# Aptitude, potential, age plasticity, experience, retention, and physical aging
# remain responsible for the durable golfer that emerges.

const START_AGE := 16
const END_AGE := 76
const SHOT_TYPES := [0, 1, 2, 3]
const OUTPUT_PATH := "res://poc10_golf_life_careers.csv"
const PLAY_EXECUTION_BASE := 67.0
const PRACTICE_EXECUTION_BASE := 69.0
const FORM_PERSISTENCE := 0.70
const FORM_INNOVATION_SD := 1.8

const ARCHETYPES := [
	{
		"id": "heavy_practice_junior", "label": "Heavy-Practice Junior", "seed": 101001,
		"skills": {0: 43.0, 1: 42.0, 2: 41.0, 3: 42.0},
		"aptitude": {0: 1.15, 1: 1.18, 2: 1.12, 3: 1.10},
		"potential": {0: 77.0, 1: 79.0, 2: 78.0, 3: 76.0},
		"physical": [72.0, 74.0, 76.0, 73.0]
	},
	{
		"id": "competitive", "label": "High-Volume Competitor", "seed": 101002,
		"skills": {0: 47.0, 1: 47.0, 2: 46.0, 3: 47.0},
		"aptitude": {0: 1.04, 1: 1.06, 2: 1.04, 3: 1.02},
		"potential": {0: 75.0, 1: 77.0, 2: 76.0, 3: 75.0},
		"physical": [74.0, 75.0, 76.0, 76.0]
	},
	{
		"id": "talented_low_practice", "label": "Talented Low-Practice Golfer", "seed": 101003,
		"skills": {0: 50.0, 1: 49.0, 2: 48.0, 3: 49.0},
		"aptitude": {0: 1.24, 1: 1.22, 2: 1.20, 3: 1.18},
		"potential": {0: 84.0, 1: 85.0, 2: 83.0, 3: 82.0},
		"physical": [76.0, 75.0, 78.0, 70.0]
	},
	{
		"id": "grinder", "label": "Grinder", "seed": 101004,
		"skills": {0: 42.0, 1: 42.0, 2: 41.0, 3: 42.0},
		"aptitude": {0: 0.96, 1: 0.98, 2: 1.00, 3: 0.96},
		"potential": {0: 70.0, 1: 73.0, 2: 74.0, 3: 71.0},
		"physical": [70.0, 73.0, 74.0, 76.0]
	},
	{
		"id": "weekend_club", "label": "Weekend Club Golfer", "seed": 101005,
		"skills": {0: 39.0, 1: 40.0, 2: 40.0, 3: 42.0},
		"aptitude": {0: 0.95, 1: 0.95, 2: 1.00, 3: 0.96},
		"potential": {0: 62.0, 1: 64.0, 2: 66.0, 3: 65.0},
		"physical": [65.0, 68.0, 70.0, 67.0]
	},
	{
		"id": "late_bloomer", "label": "Late Bloomer", "seed": 101006,
		"skills": {0: 39.0, 1: 39.0, 2: 38.0, 3: 40.0},
		"aptitude": {0: 0.92, 1: 0.94, 2: 0.96, 3: 0.92},
		"potential": {0: 80.0, 1: 82.0, 2: 82.0, 3: 79.0},
		"physical": [68.0, 71.0, 72.0, 70.0]
	},
	{
		"id": "former_competitor", "label": "Former Competitor", "seed": 101007,
		"skills": {0: 48.0, 1: 48.0, 2: 47.0, 3: 48.0},
		"aptitude": {0: 1.05, 1: 1.06, 2: 1.04, 3: 1.02},
		"potential": {0: 76.0, 1: 78.0, 2: 77.0, 3: 76.0},
		"physical": [74.0, 75.0, 77.0, 75.0]
	}
]

var rng := RandomNumberGenerator.new()
var rows: Array[String] = []

func _init() -> void:
	rows.append("id,label,age,rounds,practice_reps,practice_quality,cumulative_rounds,cumulative_practice,total_activity,technical_composite,drive_skill,approach_skill,short_game_skill,putt_skill,physical_capacity,form")
	for config in ARCHETYPES:
		_run_career(config)
	_write_output()
	print("POC-10 GOLF-LIFE CAREER DIAGNOSTIC COMPLETE")
	quit(0)

func _run_career(config: Dictionary) -> void:
	var golfer = _create_golfer(config)
	var development = TechniqueSkillDevelopment.new()
	development.initialize_from_golfer(golfer)
	var lifecycle = GolferLifecycle.new()
	var activity = GolfActivity.new()
	var bridge = DevelopmentEvidenceBridge.new()
	rng.seed = int(config["seed"])
	var career_form := 0.0

	for age in range(START_AGE, END_AGE + 1):
		golfer.age = age
		development.set_current_age(age)
		career_form = FORM_PERSISTENCE * career_form + rng.randfn(0.0, FORM_INNOVATION_SD)
		var lifestyle := _lifestyle_for(str(config["id"]), age)
		var round_factor := clampf(rng.randfn(1.0, 0.08), 0.78, 1.22)
		var practice_factor := clampf(rng.randfn(1.0, 0.10), 0.70, 1.30)
		var rounds := maxi(0, int(round(float(lifestyle["rounds"]) * round_factor)))
		var practice_reps := maxi(0, int(round(float(lifestyle["practice_reps"]) * practice_factor)))
		var quality := clampf(float(lifestyle["quality"]), 0.0, 1.0)
		var focus: Dictionary = lifestyle["focus"]

		var play_result := activity.record_rounds(rounds)
		for shot_type in SHOT_TYPES:
			var play_reps := int(play_result["on_course_exposure"][shot_type])
			var play_score := clampf(PLAY_EXECUTION_BASE + career_form + _physical_modifier(golfer, shot_type), 0.0, 100.0)
			var persistent_play := clampf(play_score - career_form * 0.80, 0.0, 100.0)
			bridge.apply_play_exposure(development, shot_type, play_reps, play_score, 0.0, 0.0, persistent_play)

		if practice_reps > 0:
			var practice_result := activity.record_practice(practice_reps, focus, quality)
			for shot_type in SHOT_TYPES:
				var reps := int(practice_result["practice_repetitions"][shot_type])
				if reps <= 0:
					continue
				var practice_score := clampf(PRACTICE_EXECUTION_BASE + _physical_modifier(golfer, shot_type), 0.0, 100.0)
				bridge.apply_practice_exposure(development, shot_type, reps, quality, practice_score, 0.0, 0.0, practice_score)

		_emit_year(config, golfer, development, activity, age, rounds, practice_reps, quality, career_form)
		if age < END_AGE:
			development.advance_year()
			lifecycle.advance_year(golfer)
	golfer.free()

func _lifestyle_for(id: String, age: int) -> Dictionary:
	var rounds := 30
	var practice_reps := 800
	var quality := 0.55
	var focus := {0: 0.25, 1: 0.30, 2: 0.25, 3: 0.20}

	match id:
		"heavy_practice_junior":
			if age <= 18:
				rounds = 65; practice_reps = 7000; quality = 0.82
			elif age <= 24:
				rounds = 85; practice_reps = 6000; quality = 0.85
			elif age <= 35:
				rounds = 65; practice_reps = 3200; quality = 0.78
			elif age <= 55:
				rounds = 45; practice_reps = 1600; quality = 0.68
			else:
				rounds = 30; practice_reps = 700; quality = 0.58
			focus = {0: 0.25, 1: 0.32, 2: 0.25, 3: 0.18}
		"competitive":
			if age <= 22:
				rounds = 95; practice_reps = 5000; quality = 0.82
			elif age <= 40:
				rounds = 110; practice_reps = 4500; quality = 0.84
			elif age <= 55:
				rounds = 80; practice_reps = 2800; quality = 0.76
			else:
				rounds = 50; practice_reps = 1200; quality = 0.64
			focus = {0: 0.24, 1: 0.31, 2: 0.25, 3: 0.20}
		"talented_low_practice":
			if age <= 25:
				rounds = 55; practice_reps = 900; quality = 0.68
			elif age <= 50:
				rounds = 45; practice_reps = 650; quality = 0.62
			else:
				rounds = 30; practice_reps = 350; quality = 0.55
		"grinder":
			if age <= 25:
				rounds = 75; practice_reps = 6500; quality = 0.72
			elif age <= 50:
				rounds = 85; practice_reps = 6000; quality = 0.74
			elif age <= 65:
				rounds = 65; practice_reps = 3500; quality = 0.68
			else:
				rounds = 40; practice_reps = 1400; quality = 0.58
			focus = {0: 0.20, 1: 0.32, 2: 0.30, 3: 0.18}
		"weekend_club":
			if age <= 22:
				rounds = 20; practice_reps = 250; quality = 0.48
			elif age <= 60:
				rounds = 35; practice_reps = 300; quality = 0.50
			else:
				rounds = 25; practice_reps = 150; quality = 0.45
		"late_bloomer":
			if age <= 24:
				rounds = 10; practice_reps = 100; quality = 0.42
			elif age <= 29:
				rounds = 18; practice_reps = 250; quality = 0.48
			elif age <= 40:
				rounds = 75; practice_reps = 5200; quality = 0.80
			elif age <= 50:
				rounds = 70; practice_reps = 4200; quality = 0.76
			elif age <= 65:
				rounds = 55; practice_reps = 2200; quality = 0.68
			else:
				rounds = 35; practice_reps = 800; quality = 0.56
			focus = {0: 0.22, 1: 0.32, 2: 0.28, 3: 0.18}
		"former_competitor":
			if age <= 24:
				rounds = 100; practice_reps = 5200; quality = 0.83
			elif age <= 40:
				rounds = 105; practice_reps = 4300; quality = 0.82
			elif age <= 45:
				rounds = 55; practice_reps = 1500; quality = 0.65
			elif age <= 60:
				rounds = 8; practice_reps = 100; quality = 0.45
			else:
				rounds = 18; practice_reps = 250; quality = 0.50
			focus = {0: 0.24, 1: 0.31, 2: 0.25, 3: 0.20}

	return {"rounds": rounds, "practice_reps": practice_reps, "quality": quality, "focus": focus}

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
	golfer.career_shot_experience = {0: 400, 1: 600, 2: 450, 3: 700}
	golfer.skill_learning_rates = config["aptitude"].duplicate(true)
	golfer.skill_potentials = config["potential"].duplicate(true)
	return golfer

func _physical_modifier(golfer, shot_type: int) -> float:
	var factor := float(golfer.physical_distance_factor(shot_type))
	var sensitivity := 0.0
	match shot_type:
		0: sensitivity = 1.5
		1: sensitivity = 0.8
		2: sensitivity = 0.25
		3: sensitivity = 0.05
	return (factor - 1.0) * sensitivity

func _emit_year(config: Dictionary, golfer, development, activity, age: int, rounds: int, practice_reps: int, quality: float, career_form: float) -> void:
	var technical_sum := 0.0
	var states: Dictionary = {}
	for shot_type in SHOT_TYPES:
		var state: Dictionary = development.development_state(shot_type)
		states[shot_type] = state
		technical_sum += float(state["effective_skill"])
	var technical_composite := technical_sum / 4.0
	var physical_capacity := (float(golfer.physical_power) + float(golfer.mobility) + float(golfer.coordination) + float(golfer.endurance)) / 4.0
	rows.append("%s,%s,%d,%d,%d,%.3f,%d,%d,%d,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f" % [
		str(config["id"]), str(config["label"]), age, rounds, practice_reps, quality,
		int(activity.career_rounds_played), int(activity.total_practice_repetitions()), int(activity.total_activity_repetitions()),
		technical_composite,
		float(states[0]["effective_skill"]), float(states[1]["effective_skill"]), float(states[2]["effective_skill"]), float(states[3]["effective_skill"]),
		physical_capacity, career_form
	])

func _write_output() -> void:
	var output = FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if output == null:
		push_error("Could not write POC-10 golf-life career CSV: %s" % OUTPUT_PATH)
		quit(1)
		return
	for row in rows:
		output.store_line(row)
	output.close()
	print("Wrote POC-10 golf-life career CSV: ", OUTPUT_PATH)
