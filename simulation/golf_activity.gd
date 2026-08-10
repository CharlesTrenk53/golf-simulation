extends RefCounted

# Golf Activity
# -------------
# Records what golf the golfer actually does. This layer is intentionally factual:
# rounds played, on-course shot exposure, practice repetitions, practice focus,
# and practice quality. It does not award skill and does not decide how much
# durable learning results from that activity.

const SHOT_TYPES := [0, 1, 2, 3]
const DEFAULT_SHOTS_PER_ROUND := {
	0: 14,
	1: 22,
	2: 12,
	3: 30
}

var career_rounds_played: int = 0
var career_on_course_exposure: Dictionary = {}
var career_practice_repetitions: Dictionary = {}
var practice_quality_sum: Dictionary = {}
var practice_sessions: Dictionary = {}

func _init() -> void:
	reset()

func reset() -> void:
	career_rounds_played = 0
	career_on_course_exposure.clear()
	career_practice_repetitions.clear()
	practice_quality_sum.clear()
	practice_sessions.clear()
	for shot_type in SHOT_TYPES:
		career_on_course_exposure[shot_type] = 0
		career_practice_repetitions[shot_type] = 0
		practice_quality_sum[shot_type] = 0.0
		practice_sessions[shot_type] = 0

func record_rounds(rounds: int, shots_per_round: Dictionary = {}) -> Dictionary:
	var resolved_rounds := maxi(rounds, 0)
	var distribution := DEFAULT_SHOTS_PER_ROUND if shots_per_round.is_empty() else shots_per_round
	var added_exposure: Dictionary = {}
	career_rounds_played += resolved_rounds
	for shot_type in SHOT_TYPES:
		var per_round := maxi(int(distribution.get(shot_type, 0)), 0)
		var added := resolved_rounds * per_round
		career_on_course_exposure[shot_type] = int(career_on_course_exposure.get(shot_type, 0)) + added
		added_exposure[shot_type] = added
	return {
		"rounds": resolved_rounds,
		"on_course_exposure": added_exposure
	}

func record_practice(total_repetitions: int, focus: Dictionary, quality: float = 1.0) -> Dictionary:
	var repetitions := maxi(total_repetitions, 0)
	var resolved_quality := clampf(quality, 0.0, 1.0)
	var normalized_focus := _normalized_focus(focus)
	var allocations := _allocate_repetitions(repetitions, normalized_focus)
	for shot_type in SHOT_TYPES:
		var reps := int(allocations.get(shot_type, 0))
		if reps <= 0:
			continue
		career_practice_repetitions[shot_type] = int(career_practice_repetitions.get(shot_type, 0)) + reps
		practice_quality_sum[shot_type] = float(practice_quality_sum.get(shot_type, 0.0)) + float(reps) * resolved_quality
		practice_sessions[shot_type] = int(practice_sessions.get(shot_type, 0)) + 1
	return {
		"repetitions": repetitions,
		"focus": normalized_focus,
		"quality": resolved_quality,
		"practice_repetitions": allocations
	}

func average_practice_quality(shot_type: int) -> float:
	var reps := int(career_practice_repetitions.get(shot_type, 0))
	if reps <= 0:
		return 0.0
	return float(practice_quality_sum.get(shot_type, 0.0)) / float(reps)

func total_on_course_exposure() -> int:
	return _sum_int_dictionary(career_on_course_exposure)

func total_practice_repetitions() -> int:
	return _sum_int_dictionary(career_practice_repetitions)

func total_activity_repetitions() -> int:
	return total_on_course_exposure() + total_practice_repetitions()

func state() -> Dictionary:
	var average_quality: Dictionary = {}
	for shot_type in SHOT_TYPES:
		average_quality[shot_type] = average_practice_quality(shot_type)
	return {
		"career_rounds_played": career_rounds_played,
		"career_on_course_exposure": career_on_course_exposure.duplicate(true),
		"career_practice_repetitions": career_practice_repetitions.duplicate(true),
		"average_practice_quality": average_quality,
		"total_on_course_exposure": total_on_course_exposure(),
		"total_practice_repetitions": total_practice_repetitions(),
		"total_activity_repetitions": total_activity_repetitions()
	}

func _normalized_focus(focus: Dictionary) -> Dictionary:
	var resolved: Dictionary = {}
	var total := 0.0
	for shot_type in SHOT_TYPES:
		var weight := maxf(float(focus.get(shot_type, 0.0)), 0.0)
		resolved[shot_type] = weight
		total += weight
	if total <= 0.0:
		var equal_weight := 1.0 / float(SHOT_TYPES.size())
		for shot_type in SHOT_TYPES:
			resolved[shot_type] = equal_weight
		return resolved
	for shot_type in SHOT_TYPES:
		resolved[shot_type] = float(resolved[shot_type]) / total
	return resolved

func _allocate_repetitions(repetitions: int, normalized_focus: Dictionary) -> Dictionary:
	var allocations: Dictionary = {}
	var allocated := 0
	var remainders: Array = []
	for shot_type in SHOT_TYPES:
		var exact := float(repetitions) * float(normalized_focus.get(shot_type, 0.0))
		var base := int(floor(exact))
		allocations[shot_type] = base
		allocated += base
		remainders.append({"shot_type": shot_type, "remainder": exact - float(base)})
	remainders.sort_custom(func(a, b): return float(a["remainder"]) > float(b["remainder"]))
	var remaining := repetitions - allocated
	for i in range(remaining):
		var shot_type := int(remainders[i % remainders.size()]["shot_type"])
		allocations[shot_type] = int(allocations[shot_type]) + 1
	return allocations

func _sum_int_dictionary(values: Dictionary) -> int:
	var total := 0
	for shot_type in SHOT_TYPES:
		total += int(values.get(shot_type, 0))
	return total
