extends RefCounted

# POC-12A: Course Definition
# --------------------------
# Owns an ordered set of independently playable HoleDefinitions. Course totals
# are derived from the holes so par and yardage have one source of truth.

const HoleDefinition = preload("res://simulation/hole_definition.gd")
const SUPPORTED_SCHEMA_VERSION := 1

var schema_version: int = SUPPORTED_SCHEMA_VERSION
var course_id: String = ""
var course_name: String = ""
var hole_paths: Array[String] = []
var holes: Array = []


static func load_json(path: String):
	if not FileAccess.file_exists(path):
		push_error("CourseDefinition file not found: %s" % path)
		return null
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("CourseDefinition could not open: %s" % path)
		return null
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("CourseDefinition JSON root must be a Dictionary: %s" % path)
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
		push_error("Unsupported course schema version: %d" % schema_version)
		return false

	course_id = str(data.get("course_id", ""))
	course_name = str(data.get("course_name", ""))
	hole_paths.clear()
	holes.clear()

	var raw_paths = data.get("holes", [])
	if typeof(raw_paths) != TYPE_ARRAY:
		push_error("CourseDefinition holes must be an Array")
		return false

	for path_value in raw_paths:
		var hole_path: String = str(path_value)
		hole_paths.append(hole_path)
		var hole = HoleDefinition.load_json(hole_path)
		if hole == null:
			push_error("CourseDefinition could not load hole: %s" % hole_path)
			return false
		holes.append(hole)

	return is_valid()


func is_valid() -> bool:
	if course_id.is_empty():
		push_error("CourseDefinition requires course_id")
		return false
	if course_name.is_empty():
		push_error("CourseDefinition requires course_name")
		return false
	if holes.is_empty():
		push_error("CourseDefinition requires at least one hole")
		return false
	if holes.size() != hole_paths.size():
		push_error("CourseDefinition hole path count must match loaded hole count")
		return false

	var seen_numbers: Dictionary = {}
	for index in range(holes.size()):
		var hole = holes[index]
		if str(hole.course_id) != course_id:
			push_error("CourseDefinition hole %d belongs to course '%s', expected '%s'" % [int(hole.hole_number), str(hole.course_id), course_id])
			return false
		var expected_number: int = index + 1
		if int(hole.hole_number) != expected_number:
			push_error("CourseDefinition holes must be ordered 1..N; slot %d contains hole %d" % [expected_number, int(hole.hole_number)])
			return false
		if seen_numbers.has(int(hole.hole_number)):
			push_error("CourseDefinition contains duplicate hole number: %d" % int(hole.hole_number))
			return false
		seen_numbers[int(hole.hole_number)] = true
	return true


func hole_count() -> int:
	return holes.size()


func hole_at(index: int):
	if index < 0 or index >= holes.size():
		return null
	return holes[index]


func hole_by_number(hole_number: int):
	for hole in holes:
		if int(hole.hole_number) == hole_number:
			return hole
	return null


func total_par() -> int:
	var total: int = 0
	for hole in holes:
		total += int(hole.par)
	return total


func total_yardage(tee_id: String = "default") -> float:
	var total: float = 0.0
	for hole in holes:
		total += float(hole.tee_yardage(tee_id))
	return total


func snapshot(tee_id: String = "default") -> Dictionary:
	var hole_summaries: Array = []
	for hole in holes:
		hole_summaries.append({
			"hole_number": int(hole.hole_number),
			"hole_name": str(hole.hole_name),
			"par": int(hole.par),
			"yardage": float(hole.tee_yardage(tee_id))
		})
	return {
		"schema_version": schema_version,
		"course_id": course_id,
		"course_name": course_name,
		"hole_count": hole_count(),
		"total_par": total_par(),
		"total_yardage": total_yardage(tee_id),
		"holes": hole_summaries
	}
