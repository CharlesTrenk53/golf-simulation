extends RefCounted

# POC-11C: Data-Defined Autonomous Hole
# --------------------------------------
# Thin integration layer that lets the existing autonomous golfer play directly
# from a HoleDefinition. Geometry remains authoritative in the hole model; this
# wrapper builds only the compatibility inputs still required by AutonomousHole.
# Data-defined course coordinates are literal yards, so both option generation
# and shot execution use the same literal-yard club profile.

const AutonomousHole = preload("res://simulation/autonomous_hole.gd")
const HoleCourseContext = preload("res://simulation/hole_course_context.gd")

var hole_definition = null
var course_context = null
var autonomous = AutonomousHole.new()
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


func play_step(golfer: Node, state) -> Dictionary:
	if state == null:
		return {}
	return autonomous.play_step(golfer, state, _legacy_water_hazards())


func play_hole(golfer: Node, seed_value: int = 1) -> Dictionary:
	if hole_definition == null:
		return {}
	return autonomous.play_hole(
		golfer,
		hole_definition.tee_position(tee_id),
		hole_definition.pin_position,
		_legacy_water_hazards(),
		hole_definition.par,
		seed_value,
		course_context
	)


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
