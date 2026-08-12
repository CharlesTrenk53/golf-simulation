extends RefCounted

# POC-17D: Course Authoring Model
# -------------------------------
# Mutable, UI-independent course builder that owns an ordered set of authored
# holes and produces the existing CourseDefinition runtime model.

const CourseDefinition = preload("res://simulation/course_definition.gd")

var course_id: String = ""
var course_name: String = ""
var authored_holes: Array = []


func configure_identity(new_course_id: String, new_course_name: String) -> void:
	course_id = new_course_id
	course_name = new_course_name


func add_hole(authoring_model) -> bool:
	if authoring_model == null or not authoring_model.has_method("build_definition"):
		return false
	var definition = authoring_model.build_definition()
	if definition == null:
		return false
	authored_holes.append(definition)
	return true


func add_hole_definition(definition) -> bool:
	if definition == null:
		return false
	authored_holes.append(definition)
	return true


func hole_count() -> int:
	return authored_holes.size()


func build_definition():
	return CourseDefinition.from_holes(course_id, course_name, authored_holes)


func is_valid() -> bool:
	return build_definition() != null


func total_par() -> int:
	var definition = build_definition()
	return definition.total_par() if definition != null else 0


func total_yardage(tee_id: String = "default") -> float:
	var definition = build_definition()
	return definition.total_yardage(tee_id) if definition != null else 0.0
