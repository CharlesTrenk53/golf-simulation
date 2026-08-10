extends RefCounted

# POC-11A: Hole Definition
# ------------------------
# Authoritative, golfer-independent description of one golf hole.
# Coordinates are expressed in course-space yards unless the source data says
# otherwise. This model deliberately stores geometry and metadata only; it does
# not decide strategy, generate shot choices, or award outcomes.

const SUPPORTED_SCHEMA_VERSION := 1

var schema_version: int = SUPPORTED_SCHEMA_VERSION
var course_id: String = ""
var hole_number: int = 0
var hole_name: String = ""
var par: int = 4
var nominal_yardage: float = 0.0
var coordinate_units: String = "yards"

var tees: Array = []
var pin_position: Vector3 = Vector3.ZERO
var green_polygon: PackedVector2Array = PackedVector2Array()
var surface_regions: Array = []
var hazards: Array = []
var out_of_bounds_regions: Array = []
var elevation_points: Array = []


static func load_json(path: String):
	if not FileAccess.file_exists(path):
		push_error("HoleDefinition file not found: %s" % path)
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("HoleDefinition could not open: %s" % path)
		return null
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("HoleDefinition JSON root must be a Dictionary: %s" % path)
		return null
	return from_dictionary(parsed)


static func from_dictionary(data: Dictionary):
	var definition = new()
	if not definition._apply_dictionary(data):
		return null
	return definition


func _apply_dictionary(data: Dictionary) -> bool:
	schema_version = int(data.get("schema_version", SUPPORTED_SCHEMA_VERSION))
	if schema_version != SUPPORTED_SCHEMA_VERSION:
		push_error("Unsupported hole schema version: %d" % schema_version)
		return false

	course_id = str(data.get("course_id", ""))
	hole_number = int(data.get("hole_number", 0))
	hole_name = str(data.get("hole_name", ""))
	par = int(data.get("par", 4))
	nominal_yardage = float(data.get("nominal_yardage", 0.0))
	coordinate_units = str(data.get("coordinate_units", "yards"))

	tees.clear()
	for tee_value in data.get("tees", []):
		if typeof(tee_value) != TYPE_DICTIONARY:
			continue
		var tee: Dictionary = tee_value
		tees.append({
			"id": str(tee.get("id", "default")),
			"name": str(tee.get("name", tee.get("id", "Tee"))),
			"position": _vector3_from_data(tee.get("position", [0.0, 0.0, 0.0])),
			"yardage": float(tee.get("yardage", nominal_yardage))
		})

	pin_position = _vector3_from_data(data.get("pin_position", [0.0, 0.0, 0.0]))
	green_polygon = _polygon_from_data(data.get("green_polygon", []))
	surface_regions = _regions_from_data(data.get("surface_regions", []), "surface")
	hazards = _regions_from_data(data.get("hazards", []), "type")
	out_of_bounds_regions = _regions_from_data(data.get("out_of_bounds_regions", []), "type")

	elevation_points.clear()
	for elevation_value in data.get("elevation_points", []):
		if typeof(elevation_value) != TYPE_DICTIONARY:
			continue
		var elevation: Dictionary = elevation_value
		elevation_points.append({
			"position": _vector3_from_data(elevation.get("position", [0.0, 0.0, 0.0])),
			"elevation": float(elevation.get("elevation", 0.0))
		})

	return is_valid()


func is_valid() -> bool:
	if course_id.is_empty():
		push_error("HoleDefinition requires course_id")
		return false
	if hole_number <= 0:
		push_error("HoleDefinition requires positive hole_number")
		return false
	if par < 3 or par > 6:
		push_error("HoleDefinition par must be between 3 and 6")
		return false
	if tees.is_empty():
		push_error("HoleDefinition requires at least one tee")
		return false
	if green_polygon.size() < 3:
		push_error("HoleDefinition green_polygon requires at least three points")
		return false
	return true


func tee_position(tee_id: String = "default") -> Vector3:
	for tee in tees:
		if str(tee.get("id", "")) == tee_id:
			return tee.get("position", Vector3.ZERO)
	if not tees.is_empty():
		return tees[0].get("position", Vector3.ZERO)
	return Vector3.ZERO


func tee_yardage(tee_id: String = "default") -> float:
	for tee in tees:
		if str(tee.get("id", "")) == tee_id:
			return float(tee.get("yardage", nominal_yardage))
	if not tees.is_empty():
		return float(tees[0].get("yardage", nominal_yardage))
	return nominal_yardage


func region_by_id(region_id: String) -> Dictionary:
	for collection in [surface_regions, hazards, out_of_bounds_regions]:
		for region in collection:
			if str(region.get("id", "")) == region_id:
				return region
	return {}


func snapshot() -> Dictionary:
	return {
		"schema_version": schema_version,
		"course_id": course_id,
		"hole_number": hole_number,
		"hole_name": hole_name,
		"par": par,
		"nominal_yardage": nominal_yardage,
		"coordinate_units": coordinate_units,
		"tees": tees.duplicate(true),
		"pin_position": pin_position,
		"green_polygon": green_polygon,
		"surface_regions": surface_regions.duplicate(true),
		"hazards": hazards.duplicate(true),
		"out_of_bounds_regions": out_of_bounds_regions.duplicate(true),
		"elevation_points": elevation_points.duplicate(true)
	}


static func _regions_from_data(values, classification_key: String) -> Array:
	var result: Array = []
	if typeof(values) != TYPE_ARRAY:
		return result
	for region_value in values:
		if typeof(region_value) != TYPE_DICTIONARY:
			continue
		var region: Dictionary = region_value
		var parsed := {
			"id": str(region.get("id", "")),
			"name": str(region.get("name", region.get("id", "Region"))),
			"polygon": _polygon_from_data(region.get("polygon", []))
		}
		parsed[classification_key] = str(region.get(classification_key, ""))
		if region.has("penalty_strokes"):
			parsed["penalty_strokes"] = int(region.get("penalty_strokes", 0))
		if region.has("relief_rule"):
			parsed["relief_rule"] = str(region.get("relief_rule", ""))
		result.append(parsed)
	return result


static func _polygon_from_data(values) -> PackedVector2Array:
	var polygon := PackedVector2Array()
	if typeof(values) != TYPE_ARRAY:
		return polygon
	for point in values:
		if typeof(point) == TYPE_ARRAY and point.size() >= 2:
			polygon.append(Vector2(float(point[0]), float(point[1])))
	return polygon


static func _vector3_from_data(value) -> Vector3:
	if typeof(value) == TYPE_ARRAY:
		if value.size() >= 3:
			return Vector3(float(value[0]), float(value[1]), float(value[2]))
		if value.size() >= 2:
			return Vector3(float(value[0]), 0.0, float(value[1]))
	return Vector3.ZERO
