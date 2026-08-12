extends SceneTree

const HoleAuthoringModel = preload("res://simulation/hole_authoring_model.gd")
const CourseAuthoringModel = preload("res://simulation/course_authoring_model.gd")

var failures: int = 0


func _init() -> void:
	print("POC-17D: course authoring model")

	var course = CourseAuthoringModel.new()
	course.configure_identity("poc17_course_builder", "POC-17 Builder Course")
	_expect(course.add_hole(_build_hole(1, "Opening Four", 4, 410.0)), "hole 1 can be added")
	_expect(course.add_hole(_build_hole(2, "Water Three", 3, 168.0)), "hole 2 can be added")
	_expect(course.add_hole(_build_hole(3, "Risk Reward Five", 5, 525.0)), "hole 3 can be added")

	var definition = course.build_definition()
	_expect(definition != null, "authored course builds a valid CourseDefinition")
	if definition != null:
		var snapshot: Dictionary = definition.snapshot("back")
		_expect_equal(definition.course_id, "poc17_course_builder", "course id survives authoring")
		_expect_equal(definition.course_name, "POC-17 Builder Course", "course name survives authoring")
		_expect_equal(definition.hole_count(), 3, "course contains three ordered holes")
		_expect_equal(definition.total_par(), 12, "total par derives from authored holes")
		_expect_close(definition.total_yardage("back"), 1103.0, "total yardage derives from authored tees")
		_expect_equal(definition.hole_at(0).hole_number, 1, "hole 1 remains first")
		_expect_equal(definition.hole_at(1).hole_number, 2, "hole 2 remains second")
		_expect_equal(definition.hole_at(2).hole_number, 3, "hole 3 remains third")
		_expect_equal(snapshot.get("hole_count", 0), 3, "course snapshot reports hole count")
		_expect_equal(snapshot.get("total_par", 0), 12, "course snapshot reports total par")
		_expect_close(float(snapshot.get("total_yardage", 0.0)), 1103.0, "course snapshot reports total yardage")
		_expect(definition.hole_paths.is_empty(), "in-memory authored course does not invent JSON paths")

	var wrong_course = CourseAuthoringModel.new()
	wrong_course.configure_identity("poc17_course_builder", "Broken Course")
	var foreign_hole = _build_hole(1, "Foreign", 4, 400.0, "different_course")
	_expect(wrong_course.add_hole(foreign_hole), "foreign hole can enter mutable authoring state before validation")
	_expect(wrong_course.build_definition() == null, "course validation rejects a hole from another course")

	var wrong_order = CourseAuthoringModel.new()
	wrong_order.configure_identity("poc17_course_builder", "Wrong Order")
	_expect(wrong_order.add_hole(_build_hole(2, "Second First", 4, 410.0)), "out-of-order hole can enter mutable authoring state")
	_expect(wrong_order.build_definition() == null, "course validation rejects non-sequential hole ordering")

	_finish()


func _build_hole(number: int, name: String, par: int, yardage: float, override_course_id: String = ""):
	var author = HoleAuthoringModel.new()
	var id: String = override_course_id if not override_course_id.is_empty() else "poc17_course_builder"
	author.configure_identity(id, number, name, par, yardage)
	author.add_tee("back", "Back", Vector3(0.0, 0.0, yardage), yardage)
	author.set_pin(Vector3.ZERO)
	author.set_green(PackedVector2Array([
		Vector2(-15.0, -12.0), Vector2(15.0, -12.0), Vector2(15.0, 12.0), Vector2(-15.0, 12.0)
	]))
	author.add_surface_region("fairway_%d" % number, "Fairway", "FAIRWAY", PackedVector2Array([
		Vector2(-25.0, 20.0), Vector2(25.0, 20.0), Vector2(30.0, yardage - 20.0), Vector2(-30.0, yardage - 20.0)
	]))
	author.add_surface_region("tee_%d" % number, "Tee", "TEE", PackedVector2Array([
		Vector2(-10.0, yardage - 10.0), Vector2(10.0, yardage - 10.0), Vector2(10.0, yardage + 10.0), Vector2(-10.0, yardage + 10.0)
	]))
	return author


func _expect(value: bool, label: String) -> void:
	if value:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)


func _expect_equal(actual, expected, label: String) -> void:
	if actual == expected:
		print("PASS: %s (actual=%s expected=%s)" % [label, str(actual), str(expected)])
	else:
		failures += 1
		push_error("FAIL: %s (actual=%s expected=%s)" % [label, str(actual), str(expected)])


func _expect_close(actual: float, expected: float, label: String) -> void:
	if is_equal_approx(actual, expected):
		print("PASS: %s (actual=%.3f expected=%.3f)" % [label, actual, expected])
	else:
		failures += 1
		push_error("FAIL: %s (actual=%.3f expected=%.3f)" % [label, actual, expected])


func _finish() -> void:
	if failures == 0:
		print("POC-17D COURSE AUTHORING MODEL PASSED")
		quit(0)
	else:
		push_error("POC-17D COURSE AUTHORING MODEL FAILED: %d" % failures)
		quit(1)
