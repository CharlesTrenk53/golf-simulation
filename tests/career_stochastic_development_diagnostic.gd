extends SceneTree

const TechniqueSkillDevelopment = preload("res://simulation/technique_skill_development.gd")
const QuietGolfer = preload("res://tests/quiet_golfer.gd")

const SHOT_TYPE := 0
const ROUNDS_PER_SEASON := 100
const DRIVER_SHOTS_PER_ROUND := 12
const SHOTS_PER_SEASON := ROUNDS_PER_SEASON * DRIVER_SHOTS_PER_ROUND
const CAREER_SEASONS := 20
const EXECUTION_SD := 12.0

var rng := RandomNumberGenerator.new()

func _init() -> void:
	print("scenario,start_skill,prior_experience,season,rounds,shots,phase,target_mean,realized_mean,baseline_skill,effective_skill,skill_delta,pct_change,stability,resistance")

	# Stable stochastic bands. Individual shots vary; only the long-run center differs.
	for start_skill in [30.0, 50.0, 70.0, 90.0]:
		_run_steady("STEADY_NEUTRAL", start_skill, 100, 62.0, 11000 + int(start_skill))
		_run_steady("STEADY_GOOD", start_skill, 100, 70.0, 12000 + int(start_skill))
		_run_steady("STEADY_MILD_POOR", start_skill, 100, 54.0, 13000 + int(start_skill))

	# Same ability, different established experience, under an identical career arc.
	for prior_experience in [100, 8000]:
		_run_career_arc("CAREER_ARC", 70.0, prior_experience, 21000 + prior_experience)

	# Alternating half-season hot/cold periods test whether temporary form oscillation
	# produces controlled skill movement rather than ratcheting endlessly.
	_run_alternating("ALTERNATING_FORM", 70.0, 100, 31001)
	_run_alternating("ALTERNATING_FORM", 70.0, 8000, 31002)

	# Fine recovery trace after a meaningful 2-season slump. This is deliberately
	# sampled every 50 shots during the first 1,000 recovery swings because the prior
	# constant-score diagnostic suggested recovery may currently be too abrupt.
	_run_fine_recovery("FINE_RECOVERY", 70.0, 100, 41001)
	_run_fine_recovery("FINE_RECOVERY", 70.0, 8000, 41002)

	print("POC-08 STOCHASTIC CAREER DEVELOPMENT DIAGNOSTIC COMPLETE")
	quit(0)

func _run_steady(label: String, start_skill: float, prior_experience: int, target_mean: float, seed_value: int) -> void:
	var golfer = _golfer(start_skill, prior_experience)
	var model = TechniqueSkillDevelopment.new()
	model.initialize_from_golfer(golfer)
	rng.seed = seed_value
	_emit(label, golfer, model, 0, "BASELINE", target_mean, 0.0, 0)
	var cumulative_sum := 0.0
	var total_shots := 0
	for season in range(1, CAREER_SEASONS + 1):
		for _shot in range(SHOTS_PER_SEASON):
			var score = _sample_execution(target_mean, EXECUTION_SD)
			cumulative_sum += score
			total_shots += 1
			_record(model, score)
		_emit(label, golfer, model, season, "STEADY", target_mean, cumulative_sum / total_shots, total_shots)
	golfer.free()

func _run_career_arc(label: String, start_skill: float, prior_experience: int, seed_value: int) -> void:
	var golfer = _golfer(start_skill, prior_experience)
	var model = TechniqueSkillDevelopment.new()
	model.initialize_from_golfer(golfer)
	rng.seed = seed_value
	_emit(label, golfer, model, 0, "BASELINE", 62.0, 0.0, 0)
	var total_shots := 0
	for season in range(1, CAREER_SEASONS + 1):
		var phase = _career_phase(season)
		var target_mean = float(phase["mean"])
		var season_sum := 0.0
		for _shot in range(SHOTS_PER_SEASON):
			var score = _sample_execution(target_mean, EXECUTION_SD)
			season_sum += score
			total_shots += 1
			_record(model, score)
		_emit(label, golfer, model, season, String(phase["name"]), target_mean, season_sum / SHOTS_PER_SEASON, total_shots)
	golfer.free()

func _run_alternating(label: String, start_skill: float, prior_experience: int, seed_value: int) -> void:
	var golfer = _golfer(start_skill, prior_experience)
	var model = TechniqueSkillDevelopment.new()
	model.initialize_from_golfer(golfer)
	rng.seed = seed_value
	_emit(label, golfer, model, 0, "BASELINE", 62.0, 0.0, 0)
	var total_shots := 0
	for season in range(1, 11):
		var season_sum := 0.0
		for shot_in_season in range(SHOTS_PER_SEASON):
			var hot = shot_in_season >= SHOTS_PER_SEASON / 2
			var target_mean = 72.0 if hot else 52.0
			var score = _sample_execution(target_mean, EXECUTION_SD)
			season_sum += score
			total_shots += 1
			_record(model, score)
		_emit(label, golfer, model, season, "COLD_THEN_HOT", 62.0, season_sum / SHOTS_PER_SEASON, total_shots)
	golfer.free()

func _run_fine_recovery(label: String, start_skill: float, prior_experience: int, seed_value: int) -> void:
	var golfer = _golfer(start_skill, prior_experience)
	var model = TechniqueSkillDevelopment.new()
	model.initialize_from_golfer(golfer)
	rng.seed = seed_value
	_emit(label, golfer, model, 0, "BASELINE", 62.0, 0.0, 0)
	var total_shots := 0
	var slump_sum := 0.0
	for _shot in range(SHOTS_PER_SEASON * 2):
		var score = _sample_execution(50.0, EXECUTION_SD)
		slump_sum += score
		total_shots += 1
		_record(model, score)
	_emit(label, golfer, model, 2, "TWO_SEASON_SLUMP", 50.0, slump_sum / (SHOTS_PER_SEASON * 2), total_shots)

	var recovery_sum := 0.0
	for recovery_shot in range(1, 1001):
		var score = _sample_execution(72.0, EXECUTION_SD)
		recovery_sum += score
		total_shots += 1
		_record(model, score)
		if recovery_shot % 50 == 0:
			_emit(label, golfer, model, 2, "RECOVERY_%d" % recovery_shot, 72.0, recovery_sum / recovery_shot, total_shots)
	golfer.free()

func _career_phase(season: int) -> Dictionary:
	if season <= 4:
		return {"name": "FOUNDATION", "mean": 66.0}
	if season <= 7:
		return {"name": "IMPROVEMENT", "mean": 72.0}
	if season <= 9:
		return {"name": "SLUMP", "mean": 50.0}
	if season <= 12:
		return {"name": "RECOVERY", "mean": 70.0}
	if season <= 16:
		return {"name": "ESTABLISHED", "mean": 64.0}
	return {"name": "LATE_VARIABILITY", "mean": 60.0}

func _golfer(start_skill: float, prior_driver_experience: int):
	var golfer = QuietGolfer.new()
	golfer.profile = 2
	golfer.apply_profile()
	golfer.golfer_name = "Calibration Golfer"
	golfer.driving = start_skill
	golfer.career_shot_experience[SHOT_TYPE] = prior_driver_experience
	return golfer

func _sample_execution(mean: float, deviation: float) -> float:
	return clamp(rng.randfn(mean, deviation), 0.0, 100.0)

func _record(model, score: float) -> void:
	var severity = (62.0 - score) / 37.0
	var lateral = clamp(severity * 4.0 + rng.randfn(0.0, 1.2), -4.0, 8.0)
	var distance = clamp(severity * -3.0 + rng.randfn(0.0, 0.8), -7.0, 3.0)
	model.record_execution(SHOT_TYPE, score, lateral, distance)

func _emit(label: String, golfer, model, season: int, phase: String, target_mean: float, realized_mean: float, shots: int) -> void:
	var state: Dictionary = model.development_state(SHOT_TYPE)
	var baseline = float(state["baseline_skill"])
	var effective = float(state["effective_skill"])
	var delta = float(state["skill_delta"])
	var pct_change = 0.0 if abs(baseline) < 0.001 else delta / baseline * 100.0
	var rounds = float(shots) / float(DRIVER_SHOTS_PER_ROUND)
	print("CAREERCSV,%s,%.1f,%d,%d,%.1f,%d,%s,%.3f,%.3f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f" % [
		label,
		baseline,
		int(state["prior_experience"]),
		season,
		rounds,
		shots,
		phase,
		target_mean,
		realized_mean,
		baseline,
		effective,
		delta,
		pct_change,
		float(state["experience_stability"]),
		float(state.get("development_resistance", 1.0))
	])
