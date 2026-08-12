extends RefCounted

# POC-15B: golfer-specific putting execution proficiency.
# The putting read remains immutable. This layer describes how tightly a golfer
# can reproduce the intended start line and pace before stochastic realization.


func assess(golfer: Node, planned_putt: Dictionary) -> Dictionary:
	var putting_ability: float = clampf(float(golfer.get_shot_ability(3)), 0.0, 100.0)
	var coordination: float = clampf(float(golfer.get("coordination")), 0.0, 100.0)
	var confidence: float = clampf(float(golfer.get("confidence")), 0.0, 100.0)
	var distance_feet: float = maxf(0.0, float(planned_putt.get("distance_feet", 0.0)))

	# Putting ability is primary; coordination controls repeatability and confidence
	# has a smaller influence.
	var reliability: float = clampf(
		(putting_ability * 0.65 + coordination * 0.25 + confidence * 0.10) / 100.0,
		0.05,
		0.99
	)

	# A fixed lateral error in inches made long putts unrealistically easy. Treat
	# start-line precision as a short-putt base that compounds with path length:
	# tiny stroke errors matter little from three feet but produce increasingly
	# large lateral misses as the ball must stay on line for longer.
	var short_line_sigma_inches: float = lerpf(2.0, 0.5, reliability)
	var line_distance_factor: float = pow(maxf(distance_feet, 3.0) / 3.0, 1.25)
	var line_sigma_inches: float = short_line_sigma_inches * line_distance_factor

	# Pace is comparatively easy to control on very short putts. Longer strokes
	# widen distance uncertainty progressively, with stronger putters widening
	# more slowly rather than receiving an almost distance-independent advantage.
	var short_pace_sigma_feet: float = lerpf(0.60, 0.18, reliability)
	var pace_distance_factor: float = 1.0 + 0.80 * pow(distance_feet / 10.0, 1.15)
	var pace_sigma_feet: float = short_pace_sigma_feet * pace_distance_factor

	return {
		"putting_ability": putting_ability,
		"coordination": coordination,
		"confidence": confidence,
		"execution_reliability": reliability,
		"line_sigma_inches": line_sigma_inches,
		"pace_sigma_feet": pace_sigma_feet,
		"putt_signature": str(planned_putt.get("signature", ""))
	}
