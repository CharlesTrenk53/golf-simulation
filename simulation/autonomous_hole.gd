extends RefCounted

const CourseState = preload("res://simulation/course_state.gd")
const ShotOptionGenerator = preload("res://simulation/shot_option_generator.gd")
const GolfBag = preload("res://simulation/golf_bag.gd")
const ShotAssessmentPipeline = preload("res://simulation/shot_assessment_pipeline.gd")
const DecisionQualityEvaluator = preload("res://simulation/decision_quality_evaluator.gd")
const PuttingPipeline = preload("res://simulation/putting_pipeline.gd")

const WATER_BOUNDARY_STEPS := 80
const LATERAL_RELIEF_DISTANCE := 4.0
const PUTT := 3
const FEET_PER_YARD := 3.0

var option_generator = ShotOptionGenerator.new()
var bag = GolfBag.new()
var assessment_pipeline = ShotAssessmentPipeline.new()
var decision_evaluator = DecisionQualityEvaluator.new()
var putting_pipeline = PuttingPipeline.new()
var shot_history: Array = []

func create_state(start_position: Vector3, hole_position: Vector3, par: int = 4, seed_value: int = 1, course_context = null):
	seed(seed_value)
	shot_history.clear()
	return CourseState.new(start_position, hole_position, par, course_context)

func play_step(golfer: Node, state, hazards: Array = []) -> Dictionary:
	if not state.can_continue(): return {}
	var surface_before = state.surface_name()
	var lie_quality_before = state.current_lie_quality
	var generated_options = option_generator.generate_options(golfer, state, hazards)
	if generated_options.is_empty(): return {}
	var options = assessment_pipeline.assess_options(golfer, state, generated_options, hazards)
	var chosen = golfer.choose_best_option(options)
	var decision_assessment = decision_evaluator.evaluate(golfer, chosen, options)
	var commitment = assessment_pipeline.prepare_execution(golfer, chosen, float(decision_assessment["gap"]))
	var result = _execute_option(golfer, state, chosen, hazards, commitment)
	result["selected_option"] = chosen
	result["surface_before"] = surface_before
	result["lie_quality_before"] = lie_quality_before
	result["decision_quality"] = decision_assessment["quality"]
	result["decision_score"] = decision_assessment["score"]
	result["decision_best_score"] = decision_assessment["best_score"]
	result["decision_gap"] = decision_assessment["gap"]
	result["decision_best_option"] = decision_assessment["best_option"]
	result["decision_reason"] = decision_assessment["reason"]
	result["decision_chosen_breakdown"] = decision_assessment.get("chosen_breakdown", {}).duplicate(true)
	result["decision_best_breakdown"] = decision_assessment.get("best_breakdown", {}).duplicate(true)
	result["decision_option_breakdowns"] = decision_assessment.get("option_breakdowns", []).duplicate(true)
	result["commitment_score"] = commitment["score"]
	result["commitment_quality"] = commitment["label"]
	result["assessment"] = chosen.get("assessment", {}).duplicate(true)

	if state.course_context != null and int(result["shot_type"]) != PUTT:
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
	var hole_radius: float = 0.01 if int(result["shot_type"]) == PUTT else 2.0
	state.advance_to(next_position, result["outcome"], result["penalty_strokes"], hole_radius)
	result["surface_after"] = state.surface_name()
	result["lie_quality_after"] = state.current_lie_quality
	var execution_assessment = _assess_execution(result)
	result["execution_quality"] = execution_assessment["quality"]
	result["execution_score"] = execution_assessment["score"]
	result["execution_miss_distance"] = execution_assessment["miss_distance"]
	result["execution_reason"] = execution_assessment["reason"]
	assessment_pipeline.record_result(chosen, result)
	shot_history.append(result)
	golfer.record_shot_result(result["outcome"], chosen["is_aggressive"])
	return result

func _assess_execution(result: Dictionary) -> Dictionary:
	if int(result.get("shot_type", -1)) == PUTT and result.has("putting"):
		var roll: Dictionary = result["putting"].get("roll", {})
		var miss_feet: float = float(roll.get("finish_distance_from_hole_feet", 0.0))
		var holed: bool = bool(roll.get("holed", false))
		var score: float = 100.0 if holed else clampf(100.0 - miss_feet * 12.0, 0.0, 95.0)
		var quality: String = "GOOD"
		var reason: String = "Putt was holed"
		if not holed and miss_feet > 6.0:
			quality = "POOR"
			reason = "Putt finished a difficult distance from the hole"
		elif not holed and miss_feet > 3.0:
			quality = "ACCEPTABLE"
			reason = "Putt missed but left a manageable remaining putt"
		elif not holed:
			reason = "Putt missed but finished close to the hole"
		return {"quality": quality, "score": score, "miss_distance": miss_feet / FEET_PER_YARD, "reason": reason}
	var miss_distance = result["target_position"].distance_to(result["landing_position"])
	var dispersion = max(float(result.get("club_dispersion", 1.0)), 0.25)
	var normalized_miss = miss_distance / dispersion
	var score = clamp(100.0 - normalized_miss * 35.0, 0.0, 100.0)
	var quality = "GOOD"
	var reason = "Ball finished close to the intended target relative to expected dispersion"
	if result["outcome"] == "WATER":
		quality = "POOR"; score = min(score, 20.0); reason = "Execution produced a penalty-area outcome"
	elif normalized_miss > 1.25:
		quality = "POOR"; reason = "Miss was large relative to the selected club's expected dispersion"
	elif normalized_miss > 0.65:
		quality = "ACCEPTABLE"; reason = "Miss was noticeable but within a plausible execution range"
	return {"quality": quality, "score": score, "miss_distance": miss_distance, "reason": reason}

func _find_water_entry_point(state, start: Vector3, water_position: Vector3) -> Vector3:
	if state.course_context == null: return water_position
	var last_dry = start
	for step in range(1, WATER_BOUNDARY_STEPS + 1):
		var sample = start.lerp(water_position, float(step) / float(WATER_BOUNDARY_STEPS))
		if _position_is_water(state, sample):
			var dry = last_dry; var wet = sample
			for _refine in range(10):
				var midpoint = dry.lerp(wet, 0.5)
				if _position_is_water(state, midpoint): wet = midpoint
				else: dry = midpoint
			return dry
		last_dry = sample
	return water_position

func _lateral_water_relief_position(state, entry_point: Vector3, previous_position: Vector3) -> Vector3:
	if state.course_context == null: return previous_position
	var toward_hole = state.hole_position - entry_point; toward_hole.y = 0.0
	if toward_hole.length() <= 0.001: toward_hole = Vector3.FORWARD
	else: toward_hole = toward_hole.normalized()
	var lateral = Vector3(-toward_hole.z, 0.0, toward_hole.x)
	var reference_distance = entry_point.distance_to(state.hole_position)
	for distance in [LATERAL_RELIEF_DISTANCE, 3.0, 2.0, 1.0]:
		for side in [1.0, -1.0]:
			var candidate = entry_point + lateral * distance * side; candidate.y = previous_position.y
			if not _position_is_water(state, candidate) and candidate.distance_to(state.hole_position) >= reference_distance - 0.01: return candidate
	for back_distance in [1.0, 2.0, 3.0, LATERAL_RELIEF_DISTANCE]:
		var candidate = entry_point - toward_hole * back_distance; candidate.y = previous_position.y
		if not _position_is_water(state, candidate) and candidate.distance_to(state.hole_position) >= reference_distance - 0.01: return candidate
	return previous_position

func _position_is_water(state, position: Vector3) -> bool:
	return state.course_context.surface_name(state.course_context.surface_at(position)) == "WATER"

func play_hole(golfer: Node, start_position: Vector3, hole_position: Vector3, hazards: Array = [], par: int = 4, seed_value: int = 1, course_context = null) -> Dictionary:
	var state = create_state(start_position, hole_position, par, seed_value, course_context)
	while state.can_continue():
		var result = play_step(golfer, state, hazards)
		if result.is_empty(): break
	return {"finished": state.finished, "strokes": state.strokes, "par": state.par, "remaining_distance": state.remaining_distance(), "final_position": state.ball_position, "final_surface": state.surface_name(), "history": shot_history.duplicate(true)}

func _execute_option(golfer: Node, state, option: Dictionary, hazards: Array, commitment: Dictionary = {}) -> Dictionary:
	var shot_type: int = option["shot_type"]
	if shot_type == PUTT:
		return _execute_putt(golfer, state, option)
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
	var assessment: Dictionary = option.get("assessment", {})
	var performance: Dictionary = assessment.get("performance", {})
	effective_carry *= float(performance.get("carry_factor", 1.0))
	dispersion *= float(performance.get("dispersion_factor", 1.0))
	effective_carry *= float(commitment.get("carry_factor", 1.0))
	dispersion *= float(commitment.get("dispersion_factor", 1.0))
	var direction = target - start; direction.y = 0.0
	if direction.length() <= 0.001: direction = Vector3.FORWARD
	else: direction = direction.normalized()
	var lateral = Vector3(-direction.z, 0.0, direction.x)
	var directional_bias = float(performance.get("directional_bias", 0.0))
	var lateral_error = randf_range(-dispersion, dispersion) + directional_bias * 0.15
	var distance_error = randf_range(-dispersion * 0.7, dispersion * 0.7)
	var landing = start + direction * min(intended_distance, effective_carry) + lateral * lateral_error + direction * distance_error
	landing.y = start.y
	var outcome = "SUCCESS"; var penalty_strokes = 0; var execution_roll = -1.0
	if option["is_aggressive"]:
		execution_roll = randf_range(0.0, 100.0)
		if execution_roll > float(option["model_success_chance"]):
			var hazard = _closest_intersecting_hazard(start, target, hazards)
			if not hazard.is_empty(): landing = hazard["position"]; landing.y = start.y; outcome = "WATER"; penalty_strokes = 1
	return {"shot_number": state.strokes + 1, "option": option["name"], "shot_type": shot_type, "club_id": option.get("club_id", ""), "club_name": option.get("club_name", ""), "club_effective_carry": effective_carry, "club_dispersion": dispersion, "start_position": start, "target_position": target, "landing_position": landing, "intended_distance": intended_distance, "outcome": outcome, "penalty_strokes": penalty_strokes, "execution_roll": execution_roll, "remaining_after_shot": landing.distance_to(state.hole_position), "lateral_error": lateral_error, "distance_error": distance_error}

func _execute_putt(golfer: Node, state, option: Dictionary) -> Dictionary:
	var start: Vector3 = state.ball_position
	var target: Vector3 = state.hole_position
	var direction: Vector3 = target - start
	direction.y = 0.0
	var distance_yards: float = direction.length()
	if distance_yards <= 0.0001:
		direction = Vector3.FORWARD
	else:
		direction = direction.normalized()
	var lateral: Vector3 = Vector3(-direction.z, 0.0, direction.x)
	var slope_across: float = float(option.get("slope_across_percent", 0.0))
	var slope_along: float = float(option.get("slope_along_percent", 0.0))
	var green_speed: float = float(option.get("green_speed", 10.0))
	var putting: Dictionary = putting_pipeline.resolve(
		golfer,
		distance_yards * FEET_PER_YARD,
		int(randi()),
		slope_across,
		slope_along,
		green_speed
	)
	var roll: Dictionary = putting["roll"]
	var holed: bool = bool(putting["holed"])
	var rolled_yards: float = float(putting["rolled_distance_feet"]) / FEET_PER_YARD
	var lateral_yards: float = float(putting["final_lateral_feet"]) / FEET_PER_YARD
	var landing: Vector3
	if holed:
		landing = target
	else:
		landing = start + direction * rolled_yards + lateral * lateral_yards
		landing.y = start.y
	var outcome: String = "HOLED" if holed else "SUCCESS"
	return {
		"shot_number": state.strokes + 1,
		"option": option["name"],
		"shot_type": PUTT,
		"club_id": option.get("club_id", "PUTTER"),
		"club_name": option.get("club_name", "Putter"),
		"club_effective_carry": distance_yards,
		"club_dispersion": 0.25,
		"start_position": start,
		"target_position": target,
		"landing_position": landing,
		"intended_distance": distance_yards,
		"outcome": outcome,
		"penalty_strokes": 0,
		"execution_roll": -1.0,
		"remaining_after_shot": landing.distance_to(target),
		"lateral_error": lateral_yards,
		"distance_error": rolled_yards - distance_yards,
		"putting": putting,
		"putting_strategy": str(putting["strategy"].get("strategy", "NEUTRAL")),
		"putting_holed": holed,
		"putting_finish_distance_feet": float(roll.get("finish_distance_from_hole_feet", 0.0))
	}

func _closest_intersecting_hazard(start: Vector3, end: Vector3, hazards: Array) -> Dictionary:
	var best: Dictionary = {}; var best_distance = INF
	for hazard in hazards:
		if not hazard.has("position"): continue
		var position: Vector3 = hazard["position"]; var radius: float = hazard.get("radius", 6.0)
		if _distance_to_segment(position, start, end) <= radius:
			var from_start = start.distance_to(position)
			if from_start < best_distance: best_distance = from_start; best = hazard
	return best

func _distance_to_segment(point: Vector3, start: Vector3, end: Vector3) -> float:
	var segment = end - start; var length_squared = segment.length_squared()
	if length_squared <= 0.001: return point.distance_to(start)
	var t = clamp((point - start).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(start + segment * t)

func set_physical_condition(values: Dictionary) -> void:
	assessment_pipeline.set_physical_condition(values)

func set_mental_state(values: Dictionary) -> void:
	assessment_pipeline.set_mental_state(values)

func set_strategic_context(values: Dictionary) -> void:
	assessment_pipeline.set_strategic_context(values)
