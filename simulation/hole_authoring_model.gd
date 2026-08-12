extends RefCounted

# POC-17A: Hole Authoring Model
# -----------------------------
# Mutable authoring layer for creating HoleDefinition-compatible data without
# coupling course creation to the golfer engine or a future visual editor.

const HoleDefinition = preload("res://simulation/hole_definition.gd")

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


func configure_identity(new_course_id: String, new_hole_number: int, new_hole_name: String, new_par: int, yardage: float) -> void:
	course_id = new_course_id
	hole_number = new_hole_number
	hole_name = new_hole_name
	par = new_par
	nominal_yardage = yardage


func add_tee(tee_id: String, tee_name: String, position: Vector3, yardage: float) -> void:
	tees.append({
		"id": tee_id,
		"name": tee_name,
		"position": position,
		"yardage": yardage
	})


func set_pin(position: Vector3) -> void:
	pin_position = position


func set_green(points: PackedVector2Array) -> void:
	green_polygon = points.duplicate()


func add_surface_region(region_id: String, region_name: String, surface: String, points: PackedVector2Array) -> void:
	surface_regions.append({
		"id": region_id,
		"name": region_name,
		"surface": surface,
		"polygon": points.duplicate()
	})


func add_hazard(region_id: String, region_name: String, hazard_type: String, points: PackedVector2Array, penalty_strokes: int = 1, relief_rule: String = "") -> void:
	var hazard := {
		"id": region_id,
		"name": region_name,
		"type": hazard_type,
		"polygon": points.duplicate(),
		"penalty_strokes": penalty_strokes
	}
	if not relief_rule.is_empty():
		hazard["relief_rule"] = relief_rule
	hazards.append(hazard)


func add_out_of_bounds_region(region_id: String, region_name: String, points: PackedVector2Array, penalty_strokes: int = 1, relief_rule: String = "stroke_and_distance") -> void:
	out_of_bounds_regions.append({
		"id": region_id,
		"name": region_name,
		"type": "OUT_OF_BOUNDS",
		"polygon": points.duplicate(),
		"penalty_strokes": penalty_strokes,
		"relief_rule": relief_rule
	})


func add_elevation_point(position: Vector3, elevation: float) -> void:
	elevation_points.append({
		"position": position,
		"elevation": elevation
	})


func to_dictionary() -> Dictionary:
	return {
		"schema_version": HoleDefinition.SUPPORTED_SCHEMA_VERSION,
		"course_id": course_id,
		"hole_number": hole_number,
		"hole_name": hole_name,
		"par": par,
		"nominal_yardage": nominal_yardage,
		"coordinate_units": coordinate_units,
		"tees": _serialize_tees(),
		"pin_position": _vector3_to_array(pin_position),
		"green_polygon": _polygon_to_arrays(green_polygon),
		"surface_regions": _serialize_regions(surface_regions, "surface"),
		"hazards": _serialize_regions(hazards, "type"),
		"out_of_bounds_regions": _serialize_regions(out_of_bounds_regions, "type"),
		"elevation_points": _serialize_elevation_points()
	}


func build_definition():
	return HoleDefinition.from_dictionary(to_dictionary())


func is_valid() -> bool:
	return build_definition() != null


func _serialize_tees() -> Array:
	var result: Array = []
	for tee in tees:
		result.append({
			"id": str(tee.get("id", "default")),
			"name": str(tee.get("name", "Tee")),
			"position": _vector3_to_array(tee.get("position", Vector3.ZERO)),
			"yardage": float(tee.get("yardage", nominal_yardage))
		})
	return result


func _serialize_regions(regions: Array, classification_key: String) -> Array:
	var result: Array = []
	for region in regions:
		var serialized := {
			"id": str(region.get("id", "")),
			"name": str(region.get("name", "Region")),
			"polygon": _polygon_to_arrays(region.get("polygon", PackedVector2Array()))
		}
		serialized[classification_key] = str(region.get(classification_key, ""))
		if region.has("penalty_strokes"):
			serialized["penalty_strokes"] = int(region["penalty_strokes"])
		if region.has("relief_rule"):
			serialized["relief_rule"] = str(region["relief_rule"])
		result.append(serialized)
	return result


func _serialize_elevation_points() -> Array:
	var result: Array = []
	for point in elevation_points:
		result.append({
			"position": _vector3_to_array(point.get("position", Vector3.ZERO)),
			"elevation": float(point.get("elevation", 0.0))
		})
	return result


static func _vector3_to_array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


static func _polygon_to_arrays(points: PackedVector2Array) -> Array:
	var result: Array = []
	for point in points:
		result.append([point.x, point.y])
	return result
