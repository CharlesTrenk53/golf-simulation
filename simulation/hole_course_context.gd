extends RefCounted

# POC-11C: Hole Course Context Adapter
# -------------------------------------
# Compatibility bridge between the data-defined HoleDefinition/HoleSpatialQuery
# architecture and the existing CourseState / autonomous golfer systems.
# Course facts remain authoritative in HoleDefinition; this object only adapts
# them to the legacy course-context interface while POC-11 integration proceeds.

const HoleSpatialQuery = preload("res://simulation/hole_spatial_query.gd")

enum Surface {
	TEE,
	FAIRWAY,
	ROUGH,
	BUNKER,
	GREEN,
	WATER
}

var hole_definition = null
var spatial_query = null
var explicit_hole_out_required: bool = true
# Kept for legacy callers that inspect rectangular zones. Polygon-defined holes
# intentionally do not synthesize fake rectangles.
var zones: Array = []


func _init(definition = null) -> void:
	hole_definition = definition
	spatial_query = HoleSpatialQuery.new(definition) if definition != null else null


func surface_at(position: Vector3) -> int:
	if spatial_query == null:
		return Surface.ROUGH
	return _surface_from_name(spatial_query.surface_at(position))


func surface_name(surface: int) -> String:
	match surface:
		Surface.TEE: return "TEE"
		Surface.FAIRWAY: return "FAIRWAY"
		Surface.ROUGH: return "ROUGH"
		Surface.BUNKER: return "BUNKER"
		Surface.GREEN: return "GREEN"
		Surface.WATER: return "WATER"
		_: return "ROUGH"


func lie_quality(surface: int) -> float:
	match surface:
		Surface.TEE: return 1.00
		Surface.FAIRWAY: return 0.95
		Surface.ROUGH: return 0.72
		Surface.BUNKER: return 0.58
		Surface.GREEN: return 1.00
		Surface.WATER: return 0.0
		_: return 0.72


func risk_modifier(surface: int) -> float:
	match surface:
		Surface.TEE: return 0.0
		Surface.FAIRWAY: return 0.0
		Surface.ROUGH: return 15.0
		Surface.BUNKER: return 28.0
		Surface.GREEN: return -5.0
		Surface.WATER: return 100.0
		_: return 15.0


func hazards_in_corridor(start: Vector3, end: Vector3, half_width: float = 0.0) -> Array:
	if spatial_query == null:
		return []
	return spatial_query.hazards_in_corridor(start, end, half_width)


func is_out_of_bounds(position: Vector3) -> bool:
	return spatial_query != null and spatial_query.is_out_of_bounds(position)


func elevation_near(position: Vector3) -> float:
	if spatial_query == null:
		return position.y
	return spatial_query.elevation_near(position)


func _surface_from_name(value: String) -> int:
	match value.to_upper():
		"TEE": return Surface.TEE
		"FAIRWAY": return Surface.FAIRWAY
		"BUNKER": return Surface.BUNKER
		"GREEN": return Surface.GREEN
		"WATER": return Surface.WATER
		_: return Surface.ROUGH
