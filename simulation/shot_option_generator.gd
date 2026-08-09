extends RefCounted

const DRIVE := 0
const APPROACH := 1
const SHORT_GAME := 2
const PUTT := 3


func generate_options(
	golfer: Node,
	state,
	hazards: Array = []
) -> Array:
	var distance = state.remaining_distance()
	var surface = state.surface_name()
	var lie_quality: float = state.current_lie_quality

	if surface == "GREEN" or distance <= 8.0:
		return [_putt_option(state)]

	if distance <= 25.0:
		return [
			_direct_option("PITCH", SHORT_GAME, state, 68.0 * lie_quality, _lie_risk(12.0, state)),
			_direct_option("SAFE_PITCH", SHORT_GAME, state, 58.0 * lie_quality, _lie_risk(5.0, state))
		]

	var options: Array = []
	var direction = _direction_to_hole(state)

	var layup_distance = min(distance * 0.45, 28.0) * lie_quality
	var bailout_distance = min(distance * 0.60, 38.0) * lie_quality
	var attack_distance = min(distance, golfer.driving_distance * lie_quality)

	options.append(_option(
		"LAYUP",
		APPROACH,
		state.ball_position + direction * layup_distance,
		45.0 * lie_quality,
		_lie_risk(10.0, state),
		false,
		100.0
	))

	var lateral = Vector3(-direction.z, 0.0, direction.x)
	options.append(_option(
		"BAILOUT",
		APPROACH,
		state.ball_position + direction * bailout_distance + lateral * 8.0,
		55.0 * lie_quality,
		_lie_risk(30.0, state),
		false,
		100.0
	))

	var attack_target = state.ball_position + direction * attack_distance
	var attack_risk = _estimate_attack_risk(golfer, state, attack_target, hazards)
	var success_chance = _estimate_success_chance(golfer, attack_distance, lie_quality)

	options.append(_option(
		"ATTACK",
		DRIVE,
		attack_target,
		65.0 * lie_quality,
		_lie_risk(attack_risk, state),
		true,
		success_chance
	))

	return options


func _putt_option(state) -> Dictionary:
	return _option(
		"PUTT",
		PUTT,
		state.hole_position,
		80.0,
		5.0,
		false,
		100.0
	)


func _direct_option(
	name: String,
	shot_type: int,
	state,
	reward: float,
	risk: float
) -> Dictionary:
	return _option(
		name,
		shot_type,
		state.hole_position,
		reward,
		risk,
		false,
		100.0
	)


func _option(
	name: String,
	shot_type: int,
	target_position: Vector3,
	reward: float,
	risk: float,
	is_aggressive: bool,
	model_success_chance: float
) -> Dictionary:
	return {
		"name": name,
		"shot_type": shot_type,
		"target_position": target_position,
		"reward": reward,
		"risk": risk,
		"is_aggressive": is_aggressive,
		"model_success_chance": model_success_chance
	}


func _direction_to_hole(state) -> Vector3:
	var delta = state.hole_position - state.ball_position
	delta.y = 0.0
	if delta.length() <= 0.001:
		return Vector3.FORWARD
	return delta.normalized()


func _estimate_success_chance(
	golfer: Node,
	attempted_distance: float,
	lie_quality: float = 1.0
) -> float:
	var effective_distance = golfer.driving_distance * lie_quality
	var carry_margin = effective_distance - attempted_distance
	var chance = 50.0 + carry_margin * 5.0
	chance += (golfer.driving - 50.0) * 0.3
	chance -= (1.0 - lie_quality) * 25.0
	return clamp(chance, 5.0, 95.0)


func _lie_risk(base_risk: float, state) -> float:
	if state.course_context == null:
		return base_risk
	return clamp(
		base_risk + state.course_context.risk_modifier(state.current_surface),
		0.0,
		100.0
	)


func _estimate_attack_risk(
	golfer: Node,
	state,
	attack_target: Vector3,
	hazards: Array
) -> float:
	var attempted_distance = state.ball_position.distance_to(attack_target)
	var effective_distance = golfer.driving_distance * state.current_lie_quality
	var carry_margin = effective_distance - attempted_distance
	var distance_risk = clamp(50.0 - carry_margin * 4.0, 5.0, 95.0)
	var hazard_risk = 0.0

	for hazard in hazards:
		if not hazard.has("position"):
			continue
		var hazard_position: Vector3 = hazard["position"]
		var radius: float = hazard.get("radius", 6.0)
		var path_distance = _distance_to_segment(
			hazard_position,
			state.ball_position,
			attack_target
		)
		if path_distance <= radius:
			hazard_risk = max(
				hazard_risk,
				float(hazard.get("risk", 75.0))
			)

	return clamp(max(distance_risk, hazard_risk), 0.0, 100.0)


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
