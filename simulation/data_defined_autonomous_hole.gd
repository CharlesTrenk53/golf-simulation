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

const AutonomousHole = preload("res://simulation/autonomous_hole.gd")
const HoleCourseContext = preload("res://simulation/hole_course_context.gd")
const CourseStrategySelector = preload("res://simulation/course_strategy_selector.gd")

var hole_definition = null
var course_context = null
var autonomous = AutonomousHole.new()
var strategy_selector = CourseStrategySelector.new()
var tee_id: String = "default"


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

	# The selector has already produced the execution-compatible option contract.
	# Execution remains the existing stochastic club-flight engine so POC-13 changes
	# decision-making, not the physical meaning of the selected club.
	var result: Dictionary = autonomous._execute_option(golfer, state, chosen, hazards, {})
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
	golfer.record_shot_result(result["outcome"], false)
	return result


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
