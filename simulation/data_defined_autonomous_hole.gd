extends RefCounted

# POC-11C: Data-Defined Autonomous Hole
# --------------------------------------
# Thin integration layer that lets the existing autonomous golfer play directly
# from a HoleDefinition. Geometry remains authoritative in the hole model; this
# wrapper builds only the compatibility inputs still required by AutonomousHole.
# Data-defined course coordinates are literal yards, so both option generation
# and shot execution use the same literal-yard club profile.
#
# POC-13D added the course-strategy selection seam.
# POC-13E routes live data-defined play through that selected club/target while
# preserving the legacy AutonomousHole path for greens and as a safety fallback.
# POC-14F now executes the selected shot intent rather than silently reverting to
# a generic stock-flight engine after the HOW decision has been made.

const AutonomousHole = preload("res://simulation/autonomous_hole.gd")
const HoleCourseContext = preload("res://simulation/hole_course_context.gd")
const CourseStrategySelector = preload("res://simulation/course_strategy_selector.gd")
const ShotIntentExecutionBridge = preload("res://simulation/shot_intent_execution_bridge.gd")

var hole_definition = null
var course_context = null
var autonomous = AutonomousHole.new()
var strategy_selector = CourseStrategySelector.new()
var intent_execution = ShotIntentExecutionBridge.new()
var tee_id: String = "default"
var _seed_base: int = 1


func _init(definition = null, selected_tee_id: String = "default") -> void:
	hole_definition = definition
	tee_id = selected_tee_id
	course_context = HoleCourseContext.new(definition) if definition != null else null
	# AutonomousHole owns two GolfBag instances: one in the option generator and
	# one in the executor. They must agree or the selected club and actual flight
	# distance can diverge.
	autonomous.option_generator.bag.use_literal_yardages(true)
	autonomous.bag.use_literal_yardages(true)
	strategy_selector.use_literal_yardages(true)


func create_state(seed_value: int = 1):
	if hole_definition == null:
		return null
	_seed_base = seed_value
	return autonomous.create_state(
		hole_definition.tee_position(tee_id),
		hole_definition.pin_position,
		hole_definition.par,
		seed_value,
		course_context
	)


func choose_course_strategy(golfer: Node, state) -> Dictionary:
	if golfer == null or state == null:
		return {"chosen": {}, "evaluated": []}
	return strategy_selector.choose(golfer, state)


func play_step(golfer: Node, state) -> Dictionary:
	if golfer == null or state == null or not state.can_continue():
		return {}

	# Putting and very short green play still use the proven legacy subsystem.
	# Everywhere else on a data-defined course, club choice now emerges from the
	# expected-strokes / course-management selector.
	if state.surface_name() == "GREEN" or state.remaining_distance() <= 8.0:
		return autonomous.play_step(golfer, state, _legacy_water_hazards())

	var selection: Dictionary = choose_course_strategy(golfer, state)
	var chosen: Dictionary = selection.get("chosen", {})
	if chosen.is_empty():
		return autonomous.play_step(golfer, state, _legacy_water_hazards())

	return _execute_course_strategy_choice(golfer, state, chosen, selection.get("evaluated", []))


func _execute_course_strategy_choice(golfer: Node, state, chosen: Dictionary, evaluated: Array) -> Dictionary:
	var surface_before: String = state.surface_name()
	var lie_quality_before: float = state.current_lie_quality
	var hazards: Array = _legacy_water_hazards()

	# POC-14F: if the selector supplied a concrete shot intent plus its predicted
	# flight and golfer proficiency, that exact plan must drive the physical shot.
	# Fallback preserves the POC-13 execution contract for any legacy caller.
	var result: Dictionary
	var predicted: Dictionary = chosen.get("chosen_predicted_flight", {})
	var proficiency: Dictionary = chosen.get("chosen_proficiency", {})
	if not predicted.is_empty() and not proficiency.is_empty():
		result = _execute_selected_intent(state, chosen, predicted, proficiency)
	else:
		result = autonomous._execute_option(golfer, state, chosen, hazards, {})

	result["selected_option"] = chosen.duplicate(true)
	result["surface_before"] = surface_before
	result["lie_quality_before"] = lie_quality_before
	result["decision_system"] = "EXPECTED_STROKES_COURSE_MANAGEMENT"
	result["course_management"] = float(chosen.get("course_management", 50.0))
	result["objective_expected_strokes"] = float(chosen.get("expected_strokes_to_hole", INF))
	result["perceived_expected_strokes"] = float(chosen.get("perceived_expected_strokes_to_hole", INF))
	result["calibration_gap"] = float(chosen.get("calibration_gap", 0.0))
	result["strategy_candidates"] = evaluated.duplicate(true)

	if state.course_context != null:
		var landing_surface = state.course_context.surface_at(result["landing_position"])
		if state.course_context.surface_name(landing_surface) == "WATER":
			result["outcome"] = "WATER"
			result["penalty_strokes"] = max(int(result["penalty_strokes"]), 1)

	var next_position: Vector3 = result["landing_position"]
	if result["outcome"] == "WATER":
		var entry_point = autonomous._find_water_entry_point(state, result["start_position"], result["landing_position"])
		next_position = autonomous._lateral_water_relief_position(state, entry_point, result["start_position"])
		result["water_entry_point"] = entry_point
		result["relief_position"] = next_position
	else:
		result["water_entry_point"] = result["landing_position"]
		result["relief_position"] = result["landing_position"]

	state.advance_to(next_position, result["outcome"], result["penalty_strokes"])
	result["surface_after"] = state.surface_name()
	result["lie_quality_after"] = state.current_lie_quality
	var execution_assessment: Dictionary = autonomous._assess_execution(result)
	result["execution_quality"] = execution_assessment["quality"]
	result["execution_score"] = execution_assessment["score"]
	result["execution_miss_distance"] = execution_assessment["miss_distance"]
	result["execution_reason"] = execution_assessment["reason"]

	autonomous.shot_history.append(result)
	var was_aggressive: bool = bool(chosen.get("is_aggressive", false))
	result["was_aggressive"] = was_aggressive
	golfer.record_shot_result(result["outcome"], was_aggressive)
	return result


func _execute_selected_intent(state, chosen: Dictionary, predicted: Dictionary, proficiency: Dictionary) -> Dictionary:
	var start: Vector3 = state.ball_position
	var target: Vector3 = chosen.get("target_position", chosen.get("target", state.hole_position))
	var shot_seed: int = _seed_base * 1009 + (state.strokes + 1) * 7919
	var realized: Dictionary = intent_execution.execute(start, target, predicted, proficiency, shot_seed)
	var landing: Vector3 = realized.get("landing_position", target)
	var intended_distance: float = start.distance_to(target)
	var planned_carry: float = float(predicted.get("carry_yards", intended_distance))
	var predicted_dispersion: float = float(predicted.get("dispersion_yards", chosen.get("dispersion", 1.0)))
	var proficiency_dispersion: float = float(proficiency.get("expected_dispersion_multiplier", 1.0))

	return {
		"shot_number": state.strokes + 1,
		"option": chosen.get("name", "EMERGENT_INTENT"),
		"shot_type": int(chosen.get("shot_type", 1)),
		"club_id": chosen.get("club_id", ""),
		"club_name": chosen.get("club_name", ""),
		"club_effective_carry": planned_carry,
		"club_dispersion": max(0.25, predicted_dispersion * proficiency_dispersion),
		"start_position": start,
		"target_position": target,
		"landing_position": landing,
		"intended_distance": intended_distance,
		"outcome": "SUCCESS",
		"penalty_strokes": 0,
		"execution_roll": -1.0,
		"remaining_after_shot": landing.distance_to(state.hole_position),
		"lateral_error": float(realized.get("target_line_lateral_yards", 0.0)),
		"distance_error": float(realized.get("actual_total_yards", intended_distance)) - intended_distance,
		"shot_intent": chosen.get("chosen_intent", {}).duplicate(true),
		"predicted_flight": predicted.duplicate(true),
		"shotmaking_proficiency": proficiency.duplicate(true),
		"shot_execution": realized.duplicate(true),
		"intent_signature": str(realized.get("intent_signature", "")),
		"execution_seed": shot_seed
	}


func play_hole(golfer: Node, seed_value: int = 1) -> Dictionary:
	if hole_definition == null:
		return {}
	var state = create_state(seed_value)
	while state != null and state.can_continue():
		var result: Dictionary = play_step(golfer, state)
		if result.is_empty():
			break
	return {
		"finished": state != null and state.finished,
		"strokes": state.strokes if state != null else 0,
		"par": state.par if state != null else hole_definition.par,
		"remaining_distance": state.remaining_distance() if state != null else INF,
		"final_position": state.ball_position if state != null else Vector3.ZERO,
		"final_surface": state.surface_name() if state != null else "UNKNOWN",
		"history": autonomous.shot_history.duplicate(true)
	}


func course_snapshot(position: Vector3) -> Dictionary:
	if course_context == null or course_context.spatial_query == null:
		return {}
	return course_context.spatial_query.query_position(position)


func _legacy_water_hazards() -> Array:
	var result: Array = []
	if hole_definition == null:
		return result
	for hazard in hole_definition.hazards:
		if str(hazard.get("type", "")).to_upper() != "WATER":
			continue
		var polygon: PackedVector2Array = hazard.get("polygon", PackedVector2Array())
		if polygon.is_empty():
			continue
		var center_2d: Vector2 = Vector2.ZERO
		for point in polygon:
			center_2d += point
		center_2d /= float(polygon.size())
		var radius: float = 0.0
		for point in polygon:
			radius = max(radius, center_2d.distance_to(point))
		result.append({
			"id": str(hazard.get("id", "water")),
			"position": Vector3(center_2d.x, 0.0, center_2d.y),
			"radius": radius,
			"risk": 90.0,
			"source_region": hazard
		})
	return result
