extends RefCounted

# Shallow look-ahead model. It does not recursively simulate future shots.
# Instead it estimates the likely next state for an option and converts that
# state into golfer-specific expected strokes remaining.

func estimate(golfer: Node, state, option: Dictionary) -> Dictionary:
	var assessment: Dictionary = option.get("assessment", {})
	var capability: Dictionary = assessment.get("capability", {})
	var target: Vector3 = option.get("target_position", state.hole_position)
	var expected_surface = String(option.get("expected_surface", ""))
	if expected_surface.is_empty():
		expected_surface = _surface_at_target(state, target)
	var remaining = target.distance_to(state.hole_position)
	var success = clamp(float(option.get("model_success_chance", 50.0)) / 100.0, 0.05, 0.98)
	var dispersion = max(float(capability.get("expected_dispersion", 6.0)), 1.0)
	var miss: Dictionary = assessment.get("miss_consequences", {})
	var worst_cost = float(miss.get("worst_cost", 0.0))

	# Likely miss state is represented as extra remaining distance plus lie cost.
	# This keeps the model shallow and explainable while acknowledging that the
	# target point is not guaranteed.
	var miss_distance_penalty = dispersion * 0.65
	var likely_remaining = remaining + (1.0 - success) * miss_distance_penalty
	var expected_strokes = _strokes_from_state(golfer, likely_remaining, expected_surface)
	var hazard_penalty = (1.0 - success) * clamp(worst_cost / 100.0, 0.0, 1.5) * 0.80
	expected_strokes += hazard_penalty

	# If the option explicitly says the green is reachable next, modestly reduce
	# future burden. Conversely, a layup that still leaves another layup-range
	# shot should carry a small sequencing cost.
	if option.get("next_shot_green_reachable", false):
		expected_strokes -= 0.18
	if String(option.get("name", "")) == "LAYUP" and likely_remaining > _comfortable_approach_distance(golfer):
		expected_strokes += 0.30

	return {
		"expected_surface": expected_surface,
		"expected_remaining_distance": max(likely_remaining, 0.0),
		"expected_strokes_remaining": max(expected_strokes, 0.0),
		"success_probability": success,
		"hazard_penalty_strokes": hazard_penalty,
		"lookahead_depth": 1
	}

func _strokes_from_state(golfer: Node, distance: float, surface: String) -> float:
	if distance <= 0.5:
		return 0.0
	if surface == "GREEN":
		return _putting_strokes(golfer, distance)

	var approach_ability = float(golfer.get_shot_ability(1))
	var short_ability = float(golfer.get_shot_ability(2))
	var putting_ability = float(golfer.get_shot_ability(3))
	var comfortable = _comfortable_approach_distance(golfer)
	var strokes = 1.0

	if distance <= 8.0:
		strokes = 1.0 + (100.0 - short_ability) / 170.0 + (100.0 - putting_ability) / 220.0
	elif distance <= 25.0:
		strokes = 1.55 + (100.0 - short_ability) / 105.0 + (100.0 - putting_ability) / 250.0
	else:
		# Use a continuous distance burden instead of ceil(distance / comfortable).
		# The previous stair-step made 36.9 and 72.8 units both count as two full
		# shots for Bill. This smooth curve preserves the intuitive ordering that
		# every extra unit of distance increases expected strokes gradually.
		var distance_ratio = distance / max(comfortable, 1.0)
		var approach_penalty = (100.0 - approach_ability) / 110.0
		var putting_penalty = (100.0 - putting_ability) / 300.0
		strokes = 1.55 + distance_ratio * 0.92 + approach_penalty + putting_penalty

	if surface == "ROUGH":
		strokes += 0.28
	elif surface == "BUNKER":
		strokes += 0.48
	elif surface == "WATER":
		strokes += 1.35
	elif surface == "FAIRWAY":
		strokes -= 0.08
	return max(strokes, 0.0)

func _putting_strokes(golfer: Node, distance: float) -> float:
	var ability = float(golfer.get_shot_ability(3))
	var base = 1.0 + min(distance / 12.0, 1.6)
	return max(base + (70.0 - ability) / 120.0, 1.0)

func _comfortable_approach_distance(golfer: Node) -> float:
	# Uses the golfer's demonstrated approach ability to define a personalized
	# distance scale for the continuous expected-strokes curve.
	var approach_ability = float(golfer.get_shot_ability(1))
	return max(24.0 + approach_ability * 0.18, 26.0)

func _surface_at_target(state, target: Vector3) -> String:
	if state.course_context == null:
		return "FAIRWAY"
	return state.course_context.surface_name(state.course_context.surface_at(target))
