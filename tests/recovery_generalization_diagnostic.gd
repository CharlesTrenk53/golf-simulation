extends SceneTree

const TechniqueSkillDevelopment = preload("res://simulation/technique_skill_development.gd")
const QuietGolfer = preload("res://tests/quiet_golfer.gd")

const SHOT_TYPE := 0
const DRIVER_SHOTS_PER_ROUND := 12
const SHOTS_PER_SEASON := 1200
const EXECUTION_SD := 12.0
const RECOVERY_MEAN := 72.0
const MAX_RECOVERY_SHOTS := 3600
const REPLICATES := 3

var rng := RandomNumberGenerator.new()

var start_skills := [30.0, 50.0, 70.0, 90.0]
var experience_levels := [100, 8000]
var slump_levels := [
	{"name": "MILD", "mean": 56.0},
	{"name": "MODERATE", "mean": 50.0},
	{"name": "SEVERE", "mean": 42.0}
]
var slump_durations := [
	{"name": "SHORT", "shots": 300},
	{"name": "ONE_SEASON", "shots": 1200},
	{"name": "TWO_SEASON", "shots": 2400}
]

func _init() -> void:
	print("GENERALIZATIONCSV,start_skill,prior_experience,slump_severity,slump_duration,replicate,slump_target_mean,slump_realized_mean,slump_shots,slump_rounds,post_slump_skill,skill_loss,pct_loss,recovery_target_mean,recovery_50_shots,recovery_90_shots,recovery_baseline_shots,skill_after_1200_recovery,skill_after_2400_recovery,skill_after_3600_recovery,max_recovery_skill,overshoot")

	var scenario_index := 0
	for start_skill in start_skills:
		for prior_experience in experience_levels:
			for slump_level in slump_levels:
				for duration in slump_durations:
					for replicate in range(1, REPLICATES + 1):
						scenario_index += 1
						_run_scenario(start_skill, prior_experience, String(slump_level["name"]), float(slump_level["mean"]), String(duration["name"]), int(duration["shots"]), replicate, 50000 + scenario_index * 17)

	print("POC-08 RECOVERY GENERALIZATION DIAGNOSTIC COMPLETE")
	quit(0)

func _run_scenario(start_skill: float, prior_experience: int, severity_name: String, slump_mean: float, duration_name: String, slump_shots: int, replicate: int, seed_value: int) -> void:
	var golfer = _golfer(start_skill, prior_experience)
	var model = TechniqueSkillDevelopment.new()
	model.initialize_from_golfer(golfer)
	rng.seed = seed_value

	var slump_sum: float = 0.0
	for _shot in range(slump_shots):
		var score: float = _sample_execution(slump_mean)
		slump_sum += score
		_record(model, score)

	var post_slump_state: Dictionary = model.development_state(SHOT_TYPE)
	var baseline: float = float(post_slump_state["baseline_skill"])
	var post_slump_skill: float = float(post_slump_state["effective_skill"])
	var skill_loss: float = max(0.0, baseline - post_slump_skill)
	var pct_loss: float = 0.0 if baseline <= 0.001 else skill_loss / baseline * 100.0
	var target_50: float = post_slump_skill + skill_loss * 0.50
	var target_90: float = post_slump_skill + skill_loss * 0.90

	var recovery_50: int = -1
	var recovery_90: int = -1
	var recovery_baseline: int = -1
	var skill_after_1200: float = post_slump_skill
	var skill_after_2400: float = post_slump_skill
	var skill_after_3600: float = post_slump_skill
	var max_recovery_skill: float = post_slump_skill

	for recovery_shot in range(1, MAX_RECOVERY_SHOTS + 1):
		var score: float = _sample_execution(RECOVERY_MEAN)
		_record(model, score)
		var state: Dictionary = model.development_state(SHOT_TYPE)
		var current_skill: float = float(state["effective_skill"])
		max_recovery_skill = max(max_recovery_skill, current_skill)

		if skill_loss > 0.0001:
			if recovery_50 < 0 and current_skill >= target_50:
				recovery_50 = recovery_shot
			if recovery_90 < 0 and current_skill >= target_90:
				recovery_90 = recovery_shot
			if recovery_baseline < 0 and current_skill >= baseline:
				recovery_baseline = recovery_shot
		else:
			recovery_50 = 0
			recovery_90 = 0
			recovery_baseline = 0

		if recovery_shot == 1200:
			skill_after_1200 = current_skill
		elif recovery_shot == 2400:
			skill_after_2400 = current_skill
		elif recovery_shot == 3600:
			skill_after_3600 = current_skill

	var overshoot: float = max(0.0, max_recovery_skill - baseline)
	var realized_slump_mean: float = slump_sum / float(slump_shots)
	print("GENERALIZATIONCSV,%.1f,%d,%s,%s,%d,%.3f,%.3f,%d,%.1f,%.6f,%.6f,%.6f,%.3f,%d,%d,%d,%.6f,%.6f,%.6f,%.6f,%.6f" % [baseline, int(post_slump_state["prior_experience"]), severity_name, duration_name, replicate, slump_mean, realized_slump_mean, slump_shots, float(slump_shots) / float(DRIVER_SHOTS_PER_ROUND), post_slump_skill, skill_loss, pct_loss, RECOVERY_MEAN, recovery_50, recovery_90, recovery_baseline, skill_after_1200, skill_after_2400, skill_after_3600, max_recovery_skill, overshoot])
	golfer.free()

func _golfer(start_skill: float, prior_driver_experience: int):
	var golfer = QuietGolfer.new()
	golfer.profile = 2
	golfer.apply_profile()
	golfer.golfer_name = "Generalization Golfer"
	golfer.driving = start_skill
	golfer.career_shot_experience[SHOT_TYPE] = prior_driver_experience
	return golfer

func _sample_execution(mean: float) -> float:
	return clamp(rng.randfn(mean, EXECUTION_SD), 0.0, 100.0)

func _record(model, score: float) -> void:
	var severity: float = (62.0 - score) / 37.0
	var lateral: float = clamp(severity * 4.0 + rng.randfn(0.0, 1.2), -4.0, 8.0)
	var distance: float = clamp(severity * -3.0 + rng.randfn(0.0, 0.8), -7.0, 3.0)
	model.record_execution(SHOT_TYPE, score, lateral, distance)
