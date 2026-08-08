extends RefCounted

const CourseState = preload("res://simulation/course_state.gd")
const ShotOptionGenerator = preload("res://simulation/shot_option_generator.gd")

var option_generator = ShotOptionGenerator.new()
var shot_history: Array = []


func play_hole(
	golfer: Node,
	start_position: Vector3,
	hole_position: Vector3,
	hazards: Array = [],
	par: int = 4,
	seed_value: int = 1
) -> Dictionary:
	seed(seed_value)
	shot_history.clear()

	var state = CourseState.new(start_position, hole_position, par)

	while state.can_continue():
		var options = option_generator.generate_options(golfer, state, hazards)
		if options.is_empty():
			break

		var chosen = golfer.choose_best_option(options)
		var result = _execute_option(golfer, state, chosen, hazards)
		shot_history.append(result)

		state.advance_to(
			result["landing_position"],
			result["outcome"],
			result["penalty_strokes"]
		)

		golfer.record_shot_result(
			result["outcome"],
			chosen["is_aggressive"]
		)

	return {
		"finished": state.finished,
		"strokes": state.strokes,
		"par": state.par,
		"remaining_distance": state.remaining_distance(),
		"final_position": state.ball_position,
		"history": shot_history.duplicate(true)
	}


func _execute_option(
	golfer: Node,
	state,
	option: Dictionary,
	hazards: Array
) -> Dictionary:
	var shot_type: int = option["shot_type"]
	var ability = golfer.get_shot_ability(shot_type)
	var target: Vector3 = option["target_position"]
	var start: Vector3 = state.ball_position
	var intended_distance = start.distance_to(target)
	var accuracy_factor = 1.0 - ability / 100.0
	var lateral_error = randf_range(-6.0, 6.0) * accuracy_factor
	var distance_error = randf_range(-6.0, 6.0) * accuracy_factor

	var direction = target - start
	direction.y = 0.0
	if direction.length() <= 0.001:
		direction = Vector3.FORWARD
	else:
		direction = direction.normalized()
	var lateral = Vector3(-direction.z, 0.0, direction.x)

	var landing = target + lateral * lateral_error + direction * distance_error
	landing.y = start.y

	var outcome = "SUCCESS"
	var penalty_strokes = 0

	if option["is_aggressive"]:
		var success_roll = randf_range(0.0, 100.0)
		if success_roll > float(option["model_success_chance"]):
			var hazard = _closest_intersecting_hazard(start, target, hazards)
			if not hazard.is_empty():
				landing = hazard["position"]
				landing.y = start.y
				outcome = "WATER"
				penalty_strokes = 1

	return {
		"shot_number": state.strokes + 1,
		"option": option["name"],
		"shot_type": shot_type,
		"start_position": start,
		"target_position": target,
		"landing_position": landing,
		"intended_distance": intended_distance,
		"outcome": outcome,
		"penalty_strokes": penalty_strokes,
		"remaining_after_shot": landing.distance_to(state.hole_position)
	}


func _closest_intersecting_hazard(
	start: Vector3,
	end: Vector3,
	hazards: Array
) -> Dictionary:
	var best: Dictionary = {}
	var best_distance = INF

	for hazard in hazards:
		if not hazard.has("position"):
			continue
		var position: Vector3 = hazard["position"]
		var radius: float = hazard.get("radius", 6.0)
		var path_distance = _distance_to_segment(position, start, end)
		if path_distance <= radius:
			var from_start = start.distance_to(position)
			if from_start < best_distance:
				best_distance = from_start
				best = hazard

	return best


func _distance_to_segment(
	point: Vector3,
	start: Vector3,
	end: Vector3
) -> float:
	var segment = end - start
	var length_squared = segment.length_squared()
	if length_squared <= 0.001:
		return point.distance_to(start)
	var t = clamp((point - start).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(start + segment * t)
