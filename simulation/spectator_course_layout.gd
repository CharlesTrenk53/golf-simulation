extends RefCounted

# POC-25A: Spectator Course Layout
# ---------------------------------
# Display-only translation from hole-local authoritative course coordinates into
# one shared spectator world. No simulation geometry is modified or recreated.
# Hole spacing is derived from authored geometry plus a visual margin.

var course = null
var gap_yards: float = 40.0
var entries: Dictionary = {}


func configure(course_definition, visual_gap_yards: float = 40.0) -> bool:
	if course_definition == null or course_definition.hole_count() <= 0:
		return false
	if visual_gap_yards < 0.0:
		return false

	course = course_definition
	gap_yards = visual_gap_yards
	entries.clear()
	var cursor_x: float = 0.0

	for hole_number in range(1, course.hole_count() + 1):
		var hole = course.hole_by_number(hole_number)
		if hole == null:
			return false
		var bounds: Rect2 = _hole_bounds(hole)
		if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
			return false
		var offset := Vector3(cursor_x - bounds.position.x, 0.0, -bounds.position.y)
		var world_bounds := Rect2(Vector2(cursor_x, 0.0), bounds.size)
		entries[hole_number] = {
			"hole_number": hole_number,
			"offset": offset,
			"local_bounds": bounds,
			"world_bounds": world_bounds
		}
		cursor_x += bounds.size.x + gap_yards
	return true


func world_position(hole_number: int, course_position: Vector3) -> Vector3:
	return course_position + hole_offset(hole_number)


func course_position(hole_number: int, spectator_position: Vector3) -> Vector3:
	return spectator_position - hole_offset(hole_number)


func hole_offset(hole_number: int) -> Vector3:
	return entries.get(hole_number, {}).get("offset", Vector3.ZERO)


func local_bounds(hole_number: int) -> Rect2:
	return entries.get(hole_number, {}).get("local_bounds", Rect2())


func world_bounds(hole_number: int) -> Rect2:
	return entries.get(hole_number, {}).get("world_bounds", Rect2())


func snapshot() -> Dictionary:
	var holes: Array = []
	var numbers: Array = entries.keys()
	numbers.sort()
	for hole_number in numbers:
		var entry: Dictionary = entries[hole_number]
		holes.append({
			"hole_number": int(hole_number),
			"offset": entry.get("offset", Vector3.ZERO),
			"local_bounds": entry.get("local_bounds", Rect2()),
			"world_bounds": entry.get("world_bounds", Rect2())
		})
	return {
		"course_id": str(course.course_id) if course != null else "",
		"gap_yards": gap_yards,
		"hole_count": holes.size(),
		"holes": holes
	}


func _hole_bounds(hole) -> Rect2:
	var points: Array = []
	for tee_value in hole.tees:
		var tee: Dictionary = tee_value
		var position: Vector3 = tee.get("position", Vector3.ZERO)
		points.append(Vector2(position.x, position.z))
	points.append(Vector2(hole.pin_position.x, hole.pin_position.z))
	_append_polygon_points(points, hole.green_polygon)
	for collection in [hole.surface_regions, hole.hazards, hole.out_of_bounds_regions]:
		for region_value in collection:
			var region: Dictionary = region_value
			_append_polygon_points(points, region.get("polygon", PackedVector2Array()))
	for elevation_value in hole.elevation_points:
		var elevation: Dictionary = elevation_value
		var position: Vector3 = elevation.get("position", Vector3.ZERO)
		points.append(Vector2(position.x, position.z))
	if points.is_empty():
		return Rect2()

	var min_x: float = INF
	var min_z: float = INF
	var max_x: float = -INF
	var max_z: float = -INF
	for point_value in points:
		var point: Vector2 = point_value
		min_x = min(min_x, point.x)
		min_z = min(min_z, point.y)
		max_x = max(max_x, point.x)
		max_z = max(max_z, point.y)
	return Rect2(Vector2(min_x, min_z), Vector2(max_x - min_x, max_z - min_z))


func _append_polygon_points(points: Array, polygon_value) -> void:
	var polygon: PackedVector2Array = polygon_value
	for point in polygon:
		points.append(point)
