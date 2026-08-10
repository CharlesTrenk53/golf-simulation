extends RefCounted

# POC-11B: Spatial Querying
# -------------------------
# Reads a HoleDefinition and answers golfer-independent spatial questions.
# This layer does not make strategic decisions; it exposes course facts that
# later option-generation and decision systems can consume.

const DEFAULT_SURFACE := "ROUGH"
const GEOMETRY_EPSILON := 0.000001

var hole_definition = null


func _init(definition = null) -> void:
	hole_definition = definition


func distance_to_pin(position: Vector3) -> float:
	if hole_definition == null:
		return 0.0
	return _flatten(position).distance_to(_flatten(hole_definition.pin_position))


func surface_at(position: Vector3) -> String:
	if hole_definition == null:
		return DEFAULT_SURFACE
	var point := Vector2(position.x, position.z)

	# Hazards and the putting green override broader fairway/tee regions.
	for hazard in hole_definition.hazards:
		if _point_in_region(point, hazard):
			return str(hazard.get("type", DEFAULT_SURFACE))

	if Geometry2D.is_point_in_polygon(point, hole_definition.green_polygon):
		return "GREEN"

	# Later surface regions have precedence, matching the legacy CourseContext
	# behavior and allowing small regions to be layered over broad ones.
	for i in range(hole_definition.surface_regions.size() - 1, -1, -1):
		var region: Dictionary = hole_definition.surface_regions[i]
		if _point_in_region(point, region):
			return str(region.get("surface", DEFAULT_SURFACE))

	return DEFAULT_SURFACE


func is_out_of_bounds(position: Vector3) -> bool:
	if hole_definition == null:
		return false
	var point := Vector2(position.x, position.z)
	for region in hole_definition.out_of_bounds_regions:
		if _point_in_region(point, region):
			return true
	return false


func out_of_bounds_region_at(position: Vector3) -> Dictionary:
	if hole_definition == null:
		return {}
	var point := Vector2(position.x, position.z)
	for region in hole_definition.out_of_bounds_regions:
		if _point_in_region(point, region):
			return region
	return {}


func hazard_at(position: Vector3) -> Dictionary:
	if hole_definition == null:
		return {}
	var point := Vector2(position.x, position.z)
	for hazard in hole_definition.hazards:
		if _point_in_region(point, hazard):
			return hazard
	return {}


func hazards_in_corridor(start: Vector3, end: Vector3, half_width: float = 0.0) -> Array:
	var result: Array = []
	if hole_definition == null:
		return result
	var a := Vector2(start.x, start.z)
	var b := Vector2(end.x, end.z)
	for hazard in hole_definition.hazards:
		var polygon: PackedVector2Array = hazard.get("polygon", PackedVector2Array())
		if _segment_intersects_polygon(a, b, polygon, max(half_width, 0.0)):
			result.append(hazard)
	return result


func elevation_near(position: Vector3) -> float:
	if hole_definition == null or hole_definition.elevation_points.is_empty():
		return position.y
	var best_distance := INF
	var best_elevation := position.y
	for sample in hole_definition.elevation_points:
		var sample_position: Vector3 = sample.get("position", Vector3.ZERO)
		var distance := _flatten(position).distance_to(_flatten(sample_position))
		if distance < best_distance:
			best_distance = distance
			best_elevation = float(sample.get("elevation", sample_position.y))
	return best_elevation


func query_position(position: Vector3) -> Dictionary:
	return {
		"position": position,
		"surface": surface_at(position),
		"distance_to_pin": distance_to_pin(position),
		"out_of_bounds": is_out_of_bounds(position),
		"hazard": hazard_at(position).duplicate(true),
		"elevation": elevation_near(position)
	}


func _point_in_region(point: Vector2, region: Dictionary) -> bool:
	var polygon: PackedVector2Array = region.get("polygon", PackedVector2Array())
	return polygon.size() >= 3 and Geometry2D.is_point_in_polygon(point, polygon)


func _segment_intersects_polygon(a: Vector2, b: Vector2, polygon: PackedVector2Array, half_width: float) -> bool:
	if polygon.size() < 3:
		return false
	if Geometry2D.is_point_in_polygon(a, polygon) or Geometry2D.is_point_in_polygon(b, polygon):
		return true

	for i in range(polygon.size()):
		var edge_a := polygon[i]
		var edge_b := polygon[(i + 1) % polygon.size()]
		if _segments_intersect(a, b, edge_a, edge_b):
			return true

	if half_width <= 0.0:
		return false

	# A practical corridor-width approximation for option generation: a hazard
	# counts when any polygon vertex lies within the requested distance of the
	# intended shot centerline.
	for vertex in polygon:
		if _distance_to_segment(vertex, a, b) <= half_width:
			return true
	return false


func _segments_intersect(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	var r := b - a
	var s := d - c
	var denominator := _cross_2d(r, s)
	var c_minus_a := c - a

	if abs(denominator) <= GEOMETRY_EPSILON:
		# Parallel non-collinear segments cannot intersect. For collinear
		# segments, test endpoint distance to the opposite segment.
		if abs(_cross_2d(c_minus_a, r)) > GEOMETRY_EPSILON:
			return false
		return (
			_distance_to_segment(a, c, d) <= GEOMETRY_EPSILON
			or _distance_to_segment(b, c, d) <= GEOMETRY_EPSILON
			or _distance_to_segment(c, a, b) <= GEOMETRY_EPSILON
			or _distance_to_segment(d, a, b) <= GEOMETRY_EPSILON
		)

	var t := _cross_2d(c_minus_a, s) / denominator
	var u := _cross_2d(c_minus_a, r) / denominator
	return t >= -GEOMETRY_EPSILON and t <= 1.0 + GEOMETRY_EPSILON and u >= -GEOMETRY_EPSILON and u <= 1.0 + GEOMETRY_EPSILON


func _cross_2d(a: Vector2, b: Vector2) -> float:
	return a.x * b.y - a.y * b.x


func _distance_to_segment(point: Vector2, start: Vector2, end: Vector2) -> float:
	var segment := end - start
	var length_squared := segment.length_squared()
	if length_squared <= GEOMETRY_EPSILON:
		return point.distance_to(start)
	var t := clamp((point - start).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(start + segment * t)


func _flatten(position: Vector3) -> Vector2:
	return Vector2(position.x, position.z)
