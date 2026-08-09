extends RefCounted

const CourseState = preload("res://simulation/course_state.gd")
const ShotOptionGenerator = preload("res://simulation/shot_option_generator.gd")
const GolfBag = preload("res://simulation/golf_bag.gd")

const WATER_BOUNDARY_STEPS := 80
const LATERAL_RELIEF_DISTANCE := 4.0

var option_generator = ShotOptionGenerator.new()
var bag = GolfBag.new()
var shot_history: Array = []


func create_state(start_position: Vector3, hole_position: Vector3, par: int = 4, seed_value: int = 1, course_context = null):
	seed(seed_value)
	shot_history.clear()
	return CourseState.new(start_position, hole_position, par, course_context)


func play_step(golfer: Node, state, hazards: Array = []) -> Dictionary:
	if not state.can_continue():
		return {}
	var surface_before = state.surface_name()
	var lie_quality_before = state.current_lie_quality
	var options = option_generator.generate_options(golfer, state, hazards)
	if options.is_empty():
		return {}
	var chosen = golfer.choose_best_option(options)
	var result = _execute_option(golfer, state, chosen, hazards)
	result["selected_option"] = chosen
	result["surface_before"] = surface_before
	result["lie_quality_before"] = lie_quality_before

	if state.course_context != null:
		var landing_surface = state.course_context.surface_at(result["landing_position"])
		if state.course_context.surface_name(landing_surface) == "WATER":
			result["outcome"] = "WATER"
			result["penalty_strokes"] = max(int(result["penalty_strokes"]), 1)

	var next_position: Vector3 = result["landing_position"]
	if result["outcome"] == "WATER":
		var entry_point = _find_water_entry_point(state, result["start_position"], result["landing_position"])
		next_position = _lateral_water_relief_position(state, entry_point, result["start_position"])
		result["water_entry_point"] = entry_point
		result["relief_position"] = next_position
	else:
		result["water_entry_point"] = result["landing_position"]
		result["relief_position"] = result["landing_position"]

	state.advance_to(next_position, result["outcome"], result["penalty_strokes"])
	result["surface_after"] = state.surface_name()
	result["lie_quality_after"] = state.current_lie_quality
	shot_history.append(result)
	golfer.record_shot_result(result["outcome"], chosen["is_aggressive"])
	return result


func _find_water_entry_point(state, start: Vector3, water_position: Vector3) -> Vector3:
	if state.course_context == null:
		return water_position
	var last_dry = start
	for step in range(1, WATER_BOUNDARY_STEPS + 1):
		var t = float(step) / float(WATER_BOUNDARY_STEPS)
		var sample = start.lerp(water_position, t)
		if _position_is_water(state, sample):
			var dry = last_dry
			var wet = sample
			for _refine in range(10):
				var midpoint = dry.lerp(wet, 0.5)
				if _position_is_water(state, midpoint):
					wet = midpoint
				else:
					dry = midpoint
			return dry
		last_dry = sample
	return water_position


func _lateral_water_relief_position(state, entry_point: Vector3, previous_position: Vector3) -> Vector3:
	if state.course_context == null:
		return previous_position
	var toward_hole = state.hole_position - entry_point
	toward_hole.y = 0.0
	if toward_hole.length() <= 0.001:
		toward_hole = Vector3.FORWARD
	else:
		toward_hole = toward_hole.normalized()
	var lateral = Vector3(-toward_hole.z, 0.0, toward_hole.x)
	var reference_distance = entry_point.distance_to(state.hole_position)
	for distance in [LATERAL_RELIEF_DISTANCE, 3.0, 2.0, 1.0]:
		for side in [1.0, -1.0]:
			var candidate = entry_point + lateral * distance * side
			candidate.y = previous_position.y
			if not _position_is_water(state, candidate) and candidate.distance_to(state.hole_position) >= reference_distance - 0.01:
				return candidate
	for back_distance in [1.0, 2.0, 3.0, LATERAL_RELIEF_DISTANCE]:
		var candidate = entry_point - toward_hole * back_distance
		candidate.y = previous_position.y
		if not _position_is_water(state, candidate) and candidate.distance_to(state.hole_position) >= reference_distance - 0.01:
			return candidate
	return previous_position


func _position_is_water(state, position: Vector3) -> bool:
	var surface = state.course_context.surface_at(position)
	return state.course_context.surface_name(surface) == "WATER"


func play_hole(golfer: Node, start_position: Vector3, hole_position: Vector3, hazards: Array = [], par: int = 4, seed_value: int = 1, course_context = null) -> Dictionary:
	var state = create_state(start_position, hole_position, par, seed_value, course_context)
	while state.can_continue():
		var result = play_step(golfer, state, hazards)
		if result.is_empty():
			break
	return {"finished": state.finished, "strokes": state.strokes, "par": state.par, "remaining_distance": state.remaining_distance(), "final_position": state.ball_position, "final_surface": state.surface_name(), "history": shot_history.duplicate(true)}


func _execute_option(golfer: Node, state, option: Dictionary, hazards: Array) -> Dictionary:
	var shot_type: int = option["shot_type"]
	var ability = golfer.get_shot_ability(shot_type)
	var target: Vector3 = option["target_position"]
	var start: Vector3 = state.ball_position
	var intended_distance = start.distance_to(target)
	var club: Dictionary = option.get("club", {})
	var dispersion = 6.0 * (1.0 - ability / 100.0) * (1.0 + (1.0 - state.current_lie_quality))
	var effective_carry = intended_distance
	if not club.is_empty():
		dispersion = bag.effective_dispersion(club, golfer, state.surface_name(), state.current_lie_quality)
		effective_carry = bag.effective_carry(club, golfer, state.surface_name(), state.current_lie_quality)

	var direction = target - start
	direction.y = 0.0
	if direction.length() <= 0.001:
		direction = Vector3.FORWARD
	else:
		direction = direction.normalized()
	var lateral = Vector3(-direction.z, 0.0, direction.x)
	var lateral_error = randf_range(-dispersion, dispersion)
	var distance_error = randf_range(-dispersion * 0.7, dispersion * 0.7)
	var commanded_distance = min(intended_distance, effective_carry)
	var nominal = start + direction * commanded_distance
	var landing = nominal + lateral * lateral_error + direction * distance_error
	landing.y = start.y

	var outcome = "SUCCESS"
	var penalty_strokes = 0
	var execution_roll = -1.0
	if option["is_aggressive"]:
		execution_roll = randf_range(0.0, 100.0)
		if execution_roll > float(option["model_success_chance"]):
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
		"club_id": option.get("club_id", ""),
		"club_name": option.get("club_name", ""),
		"club_effective_carry": effective_carry,
		"club_dispersion": dispersion,
		"start_position": start,
		"target_position": target,
		"landing_position": landing,
		"intended_distance": intended_distance,
		"outcome": outcome,
		"penalty_strokes": penalty_strokes,
		"execution_roll": execution_roll,
		"remaining_after_shot": landing.distance_to(state.hole_position)
	}


func _closest_intersecting_hazard(start: Vector3, end: Vector3, hazards: Array) -> Dictionary:
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


func _distance_to_segment(point: Vector3, start: Vector3, end: Vector3) -> float:
	var segment = end - start
	var length_squared = segment.length_squared()
	if length_squared <= 0.001:
		return point.distance_to(start)
	var t = clamp((point - start).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(start + segment * t)
