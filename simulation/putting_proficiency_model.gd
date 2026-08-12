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
	# has a smaller influence. Longer putts widen pace uncertainty more than line.
	var reliability: float = clampf(
		(putting_ability * 0.65 + coordination * 0.25 + confidence * 0.10) / 100.0,
		0.05,
		0.99
	)
	var distance_pressure: float = clampf(distance_feet / 50.0, 0.0, 1.5)
	var line_sigma_inches: float = lerpf(3.8, 0.45, reliability) * lerpf(0.80, 1.25, minf(distance_pressure, 1.0))
	var pace_sigma_feet: float = lerpf(3.0, 0.25, reliability) * (1.0 + distance_pressure * 0.55)

	return {
		"putting_ability": putting_ability,
		"coordination": coordination,
		"confidence": confidence,
		"execution_reliability": reliability,
		"line_sigma_inches": line_sigma_inches,
		"pace_sigma_feet": pace_sigma_feet,
		"putt_signature": str(planned_putt.get("signature", ""))
	}
