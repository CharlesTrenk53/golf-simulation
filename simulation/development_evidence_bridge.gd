extends RefCounted

# Development Evidence Bridge
# ---------------------------
# Connects activity-derived opportunity to TechniqueSkillDevelopment without
# awarding skill directly. All raw repetitions contribute experience. Only the
# useful-evidence share reaches record_execution(), where aptitude, potential,
# age plasticity, experience resistance, and the existing learning model decide
# whether durable skill changes.

func apply_play_exposure(development, shot_type: int, repetitions: int, execution_score: float, lateral_error: float = 0.0, distance_error: float = 0.0, persistent_execution_score: float = -1.0) -> Dictionary:
	var reps := maxi(repetitions, 0)
	for _i in range(reps):
		development.record_execution(shot_type, execution_score, lateral_error, distance_error, persistent_execution_score)
	return {
		"raw_repetitions": reps,
		"evidence_repetitions": reps,
		"experience_only_repetitions": 0
	}

func apply_practice_exposure(development, shot_type: int, repetitions: int, quality: float, execution_score: float, lateral_error: float = 0.0, distance_error: float = 0.0, persistent_execution_score: float = -1.0) -> Dictionary:
	var reps := maxi(repetitions, 0)
	var resolved_quality := clampf(quality, 0.0, 1.0)
	# Deterministic evidence accounting avoids adding stochastic noise at this
	# architectural stage. Fractional opportunity is rounded to the nearest whole
	# evidence event, while every repetition still counts as experience.
	var evidence_reps := clampi(int(round(float(reps) * resolved_quality)), 0, reps)
	var experience_only := reps - evidence_reps
	for _i in range(evidence_reps):
		development.record_execution(shot_type, execution_score, lateral_error, distance_error, persistent_execution_score)
	if experience_only > 0:
		development.record_experience_only(shot_type, experience_only)
	return {
		"raw_repetitions": reps,
		"quality": resolved_quality,
		"evidence_repetitions": evidence_reps,
		"experience_only_repetitions": experience_only
	}
