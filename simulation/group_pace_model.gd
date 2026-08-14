extends RefCounted

# POC-24C: Group Pace Model
# -------------------------
# Converts authoritative hole geometry plus resolved group play into simulated
# elapsed time. Pace emerges from course travel, actual shot count, and penalty
# recovery rather than from a fixed per-hole duration.

var walking_yards_per_second: float = 1.45
var shot_routine_seconds: float = 30.0
var penalty_recovery_seconds: float = 45.0

func estimate_hole_duration(group_result: Dictionary, hole_definition, tee_id: String = "default") -> Dictionary:
	if hole_definition == null or group_result.is_empty():
		return {}
	var member_results: Array = group_result.get("member_results", [])
	if member_results.is_empty():
		return {}
	if walking_yards_per_second <= 0.0 or shot_routine_seconds < 0.0 or penalty_recovery_seconds < 0.0:
		return {}

	var total_strokes: int = 0
	var actual_shots: int = 0
	var penalty_strokes: int = 0
	for member_value in member_results:
		if typeof(member_value) != TYPE_DICTIONARY:
			continue
		var member: Dictionary = member_value
		total_strokes += max(0, int(member.get("strokes", 0)))
		var history: Array = member.get("history", [])
		if history.is_empty():
			actual_shots += max(0, int(member.get("strokes", 0)))
		else:
			actual_shots += history.size()
			for shot_value in history:
				if typeof(shot_value) == TYPE_DICTIONARY:
					penalty_strokes += max(0, int(shot_value.get("penalty_strokes", 0)))

	var travel_yards: float = max(0.0, float(hole_definition.tee_yardage(tee_id)))
	var travel_seconds: float = travel_yards / walking_yards_per_second
	var routine_seconds: float = float(actual_shots) * shot_routine_seconds
	var recovery_seconds: float = float(penalty_strokes) * penalty_recovery_seconds
	var total_seconds: float = travel_seconds + routine_seconds + recovery_seconds

	return {
		"hole_number": int(hole_definition.hole_number),
		"group_size": member_results.size(),
		"travel_yards": travel_yards,
		"actual_shots": actual_shots,
		"total_strokes": total_strokes,
		"penalty_strokes": penalty_strokes,
		"travel_seconds": travel_seconds,
		"shot_routine_seconds": routine_seconds,
		"penalty_recovery_seconds": recovery_seconds,
		"total_seconds": total_seconds
	}
