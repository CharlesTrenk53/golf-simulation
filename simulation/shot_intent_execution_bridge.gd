extends RefCounted

const ShotExecutionModel = preload("res://simulation/shot_execution_model.gd")

# POC-14F: translate the POC-14 execution realization into authoritative course
# coordinates. ShotExecutionModel stays geometry-agnostic; this bridge converts
# forward distance + lateral shape/error into a landing position relative to the
# golfer's chosen target line.

var execution_model = ShotExecutionModel.new()


func execute(start: Vector3, target: Vector3, predicted_flight: Dictionary, proficiency: Dictionary, seed_value: int) -> Dictionary:
	var direction: Vector3 = target - start
	direction.y = 0.0
	if direction.length() <= 0.001:
		direction = Vector3.FORWARD
	else:
		direction = direction.normalized()
	var lateral := Vector3(-direction.z, 0.0, direction.x)

	var realized: Dictionary = execution_model.realize(predicted_flight, proficiency, seed_value)
	var forward_yards: float = max(0.0, float(realized.get("actual_total_yards", 0.0)))
	var lateral_yards: float = float(realized.get("final_lateral_yards", 0.0))
	var landing: Vector3 = start + direction * forward_yards + lateral * lateral_yards
	landing.y = start.y

	var result: Dictionary = realized.duplicate(true)
	result["start_position"] = start
	result["target_position"] = target
	result["landing_position"] = landing
	result["forward_yards"] = forward_yards
	result["target_line_lateral_yards"] = lateral_yards
	result["target_miss_distance"] = target.distance_to(landing)
	return result
