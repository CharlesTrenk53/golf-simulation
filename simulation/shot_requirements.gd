extends RefCounted

# POC-08 REQUIREMENTS layer. Converts world facts into the golf problem that
# must be solved. These requirements remain independent of personality.

var effective_distance: float = 0.0
var required_carry: float = 0.0
var total_distance: float = 0.0
var accuracy_demand: float = 50.0
var trajectory_demand: float = 50.0
var stopping_demand: float = 40.0
var lie_demand: float = 50.0
var obstacle_clearance_required: bool = false
var preferred_trajectory: String = "NORMAL"
var safe_miss_direction: String = "CENTER"
var short_miss_cost: float = 20.0
var long_miss_cost: float = 20.0
var left_miss_cost: float = 20.0
var right_miss_cost: float = 20.0
var margin_for_error: float = 50.0

func derive(situation) -> Dictionary:
	effective_distance = situation.effective_playing_distance()
	total_distance = effective_distance
	required_carry = effective_distance * 0.88
	lie_demand = _lie_demand(situation.surface)
	var direct_hazard = situation.hazard_on_line_to(situation.target_position)
	if not direct_hazard.is_empty():
		var hazard_distance = _horizontal_distance(situation.ball_position, direct_hazard["position"])
		var hazard_radius = float(direct_hazard.get("radius", 6.0))
		required_carry = max(required_carry, hazard_distance + hazard_radius + 2.0)
		short_miss_cost = max(short_miss_cost, float(direct_hazard.get("risk", 75.0)))
		accuracy_demand += 15.0
		margin_for_error += 15.0
		obstacle_clearance_required = true
		preferred_trajectory = "HIGH"

	if situation.surface == "ROUGH":
		accuracy_demand += 10.0
		trajectory_demand += 5.0
	elif situation.surface == "BUNKER":
		accuracy_demand += 15.0
		trajectory_demand += 20.0
		preferred_trajectory = "HIGH"

	if situation.safe_landing_position != situation.target_position:
		margin_for_error += 10.0

	accuracy_demand = clamp(accuracy_demand, 0.0, 100.0)
	trajectory_demand = clamp(trajectory_demand, 0.0, 100.0)
	margin_for_error = clamp(margin_for_error, 0.0, 100.0)
	return as_dictionary()

func as_dictionary() -> Dictionary:
	return {
		"effective_distance": effective_distance,
		"required_carry": required_carry,
		"total_distance": total_distance,
		"accuracy_demand": accuracy_demand,
		"trajectory_demand": trajectory_demand,
		"stopping_demand": stopping_demand,
		"lie_demand": lie_demand,
		"obstacle_clearance_required": obstacle_clearance_required,
		"preferred_trajectory": preferred_trajectory,
		"safe_miss_direction": safe_miss_direction,
		"short_miss_cost": short_miss_cost,
		"long_miss_cost": long_miss_cost,
		"left_miss_cost": left_miss_cost,
		"right_miss_cost": right_miss_cost,
		"margin_for_error": margin_for_error
	}

func _lie_demand(surface: String) -> float:
	match surface:
		"TEE": return 15.0
		"FAIRWAY": return 25.0
		"ROUGH": return 60.0
		"BUNKER": return 80.0
		"GREEN": return 20.0
	return 50.0

func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	var delta = b - a
	delta.y = 0.0
	return delta.length()
