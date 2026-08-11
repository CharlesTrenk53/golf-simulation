extends RefCounted

const GolfBag = preload("res://simulation/golf_bag.gd")

const DRIVE := 0
const APPROACH := 1
const SHORT_GAME := 2
const PUTT := 3

var bag = GolfBag.new()


func generate_options(golfer: Node, state, hazards: Array = []) -> Array:
	var distance: float = state.remaining_distance()
	var surface: String = state.surface_name()
	var lie_quality: float = state.current_lie_quality
	var yard_mode: bool = bag.is_using_literal_yardages()

	if surface == "GREEN" or distance <= 8.0:
		return [_putt_option(golfer, state)]
	if surface == "BUNKER":
		return _bunker_options(golfer, state, distance)
	if distance <= 25.0:
		return [
			_clubbed_direct_option("PITCH", golfer, SHORT_GAME, state, 68.0 * lie_quality, _lie_risk(12.0, state)),
			_clubbed_direct_option("SAFE_PITCH", golfer, SHORT_GAME, state, 58.0 * lie_quality, _lie_risk(5.0, state))
		]

	var options: Array = []
	var direction: Vector3 = _direction_to_hole(state)
	var lateral: Vector3 = Vector3(-direction.z, 0.0, direction.x)
	var layup_distance: float
	var bailout_distance: float
	if yard_mode:
		# Full-length course choices are anchored to real clubs instead of the old
		# compact proving-hole caps. Conservative means a positional iron, while
		# bailout is a longer but still controlled fairway-wood/hybrid advance.
		layup_distance = min(distance * 0.55, _named_club_distance("5_IRON", golfer, surface, lie_quality, 155.0))
		bailout_distance = min(distance * 0.65, _named_club_distance("3_WOOD", golfer, surface, lie_quality, 210.0))
	else:
		layup_distance = min(distance * 0.45, 28.0) * lie_quality
		bailout_distance = min(distance * 0.60, 38.0) * lie_quality
	var lateral_offset: float = 12.0 if yard_mode else 8.0
	var layup_target: Vector3 = _find_playable_target(state, state.ball_position + direction * layup_distance, direction, lateral)
	var bailout_target: Vector3 = _find_playable_target(state, state.ball_position + direction * bailout_distance + lateral * lateral_offset, direction, lateral)

	options.append(_option_with_club("LAYUP", golfer, APPROACH, state, layup_target, 45.0 * lie_quality, _lie_risk(10.0, state), false, _safe_success_chance(92.0, lie_quality)))
	options.append(_option_with_club("BAILOUT", golfer, APPROACH, state, bailout_target, 55.0 * lie_quality, _lie_risk(30.0, state), false, _safe_success_chance(86.0, lie_quality)))

	if surface == "TEE" or surface == "FAIRWAY" or state.course_context == null:
		var preferred_attack_distance: float
		if yard_mode:
			preferred_attack_distance = min(distance, _named_club_distance("DRIVER", golfer, surface, lie_quality, 220.0))
		else:
			preferred_attack_distance = min(distance, golfer.driving_distance * lie_quality)
		var attack_club: Dictionary = bag.best_distance_match(golfer, surface, lie_quality, preferred_attack_distance)
		var attack_distance: float = preferred_attack_distance
		if not attack_club.is_empty():
			attack_distance = min(distance, bag.effective_carry(attack_club, golfer, surface, lie_quality))
		var attack_target: Vector3 = state.ball_position + direction * attack_distance
		var attack_risk: float = _estimate_attack_risk(golfer, state, attack_target, hazards, attack_club)
		var success_chance: float = _estimate_club_success(golfer, state, attack_distance, attack_club)
		options.append(_option("ATTACK", DRIVE, attack_target, 65.0 * lie_quality, _lie_risk(attack_risk, state), true, success_chance, attack_club))
	elif surface == "ROUGH":
		var recovery_cap: float = 145.0 if yard_mode else 32.0
		var recovery_distance: float = min(distance * 0.50, recovery_cap) * lie_quality
		var recovery_target: Vector3 = _find_playable_target(state, state.ball_position + direction * recovery_distance, direction, lateral)
		var rough_advance: Dictionary = _option_with_club("ADVANCE_FROM_ROUGH", golfer, APPROACH, state, recovery_target, 50.0 * lie_quality, _lie_risk(18.0, state), false, _safe_success_chance(80.0, lie_quality))
		var advance_remaining: float = recovery_target.distance_to(state.hole_position)
		var rough_setup: Dictionary = _next_shot_setup(golfer, "ROUGH", lie_quality, advance_remaining)
		rough_advance["next_shot_green_reachable"] = rough_setup["reachable"]
		rough_advance["next_shot_quality"] = rough_setup["quality"]
		options.append(rough_advance)

		var fairway_target: Vector3 = _find_fairway_recovery_target(state, direction)
		if fairway_target != state.ball_position:
			var fairway_remaining: float = fairway_target.distance_to(state.hole_position)
			var fairway_setup: Dictionary = _next_shot_setup(golfer, "FAIRWAY", 0.95, fairway_remaining)
			var recovery_reward: float = 30.0
			if not rough_setup["reachable"]:
				recovery_reward += 12.0
			recovery_reward += max(0.0, float(fairway_setup["quality"]) - float(rough_setup["quality"])) * 0.20
			var fairway_recovery: Dictionary = _option_with_club("RECOVER_TO_FAIRWAY", golfer, APPROACH, state, fairway_target, recovery_reward, _lie_risk(12.0, state), false, _safe_success_chance(90.0, lie_quality))
			fairway_recovery["lie_improvement"] = max(0.0, 1.0 - lie_quality)
			fairway_recovery["expected_surface"] = "FAIRWAY"
			fairway_recovery["advance_sets_up_green"] = rough_setup["reachable"]
			fairway_recovery["next_shot_green_reachable"] = fairway_setup["reachable"]
			fairway_recovery["next_shot_quality"] = fairway_setup["quality"]
			options.append(fairway_recovery)

	return options


func _named_club_distance(club_id: String, golfer: Node, surface: String, lie_quality: float, fallback: float) -> float:
	var club: Dictionary = bag.get_club(club_id)
	if club.is_empty() or not surface in club.get("allowed_surfaces", []):
		return fallback * lie_quality
	return bag.effective_carry(club, golfer, surface, lie_quality)


func _next_shot_setup(golfer: Node, surface: String, lie_quality: float, remaining_distance: float) -> Dictionary:
	var best_quality: float = 0.0
	var reachable: bool = false
	for club in bag.clubs_for_surface(surface):
		if int(club["shot_type"]) == PUTT:
			continue
		var carry: float = bag.effective_carry(club, golfer, surface, lie_quality)
		var ability: float = golfer.get_shot_ability(int(club["shot_type"]))
		var confidence: float = float(golfer.get("confidence")) if golfer.get("confidence") != null else 50.0
		var confidence_blend: float = ability * 0.65 + confidence * 0.35
		var reach_margin: float = carry - remaining_distance
		var reach_quality: float = clamp(50.0 + reach_margin * 4.0, 0.0, 100.0)
		var lie_adjustment: float = 0.0
		if surface == "ROUGH":
			lie_adjustment = -12.0
		elif surface == "FAIRWAY":
			lie_adjustment = 6.0
		var quality: float = clamp(confidence_blend * 0.55 + reach_quality * 0.45 + lie_adjustment, 0.0, 100.0)
		best_quality = max(best_quality, quality)
		if carry >= remaining_distance and quality >= 45.0:
			reachable = true
	return {"reachable": reachable, "quality": best_quality}


func _find_fairway_recovery_target(state, direction: Vector3) -> Vector3:
	if state.course_context == null:
		return state.ball_position
	var best_target: Vector3 = state.ball_position
	var best_distance: float = INF
	for zone in state.course_context.zones:
		if state.course_context.surface_name(zone["surface"]) != "FAIRWAY":
			continue
		var center: Vector3 = zone["center"]
		var half_size: Vector2 = zone["half_size"]
		var preferred: Vector3 = state.ball_position + direction * 8.0
		var margin: float = 2.0
		var candidate: Vector3 = Vector3(clamp(preferred.x, center.x - half_size.x + margin, center.x + half_size.x - margin), state.ball_position.y, clamp(preferred.z, center.z - half_size.y + margin, center.z + half_size.y - margin))
		if _is_water(state, candidate):
			continue
		if state.course_context.surface_name(state.course_context.surface_at(candidate)) != "FAIRWAY":
			continue
		var candidate_distance: float = state.ball_position.distance_to(candidate)
		if candidate_distance < best_distance:
			best_distance = candidate_distance
			best_target = candidate
	return best_target


func _option_with_club(name: String, golfer: Node, shot_type: int, state, target: Vector3, reward: float, risk: float, is_aggressive: bool, success_chance: float) -> Dictionary:
	var desired_distance: float = state.ball_position.distance_to(target)
	var club: Dictionary = bag.best_distance_match(golfer, state.surface_name(), state.current_lie_quality, desired_distance)
	return _option(name, shot_type, target, reward, risk, is_aggressive, success_chance, club)


func _clubbed_direct_option(name: String, golfer: Node, shot_type: int, state, reward: float, risk: float) -> Dictionary:
	return _option_with_club(name, golfer, shot_type, state, state.hole_position, reward, risk, false, 100.0)


func _find_playable_target(state, preferred: Vector3, direction: Vector3, lateral: Vector3) -> Vector3:
	if state.course_context == null or not _is_water(state, preferred):
		return preferred
	for side_offset in [8.0, -8.0, 14.0, -14.0, 20.0, -20.0]:
		var candidate: Vector3 = preferred + lateral * side_offset
		if not _is_water(state, candidate):
			return candidate
	for backoff in [6.0, 12.0, 18.0, 24.0]:
		var candidate: Vector3 = preferred - direction * backoff
		if not _is_water(state, candidate):
			return candidate
	return state.ball_position


func _is_water(state, position: Vector3) -> bool:
	if state.course_context == null:
		return false
	var surface: int = state.course_context.surface_at(position)
	return state.course_context.surface_name(surface) == "WATER"


func _bunker_options(golfer: Node, state, distance: float) -> Array:
	var lie_quality: float = state.current_lie_quality
	if distance <= 28.0:
		return [_clubbed_direct_option("SPLASH_OUT", golfer, SHORT_GAME, state, 54.0 * lie_quality, _lie_risk(14.0, state)), _clubbed_direct_option("SAFE_BUNKER_EXIT", golfer, SHORT_GAME, state, 45.0 * lie_quality, _lie_risk(5.0, state))]
	var direction: Vector3 = _direction_to_hole(state)
	var lateral: Vector3 = Vector3(-direction.z, 0.0, direction.x)
	var exit_distance: float = min(distance * 0.25, 18.0)
	var exit_target: Vector3 = _find_playable_target(state, state.ball_position + direction * exit_distance, direction, lateral)
	return [_option_with_club("BUNKER_EXIT", golfer, SHORT_GAME, state, exit_target, 42.0 * lie_quality, _lie_risk(8.0, state), false, 72.0)]


func _putt_option(golfer: Node, state) -> Dictionary:
	return _option_with_club("PUTT", golfer, PUTT, state, state.hole_position, 80.0, 5.0, false, 100.0)


func _option(name: String, shot_type: int, target_position: Vector3, reward: float, risk: float, is_aggressive: bool, model_success_chance: float, club: Dictionary = {}) -> Dictionary:
	var resolved_shot_type: int = shot_type
	if not club.is_empty():
		resolved_shot_type = int(club.get("shot_type", shot_type))
	return {"name": name, "shot_type": resolved_shot_type, "target_position": target_position, "reward": reward, "risk": risk, "is_aggressive": is_aggressive, "model_success_chance": model_success_chance, "club": club, "club_id": club.get("id", ""), "club_name": club.get("name", "")}


func _direction_to_hole(state) -> Vector3:
	var delta: Vector3 = state.hole_position - state.ball_position
	delta.y = 0.0
	if delta.length() <= 0.001:
		return Vector3.FORWARD
	return delta.normalized()


func _safe_success_chance(base_chance: float, lie_quality: float) -> float:
	return clamp(base_chance - (1.0 - lie_quality) * 45.0, 35.0, 100.0)


func _estimate_club_success(golfer: Node, state, attempted_distance: float, club: Dictionary) -> float:
	if club.is_empty():
		return 50.0
	var effective_distance: float = bag.effective_carry(club, golfer, state.surface_name(), state.current_lie_quality)
	var carry_margin: float = effective_distance - attempted_distance
	var ability: float = golfer.get_shot_ability(int(club["shot_type"]))
	var chance: float = 50.0 + carry_margin * 5.0 + (ability - 50.0) * 0.3
	chance -= (1.0 - state.current_lie_quality) * 25.0
	return clamp(chance, 5.0, 95.0)


func _lie_risk(base_risk: float, state) -> float:
	if state.course_context == null:
		return base_risk
	return clamp(base_risk + state.course_context.risk_modifier(state.current_surface), 0.0, 100.0)


func _estimate_attack_risk(golfer: Node, state, attack_target: Vector3, hazards: Array, club: Dictionary) -> float:
	var attempted_distance: float = state.ball_position.distance_to(attack_target)
	var effective_distance: float = attempted_distance
	if not club.is_empty():
		effective_distance = bag.effective_carry(club, golfer, state.surface_name(), state.current_lie_quality)
	var carry_margin: float = effective_distance - attempted_distance
	var distance_risk: float = clamp(50.0 - carry_margin * 4.0, 5.0, 95.0)
	var hazard_risk: float = 0.0
	for hazard in hazards:
		if not hazard.has("position"):
			continue
		var hazard_position: Vector3 = hazard["position"]
		var radius: float = hazard.get("radius", 6.0)
		if _distance_to_segment(hazard_position, state.ball_position, attack_target) <= radius:
			hazard_risk = max(hazard_risk, float(hazard.get("risk", 75.0)))
	return clamp(max(distance_risk, hazard_risk), 0.0, 100.0)


func _distance_to_segment(point: Vector3, start: Vector3, end: Vector3) -> float:
	var segment: Vector3 = end - start
	var length_squared: float = segment.length_squared()
	if length_squared <= 0.001:
		return point.distance_to(start)
	var t: float = clamp((point - start).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(start + segment * t)
