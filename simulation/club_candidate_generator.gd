extends RefCounted

# POC-13A: bag-derived candidate generation.
# ------------------------------------------
# Given a golfer and live course state, enumerate feasible club-specific advances
# from the golfer's actual bag. This is intentionally separate from utility
# scoring: geometry + bag define what can be attempted; later POC-13 slices decide
# which candidate best matches the golfer's strategy and personality.

const GolfBag = preload("res://simulation/golf_bag.gd")

var bag = GolfBag.new()


func generate(golfer: Node, state) -> Array:
	var candidates: Array = []
	if golfer == null or state == null:
		return candidates

	var surface: String = state.surface_name()
	var lie_quality: float = state.current_lie_quality
	var remaining: float = state.remaining_distance()
	if surface == "GREEN" or remaining <= 8.0:
		return candidates

	var direction: Vector3 = state.hole_position - state.ball_position
	direction.y = 0.0
	if direction.length() <= 0.001:
		return candidates
	direction = direction.normalized()

	for club in bag.clubs_for_surface(surface):
		if str(club.get("id", "")) == "PUTTER":
			continue
		var carry: float = bag.effective_carry(club, golfer, surface, lie_quality)
		if carry <= 0.0:
			continue
		var intended_distance: float = min(carry, remaining)
		var target: Vector3 = state.ball_position + direction * intended_distance
		var dispersion: float = bag.effective_dispersion(club, golfer, surface, lie_quality)
		var execution_penalty: float = bag.surface_execution_penalty(club, surface, lie_quality)
		var expected_surface: String = _surface_name_at(state, target)
		var corridor_hazards: Array = _corridor_hazards(state, target, dispersion)
		var out_of_bounds: bool = _is_out_of_bounds(state, target)
		candidates.append({
			"name": "CLUB_ADVANCE",
			"club": club.duplicate(true),
			"club_id": str(club.get("id", "")),
			"club_name": str(club.get("name", "")),
			"shot_type": int(club.get("shot_type", 1)),
			"target": target,
			"effective_carry": carry,
			"intended_distance": intended_distance,
			"dispersion": dispersion,
			"surface_execution_penalty": execution_penalty,
			"remaining_after_target": target.distance_to(state.hole_position),
			"expected_surface": expected_surface,
			"corridor_hazards": corridor_hazards,
			"corridor_hazard_count": corridor_hazards.size(),
			"out_of_bounds": out_of_bounds,
			"green_reaching": carry >= remaining
		})

	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("effective_carry", 0.0)) > float(b.get("effective_carry", 0.0))
	)
	return candidates


func _surface_name_at(state, position: Vector3) -> String:
	if state.course_context == null:
		return "UNKNOWN"
	var surface_value: int = state.course_context.surface_at(position)
	return state.course_context.surface_name(surface_value)


func _corridor_hazards(state, target: Vector3, dispersion: float) -> Array:
	if state.course_context == null or not state.course_context.has_method("hazards_in_corridor"):
		return []
	return state.course_context.hazards_in_corridor(state.ball_position, target, max(1.0, dispersion))


func _is_out_of_bounds(state, target: Vector3) -> bool:
	if state.course_context == null or not state.course_context.has_method("is_out_of_bounds"):
		return false
	return state.course_context.is_out_of_bounds(target)
