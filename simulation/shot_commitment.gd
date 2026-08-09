extends RefCounted

# MISS CONSEQUENCES: evaluate directional failure, not only success/failure.
func assess_miss_consequences(situation, target: Vector3, dispersion: float) -> Dictionary:
	var start: Vector3 = situation.ball_position
	var direction = target - start
	direction.y = 0.0
	if direction.length() <= 0.001:
		direction = Vector3.FORWARD
	else:
		direction = direction.normalized()
	var lateral = Vector3(-direction.z, 0.0, direction.x)
	var sample_distance = max(dispersion, 2.0)
	var short_point = target - direction * sample_distance
	var long_point = target + direction * sample_distance
	var left_point = target - lateral * sample_distance
	var right_point = target + lateral * sample_distance
	var costs = {
		"short": _miss_cost(situation, start, short_point),
		"long": _miss_cost(situation, start, long_point),
		"left": _miss_cost(situation, start, left_point),
		"right": _miss_cost(situation, start, right_point)
	}
	var safest = "short"
	var safest_cost = float(costs[safest])
	for key in costs.keys():
		if float(costs[key]) < safest_cost:
			safest = key
			safest_cost = float(costs[key])
	var worst_cost = 0.0
	for value in costs.values():
		worst_cost = max(worst_cost, float(value))
	return {"costs": costs, "safest_miss": safest, "safest_cost": safest_cost, "worst_cost": worst_cost}

# COMMITMENT: belief in the selected shot after the decision has been made.
# This is deliberately separate from choice utility and can affect execution.
func assess_commitment(golfer: Node, capability: Dictionary, specific_confidence: float, mental_state: Dictionary, decision_gap: float = 0.0) -> Dictionary:
	var capability_score = float(capability.get("capability_score", 50.0))
	var focus = float(mental_state.get("focus", 50.0))
	var nerves = float(mental_state.get("nervous", 0.0))
	var fear = float(mental_state.get("fear", 0.0))
	var frustration = float(mental_state.get("frustrated", 0.0))
	var score = capability_score * 0.30 + specific_confidence * 0.35 + focus * 0.20 + float(golfer.confidence) * 0.15
	score -= nerves * 0.10 + fear * 0.12 + frustration * 0.06
	score -= max(decision_gap, 0.0) * 0.50
	score = clamp(score, 0.0, 100.0)
	var label = "COMMITTED"
	if score < 45.0:
		label = "DOUBTFUL"
	elif score < 65.0:
		label = "TENTATIVE"
	var execution_dispersion_factor = lerp(1.30, 0.90, score / 100.0)
	var execution_carry_factor = lerp(0.94, 1.01, score / 100.0)
	return {
		"score": score,
		"label": label,
		"dispersion_factor": execution_dispersion_factor,
		"carry_factor": execution_carry_factor
	}

func _miss_cost(situation, start: Vector3, point: Vector3) -> float:
	var cost = float(situation.recovery_difficulty)
	var hazard = situation.hazard_on_line_to(point)
	if not hazard.is_empty():
		cost = max(cost, float(hazard.get("risk", 80.0)))
	var progress = start.distance_to(situation.target_position) - point.distance_to(situation.target_position)
	if progress < 0.0:
		cost += min(abs(progress) * 0.4, 20.0)
	return clamp(cost, 0.0, 100.0)
