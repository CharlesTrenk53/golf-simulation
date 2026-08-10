extends RefCounted

# Development Opportunity
# -----------------------
# Translates factual golf activity into developmental opportunity while preserving
# where that opportunity came from. This layer does not award skill and deliberately
# avoids asserting that one practice repetition is equivalent to some fixed number
# of on-course shots.
#
# On-course exposure is retained as contextual opportunity. Practice exposure is
# retained both as raw repetitions and as quality-weighted technical opportunity.
# The technique-development system can later decide how those distinct channels
# should contribute to evidence without GolfActivity knowing anything about skill.

const SHOT_TYPES := [0, 1, 2, 3]

var on_course_repetitions: Dictionary = {}
var practice_repetitions: Dictionary = {}
var quality_weighted_practice: Dictionary = {}

func _init() -> void:
	reset()

func reset() -> void:
	on_course_repetitions.clear()
	practice_repetitions.clear()
	quality_weighted_practice.clear()
	for shot_type in SHOT_TYPES:
		on_course_repetitions[shot_type] = 0
		practice_repetitions[shot_type] = 0
		quality_weighted_practice[shot_type] = 0.0

func record_round_activity(activity_result: Dictionary) -> Dictionary:
	var exposure: Dictionary = activity_result.get("on_course_exposure", {})
	var added: Dictionary = {}
	for shot_type in SHOT_TYPES:
		var repetitions := maxi(int(exposure.get(shot_type, 0)), 0)
		on_course_repetitions[shot_type] = int(on_course_repetitions.get(shot_type, 0)) + repetitions
		added[shot_type] = repetitions
	return {
		"source": "PLAY",
		"contextual_repetitions": added
	}

func record_practice_activity(activity_result: Dictionary) -> Dictionary:
	var allocations: Dictionary = activity_result.get("practice_repetitions", {})
	var quality := clampf(float(activity_result.get("quality", 1.0)), 0.0, 1.0)
	var added_raw: Dictionary = {}
	var added_weighted: Dictionary = {}
	for shot_type in SHOT_TYPES:
		var repetitions := maxi(int(allocations.get(shot_type, 0)), 0)
		var weighted := float(repetitions) * quality
		practice_repetitions[shot_type] = int(practice_repetitions.get(shot_type, 0)) + repetitions
		quality_weighted_practice[shot_type] = float(quality_weighted_practice.get(shot_type, 0.0)) + weighted
		added_raw[shot_type] = repetitions
		added_weighted[shot_type] = weighted
	return {
		"source": "PRACTICE",
		"practice_repetitions": added_raw,
		"quality_weighted_practice": added_weighted,
		"quality": quality
	}

func state_for(shot_type: int) -> Dictionary:
	return {
		"on_course_repetitions": int(on_course_repetitions.get(shot_type, 0)),
		"practice_repetitions": int(practice_repetitions.get(shot_type, 0)),
		"quality_weighted_practice": float(quality_weighted_practice.get(shot_type, 0.0))
	}

func state() -> Dictionary:
	return {
		"on_course_repetitions": on_course_repetitions.duplicate(true),
		"practice_repetitions": practice_repetitions.duplicate(true),
		"quality_weighted_practice": quality_weighted_practice.duplicate(true),
		"total_on_course_repetitions": _sum_int_dictionary(on_course_repetitions),
		"total_practice_repetitions": _sum_int_dictionary(practice_repetitions),
		"total_quality_weighted_practice": _sum_float_dictionary(quality_weighted_practice)
	}

func _sum_int_dictionary(values: Dictionary) -> int:
	var total := 0
	for shot_type in SHOT_TYPES:
		total += int(values.get(shot_type, 0))
	return total

func _sum_float_dictionary(values: Dictionary) -> float:
	var total := 0.0
	for shot_type in SHOT_TYPES:
		total += float(values.get(shot_type, 0.0))
	return total
