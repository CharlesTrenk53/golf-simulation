extends RefCounted

const PuttingIntent = preload("res://simulation/putting_intent.gd")

# POC-15A deterministic putting read. The model converts simple green context
# into an intended start line and pace. Execution error belongs in a later layer.
#
# slope_across_percent:
#   positive = ball tends to break right during the putt
#   negative = ball tends to break left
# slope_along_percent:
#   positive = uphill toward the hole
#   negative = downhill toward the hole


func plan_putt(
	distance_feet: float,
	slope_across_percent: float = 0.0,
	slope_along_percent: float = 0.0,
	green_speed: float = 10.0
) -> Dictionary:
	var distance := max(0.0, distance_feet)
	var speed := clamp(green_speed, 7.0, 14.0)

	# Faster greens and longer travel both allow cross-slope to act longer. The
	# coefficient is intentionally modest for POC-15A; calibration comes later.
	var speed_factor := lerp(0.80, 1.25, (speed - 7.0) / 7.0)
	var distance_factor := pow(max(distance, 1.0) / 10.0, 1.35)
	var aim_offset := slope_across_percent * distance_factor * speed_factor * 0.42

	# Baseline pace is enough to finish modestly past the cup on a level green.
	# Uphill putts require more delivered distance; downhill putts require less.
	var baseline_past := lerp(1.0, 2.5, clamp(distance / 40.0, 0.0, 1.0))
	var slope_pace_adjustment := slope_along_percent * distance * 0.045
	var speed_pace_adjustment := (10.0 - speed) * distance * 0.012
	var intended_distance := max(0.0, distance + baseline_past + slope_pace_adjustment + speed_pace_adjustment)
	var pace_past := max(0.0, intended_distance - distance)

	var intent = PuttingIntent.new(aim_offset, pace_past, intended_distance)
	var result := intent.as_dictionary()
	result["distance_feet"] = distance
	result["slope_across_percent"] = slope_across_percent
	result["slope_along_percent"] = slope_along_percent
	result["green_speed"] = speed
	return result
