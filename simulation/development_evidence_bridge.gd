extends RefCounted

# Development Evidence Bridge
# ---------------------------
# Connects activity-derived opportunity to TechniqueSkillDevelopment without
# awarding skill directly. All raw repetitions contribute experience. Only the
# useful-evidence share reaches record_execution(), where aptitude, potential,
# age plasticity, experience resistance, and the existing learning model decide
# whether durable skill changes.
#
# Fractional practice opportunity is carried forward by shot family so evidence
# does not depend on arbitrary session/year batching. For example, 10,000 reps at
# quality 0.85 produce 8,500 evidence events whether delivered in five large
# blocks or forty smaller blocks.

const SHOT_TYPES := [0, 1, 2, 3]

var practice_evidence_remainder: Dictionary = {}

func _init() -> void:
	reset()

func reset() -> void:
	practice_evidence_remainder.clear()
	for shot_type in SHOT_TYPES:
		practice_evidence_remainder[shot_type] = 0.0

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
	var prior_remainder := float(practice_evidence_remainder.get(shot_type, 0.0))
	var exact_opportunity := float(reps) * resolved_quality + prior_remainder
	var evidence_reps := clampi(int(floor(exact_opportunity + 0.0000001)), 0, reps)
	var next_remainder := exact_opportunity - float(evidence_reps)
	practice_evidence_remainder[shot_type] = clampf(next_remainder, 0.0, 0.9999999)
	var experience_only := reps - evidence_reps

	for _i in range(evidence_reps):
		development.record_execution(shot_type, execution_score, lateral_error, distance_error, persistent_execution_score)
	if experience_only > 0:
		development.record_experience_only(shot_type, experience_only)
	return {
		"raw_repetitions": reps,
		"quality": resolved_quality,
		"evidence_repetitions": evidence_reps,
		"experience_only_repetitions": experience_only,
		"fractional_evidence_carry": float(practice_evidence_remainder.get(shot_type, 0.0))
	}
