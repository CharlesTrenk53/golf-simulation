extends SceneTree

const TechniqueSkillDevelopment = preload("res://simulation/technique_skill_development.gd")
const QuietGolfer = preload("res://tests/quiet_golfer.gd")

const SHOT_TYPE := 0
const MAX_SHOTS := 2000
const CHECKPOINT := 100

func _init() -> void:
	print("scenario,profile,prior_experience,shots,baseline_skill,effective_skill,skill_delta,pct_change,stability,avg_execution")

	# Controlled novice/veteran comparison: identical golfer ability, only prior
	# Driver experience differs. This isolates the stability/self-correction rule.
	_run_constant_scenario("NOVICE_POOR", 2, 100, 25.0)
	_run_constant_scenario("VETERAN_POOR", 2, 8000, 25.0)
	_run_constant_scenario("NOVICE_GOOD", 2, 100, 90.0)
	_run_constant_scenario("VETERAN_GOOD", 2, 8000, 90.0)
	_run_recovery_scenario("NOVICE_SLUMP_RECOVERY", 2, 100, 800, 25.0, 90.0)
	_run_recovery_scenario("VETERAN_SLUMP_RECOVERY", 2, 8000, 800, 25.0, 90.0)

	# Current golfer profiles under the same sustained poor Driver execution.
	# This checks the actual experience anchors assigned to Bill, Rick and Carl.
	_run_profile_scenario("BILL_POOR", 0, 25.0)
	_run_profile_scenario("RICK_POOR", 1, 25.0)
	_run_profile_scenario("CARL_POOR", 2, 25.0)

	print("POC-08 DEVELOPMENT CURVE DIAGNOSTIC COMPLETE")
	quit(0)

func _run_constant_scenario(label: String, profile: int, prior_driver_experience: int, execution_score: float) -> void:
	var golfer = _golfer(profile, prior_driver_experience)
	var model = TechniqueSkillDevelopment.new()
	model.initialize_from_golfer(golfer)
	_emit(label, golfer, model, 0, execution_score)
	for shot in range(1, MAX_SHOTS + 1):
		model.record_execution(SHOT_TYPE, execution_score, _lateral_for(execution_score), _distance_for(execution_score))
		if shot % CHECKPOINT == 0:
			_emit(label, golfer, model, shot, execution_score)
	golfer.free()

func _run_recovery_scenario(label: String, profile: int, prior_driver_experience: int, slump_shots: int, poor_score: float, recovery_score: float) -> void:
	var golfer = _golfer(profile, prior_driver_experience)
	var model = TechniqueSkillDevelopment.new()
	model.initialize_from_golfer(golfer)
	_emit(label, golfer, model, 0, poor_score)
	for shot in range(1, MAX_SHOTS + 1):
		var score = poor_score if shot <= slump_shots else recovery_score
		model.record_execution(SHOT_TYPE, score, _lateral_for(score), _distance_for(score))
		if shot % CHECKPOINT == 0:
			_emit(label, golfer, model, shot, score)
	golfer.free()

func _run_profile_scenario(label: String, profile: int, execution_score: float) -> void:
	var golfer = QuietGolfer.new()
	golfer.profile = profile
	golfer.apply_profile()
	var model = TechniqueSkillDevelopment.new()
	model.initialize_from_golfer(golfer)
	_emit(label, golfer, model, 0, execution_score)
	for shot in range(1, MAX_SHOTS + 1):
		model.record_execution(SHOT_TYPE, execution_score, _lateral_for(execution_score), _distance_for(execution_score))
		if shot % CHECKPOINT == 0:
			_emit(label, golfer, model, shot, execution_score)
	golfer.free()

func _golfer(profile: int, prior_driver_experience: int):
	var golfer = QuietGolfer.new()
	golfer.profile = profile
	golfer.apply_profile()
	golfer.career_shot_experience[SHOT_TYPE] = prior_driver_experience
	return golfer

func _emit(label: String, golfer, model, shots: int, current_execution: float) -> void:
	var state: Dictionary = model.development_state(SHOT_TYPE)
	var baseline = float(state["baseline_skill"])
	var effective = float(state["effective_skill"])
	var delta = float(state["skill_delta"])
	var pct_change = 0.0 if abs(baseline) < 0.001 else (delta / baseline) * 100.0
	print("DEVCSV,%s,%s,%d,%d,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f" % [
		label,
		golfer.golfer_name,
		int(state["prior_experience"]),
		shots,
		baseline,
		effective,
		delta,
		pct_change,
		float(state["experience_stability"]),
		float(state["average_execution_quality"])
	])

func _lateral_for(execution_score: float) -> float:
	return 7.0 if execution_score < 50.0 else 0.5

func _distance_for(execution_score: float) -> float:
	return -6.0 if execution_score < 50.0 else 0.25
