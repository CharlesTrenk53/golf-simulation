extends SceneTree

const TechniqueSkillDevelopment = preload("res://simulation/technique_skill_development.gd")
const QuietGolfer = preload("res://tests/quiet_golfer.gd")

const DRIVE := 0
const APPROACH := 1
const SHORT_GAME := 2
const PUTT := 3
const START_SKILL := 50.0
const PRIOR_EXPERIENCE := 500
const SEASONS := 20
const ROUNDS_PER_SEASON := 100
const EXECUTION_MEAN := 70.0
const EXECUTION_SD := 12.0

const SHOTS_PER_ROUND := {
	DRIVE: 12,
	APPROACH: 18,
	SHORT_GAME: 9,
	PUTT: 30
}

var profiles := [
	{
		"name": "BALANCED",
		"rates": {DRIVE: 1.00, APPROACH: 1.00, SHORT_GAME: 1.00, PUTT: 1.00}
	},
	{
		"name": "BALL_STRIKER",
		"rates": {DRIVE: 1.35, APPROACH: 1.30, SHORT_GAME: 0.85, PUTT: 0.80}
	},
	{
		"name": "TOUCH_SPECIALIST",
		"rates": {DRIVE: 0.80, APPROACH: 0.90, SHORT_GAME: 1.35, PUTT: 1.40}
	},
	{
		"name": "UNEVEN_DEVELOPER",
		"rates": {DRIVE: 1.45, APPROACH: 0.75, SHORT_GAME: 1.20, PUTT: 0.70}
	}
]

func _init() -> void:
	print("PROFILECSV,profile,season,rounds,drive_shots,approach_shots,short_game_shots,putt_shots,drive_aptitude,approach_aptitude,short_game_aptitude,putt_aptitude,drive_skill,approach_skill,short_game_skill,putt_skill,drive_pct_change,approach_pct_change,short_game_pct_change,putt_pct_change,skill_spread")
	for profile_data in profiles:
		_run_profile(profile_data)
	print("POC-08 LEARNING PROFILE CAREER DIAGNOSTIC COMPLETE")
	quit(0)

func _run_profile(profile_data: Dictionary) -> void:
	var golfer = _golfer(profile_data["rates"])
	var model = TechniqueSkillDevelopment.new()
	model.initialize_from_golfer(golfer)
	var rng := RandomNumberGenerator.new()
	# Every profile receives the exact same stochastic execution sequence.
	rng.seed = 8675309

	_print_state(String(profile_data["name"]), 0, model, profile_data["rates"])
	for season in range(1, SEASONS + 1):
		for _round in range(ROUNDS_PER_SEASON):
			for shot_type in [DRIVE, APPROACH, SHORT_GAME, PUTT]:
				for _shot in range(int(SHOTS_PER_ROUND[shot_type])):
					var score: float = clamp(rng.randfn(EXECUTION_MEAN, EXECUTION_SD), 0.0, 100.0)
					var severity: float = (62.0 - score) / 38.0
					var lateral: float = clamp(severity * 3.0 + rng.randfn(0.0, 1.0), -4.0, 7.0)
					var distance: float = clamp(severity * -2.5 + rng.randfn(0.0, 0.7), -6.0, 3.0)
					model.record_execution(shot_type, score, lateral, distance)
		_print_state(String(profile_data["name"]), season, model, profile_data["rates"])
	golfer.free()

func _print_state(profile_name: String, season: int, model, rates: Dictionary) -> void:
	var drive_state: Dictionary = model.development_state(DRIVE)
	var approach_state: Dictionary = model.development_state(APPROACH)
	var short_state: Dictionary = model.development_state(SHORT_GAME)
	var putt_state: Dictionary = model.development_state(PUTT)
	var drive_skill: float = float(drive_state["effective_skill"])
	var approach_skill: float = float(approach_state["effective_skill"])
	var short_skill: float = float(short_state["effective_skill"])
	var putt_skill: float = float(putt_state["effective_skill"])
	var max_skill: float = max(max(drive_skill, approach_skill), max(short_skill, putt_skill))
	var min_skill: float = min(min(drive_skill, approach_skill), min(short_skill, putt_skill))
	print("PROFILECSV,%s,%d,%d,%d,%d,%d,%d,%.2f,%.2f,%.2f,%.2f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f" % [
		profile_name,
		season,
		season * ROUNDS_PER_SEASON,
		season * ROUNDS_PER_SEASON * int(SHOTS_PER_ROUND[DRIVE]),
		season * ROUNDS_PER_SEASON * int(SHOTS_PER_ROUND[APPROACH]),
		season * ROUNDS_PER_SEASON * int(SHOTS_PER_ROUND[SHORT_GAME]),
		season * ROUNDS_PER_SEASON * int(SHOTS_PER_ROUND[PUTT]),
		float(rates[DRIVE]),
		float(rates[APPROACH]),
		float(rates[SHORT_GAME]),
		float(rates[PUTT]),
		drive_skill,
		approach_skill,
		short_skill,
		putt_skill,
		(drive_skill - START_SKILL) / START_SKILL * 100.0,
		(approach_skill - START_SKILL) / START_SKILL * 100.0,
		(short_skill - START_SKILL) / START_SKILL * 100.0,
		(putt_skill - START_SKILL) / START_SKILL * 100.0,
		max_skill - min_skill
	])

func _golfer(rates: Dictionary):
	var golfer = QuietGolfer.new()
	golfer.profile = 2
	golfer.apply_profile()
	golfer.golfer_name = "Learning Profile Golfer"
	golfer.driving = START_SKILL
	golfer.approach = START_SKILL
	golfer.short_game = START_SKILL
	golfer.putting = START_SKILL
	golfer.career_shot_experience = {
		DRIVE: PRIOR_EXPERIENCE,
		APPROACH: PRIOR_EXPERIENCE,
		SHORT_GAME: PRIOR_EXPERIENCE,
		PUTT: PRIOR_EXPERIENCE
	}
	golfer.skill_learning_rates = rates.duplicate(true)
	return golfer
