extends RefCounted

# POC-13A/F: bag-derived club + target candidate generation.
# ----------------------------------------------------------
# The golfer's bag and the live course geometry define what can be attempted.
# Each feasible club now produces multiple spatial targets at the same stock-shot
# distance. The generator does not decide that LEFT is "safe" or RIGHT is
# "aggressive"; authoritative geometry supplies the actual landing surface,
# hazards, OB, and leave for each point, and the evaluator decides what those
# consequences mean. This keeps target strategy emergent instead of label-driven.

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
	var lateral := Vector3(-direction.z, 0.0, direction.x)

	for club in bag.clubs_for_surface(surface):
		if str(club.get("id", "")) == "PUTTER":
			continue
		var carry: float = bag.effective_carry(club, golfer, surface, lie_quality)
		if carry <= 0.0:
			continue
		var intended_distance: float = min(carry, remaining)
		var center_target: Vector3 = state.ball_position + direction * intended_distance
		var dispersion: float = bag.effective_dispersion(club, golfer, surface, lie_quality)
		var execution_penalty: float = bag.surface_execution_penalty(club, surface, lie_quality)
		var target_offset: float = _target_offset_for(dispersion, intended_distance, remaining)

		for variant in _target_variants(center_target, lateral, target_offset):
			var target: Vector3 = variant["target"]
			var expected_surface: String = _surface_name_at(state, target)
			var corridor_hazards: Array = _corridor_hazards(state, target, dispersion)
			var out_of_bounds: bool = _is_out_of_bounds(state, target)
			candidates.append({
				"name": "CLUB_TARGET",
				"club": club.duplicate(true),
				"club_id": str(club.get("id", "")),
				"club_name": str(club.get("name", "")),
				"shot_type": int(club.get("shot_type", 1)),
				"target": target,
				"centerline_target": center_target,
				"target_variant": str(variant["id"]),
				"lateral_offset": float(variant["offset"]),
				"effective_carry": carry,
				"intended_distance": state.ball_position.distance_to(target),
				"stock_forward_distance": intended_distance,
				"dispersion": dispersion,
				"surface_execution_penalty": execution_penalty,
				"remaining_after_target": target.distance_to(state.hole_position),
				"expected_surface": expected_surface,
				"corridor_hazards": corridor_hazards,
				"corridor_hazard_count": corridor_hazards.size(),
				"out_of_bounds": out_of_bounds,
				"green_reaching": carry >= remaining
			})

	# Generation order remains useful for diagnostics only. Final choice is made by
	# expected-strokes evaluation, not by this order.
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var carry_a := float(a.get("effective_carry", 0.0))
		var carry_b := float(b.get("effective_carry", 0.0))
		if abs(carry_a - carry_b) > 0.001:
			return carry_a > carry_b
		return abs(float(a.get("lateral_offset", 0.0))) < abs(float(b.get("lateral_offset", 0.0)))
	)
	return candidates


func _target_offset_for(dispersion: float, intended_distance: float, remaining: float) -> float:
	# Target choices should be meaningfully distinct without becoming trick-shot
	# directions. Wider-dispersion clubs naturally inspect a wider strategic band.
	# Near the hole the band contracts so approach targets remain plausible.
	var offset := clamp(max(8.0, dispersion * 1.6), 8.0, 18.0)
	if intended_distance >= remaining - 0.5:
		offset = min(offset, 10.0)
	elif intended_distance < 100.0:
		offset = min(offset, 8.0)
	return offset


func _target_variants(center: Vector3, lateral: Vector3, offset: float) -> Array:
	return [
		{"id": "CENTER", "offset": 0.0, "target": center},
		{"id": "LEFT", "offset": -offset, "target": center - lateral * offset},
		{"id": "RIGHT", "offset": offset, "target": center + lateral * offset}
	]


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
