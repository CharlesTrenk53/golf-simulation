extends RefCounted

# POC-13A/F: bag-derived club + target candidate generation.
# ----------------------------------------------------------
# The golfer's bag and the live course geometry define what can be attempted.
# Each feasible club now produces multiple spatial targets at the same stock-shot
# distance. The generator does not decide that a lane is "safe" or "aggressive";
# authoritative geometry supplies the actual landing surface, hazards, OB, and
# leave for each point, and the evaluator decides what those consequences mean.
# This keeps target strategy emergent instead of label-driven.

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
	var lateral: Vector3 = Vector3(-direction.z, 0.0, direction.x)

	for club in bag.clubs_for_surface(surface):
		if str(club.get("id", "")) == "PUTTER":
			continue
		var carry: float = bag.effective_carry(club, golfer, surface, lie_quality)
		if carry <= 0.0:
			continue
		var intended_distance: float = minf(carry, remaining)
		var center_target: Vector3 = state.ball_position + direction * intended_distance
		var dispersion: float = bag.effective_dispersion(club, golfer, surface, lie_quality)
		var execution_penalty: float = bag.surface_execution_penalty(club, surface, lie_quality)
		var lane_widths: Dictionary = _target_widths_for(dispersion, intended_distance, remaining)

		for variant in _target_variants(center_target, lateral, lane_widths):
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
		var carry_a: float = float(a.get("effective_carry", 0.0))
		var carry_b: float = float(b.get("effective_carry", 0.0))
		if absf(carry_a - carry_b) > 0.001:
			return carry_a > carry_b
		return absf(float(a.get("lateral_offset", 0.0))) < absf(float(b.get("lateral_offset", 0.0)))
	)
	return candidates


func _target_widths_for(dispersion: float, intended_distance: float, remaining: float) -> Dictionary:
	# Two bands let the golfer inspect both ordinary aiming adjustments and genuine
	# strategic lanes near course features. Long shots can consider an outer lane
	# around 26-36 yards from center; approaches contract so targets remain plausible.
	var inner: float = clampf(maxf(9.0, dispersion * 1.35), 9.0, 15.0)
	var outer: float = clampf(maxf(26.0, dispersion * 3.2), 26.0, 36.0)
	if intended_distance >= remaining - 0.5:
		inner = minf(inner, 8.0)
		outer = minf(outer, 16.0)
	elif intended_distance < 100.0:
		inner = minf(inner, 7.0)
		outer = minf(outer, 12.0)
	elif intended_distance < 150.0:
		outer = minf(outer, 20.0)
	return {"inner": inner, "outer": outer}


func _target_variants(center: Vector3, lateral: Vector3, widths: Dictionary) -> Array:
	var inner: float = float(widths.get("inner", 10.0))
	var outer: float = float(widths.get("outer", 28.0))
	return [
		{"id": "CENTER", "offset": 0.0, "target": center},
		{"id": "LEFT", "offset": -inner, "target": center - lateral * inner},
		{"id": "RIGHT", "offset": inner, "target": center + lateral * inner},
		{"id": "FAR_LEFT", "offset": -outer, "target": center - lateral * outer},
		{"id": "FAR_RIGHT", "offset": outer, "target": center + lateral * outer}
	]


func _surface_name_at(state, position: Vector3) -> String:
	if state.course_context == null:
		return "UNKNOWN"
	var surface_value: int = state.course_context.surface_at(position)
	return state.course_context.surface_name(surface_value)


func _corridor_hazards(state, target: Vector3, dispersion: float) -> Array:
	if state.course_context == null or not state.course_context.has_method("hazards_in_corridor"):
		return []
	return state.course_context.hazards_in_corridor(state.ball_position, target, maxf(1.0, dispersion))


func _is_out_of_bounds(state, target: Vector3) -> bool:
	if state.course_context == null or not state.course_context.has_method("is_out_of_bounds"):
		return false
	return state.course_context.is_out_of_bounds(target)
