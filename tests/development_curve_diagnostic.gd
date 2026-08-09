extends SceneTree

const TechniqueSkillDevelopment = preload("res://simulation/technique_skill_development.gd")
const QuietGolfer = preload("res://tests/quiet_golfer.gd")

const SHOT_TYPE := 0
const MAX_SHOTS := 25000
const CHECKPOINT := 500
const STRESS_SHOTS := 100000
const STRESS_CHECKPOINT := 5000

func _init() -> void:
	print("scenario,profile,prior_experience,shots,baseline_skill,effective_skill,skill_delta,pct_change,stability,resistance,avg_execution")

	# Controlled novice/veteran comparison across execution-quality bands. These
	# identify the practical neutral zone and the rates of slow decline/improvement.
	for score in [25.0, 50.0, 62.0, 75.0, 90.0]:
		var suffix = _score_label(score)
		_run_constant_scenario("NOVICE_%s" % suffix, 2, 100, score, MAX_SHOTS, CHECKPOINT)
		_run_constant_scenario("VETERAN_%s" % suffix, 2, 8000, score, MAX_SHOTS, CHECKPOINT)

	# Long slump followed by sustained excellent execution. This tests restoration
	# to baseline, transition into genuinely new learning, and veteran self-correction.
	_run_recovery_scenario("NOVICE_SLUMP_RECOVERY", 2, 100, 5000, 25.0, 90.0, MAX_SHOTS, CHECKPOINT)
	_run_recovery_scenario("VETERAN_SLUMP_RECOVERY", 2, 8000, 5000, 25.0, 90.0, MAX_SHOTS, CHECKPOINT)

	# Current golfer profiles under identical sustained poor Driver execution.
	_run_profile_scenario("BILL_POOR", 0, 25.0, MAX_SHOTS, CHECKPOINT)
	_run_profile_scenario("RICK_POOR", 1, 25.0, MAX_SHOTS, CHECKPOINT)
	_run_profile_scenario("CARL_POOR", 2, 25.0, MAX_SHOTS, CHECKPOINT)

	# Extreme stress tests are intentionally sparse. Their purpose is not realism;
	# they expose hidden late-stage instability, runaway drift, or hard-code plateaus.
	_run_constant_scenario("STRESS_NOVICE_POOR", 2, 100, 25.0, STRESS_SHOTS, STRESS_CHECKPOINT)
	_run_constant_scenario("STRESS_VETERAN_POOR", 2, 8000, 25.0, STRESS_SHOTS, STRESS_CHECKPOINT)
	_run_constant_scenario("STRESS_NOVICE_EXCELLENT", 2, 100, 90.0, STRESS_SHOTS, STRESS_CHECKPOINT)
	_run_constant_scenario("STRESS_VETERAN_EXCELLENT", 2, 8000, 90.0, STRESS_SHOTS, STRESS_CHECKPOINT)

	print("POC-08 DEVELOPMENT CURVE DIAGNOSTIC COMPLETE")
	quit(0)

func _run_constant_scenario(label: String, profile: int, prior_driver_experience: int, execution_score: float, max_shots: int, checkpoint: int) -> void:
	var golfer = _golfer(profile, prior_driver_experience)
	var model = TechniqueSkillDevelopment.new()
	model.initialize_from_golfer(golfer)
	_emit(label, golfer, model, 0)
	for shot in range(1, max_shots + 1):
		model.record_execution(SHOT_TYPE, execution_score, _lateral_for(execution_score), _distance_for(execution_score))
		if shot % checkpoint == 0:
			_emit(label, golfer, model, shot)
	golfer.free()

func _run_recovery_scenario(label: String, profile: int, prior_driver_experience: int, slump_shots: int, poor_score: float, recovery_score: float, max_shots: int, checkpoint: int) -> void:
	var golfer = _golfer(profile, prior_driver_experience)
	var model = TechniqueSkillDevelopment.new()
	model.initialize_from_golfer(golfer)
	_emit(label, golfer, model, 0)
	for shot in range(1, max_shots + 1):
		var score = poor_score if shot <= slump_shots else recovery_score
		model.record_execution(SHOT_TYPE, score, _lateral_for(score), _distance_for(score))
		if shot % checkpoint == 0:
			_emit(label, golfer, model, shot)
	golfer.free()

func _run_profile_scenario(label: String, profile: int, execution_score: float, max_shots: int, checkpoint: int) -> void:
	var golfer = QuietGolfer.new()
	golfer.profile = profile
	golfer.apply_profile()
	var model = TechniqueSkillDevelopment.new()
	model.initialize_from_golfer(golfer)
	_emit(label, golfer, model, 0)
	for shot in range(1, max_shots + 1):
		model.record_execution(SHOT_TYPE, execution_score, _lateral_for(execution_score), _distance_for(execution_score))
		if shot % checkpoint == 0:
			_emit(label, golfer, model, shot)
	golfer.free()

func _golfer(profile: int, prior_driver_experience: int):
	var golfer = QuietGolfer.new()
	golfer.profile = profile
	golfer.apply_profile()
	golfer.career_shot_experience[SHOT_TYPE] = prior_driver_experience
	return golfer

func _emit(label: String, golfer, model, shots: int) -> void:
	var state: Dictionary = model.development_state(SHOT_TYPE)
	var baseline = float(state["baseline_skill"])
	var effective = float(state["effective_skill"])
	var delta = float(state["skill_delta"])
	var pct_change = 0.0 if abs(baseline) < 0.001 else (delta / baseline) * 100.0
	print("DEVCSV,%s,%s,%d,%d,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f" % [
		label,
		golfer.golfer_name,
		int(state["prior_experience"]),
		shots,
		baseline,
		effective,
		delta,
		pct_change,
		float(state["experience_stability"]),
		float(state.get("development_resistance", 1.0)),
		float(state["average_execution_quality"])
	])

func _score_label(score: float) -> String:
	if score <= 30.0:
		return "POOR"
	if score < 62.0:
		return "MILD_POOR"
	if is_equal_approx(score, 62.0):
		return "NEUTRAL"
	if score < 85.0:
		return "GOOD"
	return "EXCELLENT"

func _lateral_for(execution_score: float) -> float:
	if execution_score < 40.0:
		return 7.0
	if execution_score < 62.0:
		return 3.0
	if execution_score < 85.0:
		return 1.0
	return 0.5

func _distance_for(execution_score: float) -> float:
	if execution_score < 40.0:
		return -6.0
	if execution_score < 62.0:
		return -2.5
	if execution_score < 85.0:
		return -0.5
	return 0.25
