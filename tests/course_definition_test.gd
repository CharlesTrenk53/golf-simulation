extends SceneTree

const CourseDefinition = preload("res://simulation/course_definition.gd")

var failures: int = 0


func _init() -> void:
	print("POC-12A: load proving course")
	var course = CourseDefinition.load_json("res://data/courses/poc12_proving_course.json")
	_assert_true(course != null, "proving course loads")
	if course == null:
		quit(1)
		return

	_assert_true(course.course_id == "poc12_proving_course", "course id reconstructs")
	_assert_true(course.course_name == "POC-12 Proving Course", "course name reconstructs")
	_assert_true(course.hole_count() == 3, "course owns three ordered holes")
	_assert_true(course.hole_at(0) != null and int(course.hole_at(0).hole_number) == 1, "first slot resolves hole one")
	_assert_true(course.hole_at(1) != null and int(course.hole_at(1).hole_number) == 2, "second slot resolves hole two")
	_assert_true(course.hole_at(2) != null and int(course.hole_at(2).hole_number) == 3, "third slot resolves hole three")
	_assert_true(course.hole_by_number(2) != null and str(course.hole_by_number(2).hole_name) == "Carry Question", "hole lookup resolves by number")
	_assert_true(course.hole_at(3) == null, "out-of-range hole lookup is safe")

	print("POC-12A: derived course totals")
	_assert_true(course.total_par() == 12, "total par derives from holes")
	_assert_near(course.total_yardage("default"), 1100.0, 0.01, "back-tee yardage derives from holes")
	_assert_near(course.total_yardage("forward"), 975.0, 0.01, "forward-tee yardage derives from holes")

	var snapshot: Dictionary = course.snapshot("default")
	_assert_true(int(snapshot.get("hole_count", 0)) == 3, "snapshot reports hole count")
	_assert_true(int(snapshot.get("total_par", 0)) == 12, "snapshot reports derived par")
	_assert_near(float(snapshot.get("total_yardage", 0.0)), 1100.0, 0.01, "snapshot reports derived yardage")
	var summaries = snapshot.get("holes", [])
	_assert_true(typeof(summaries) == TYPE_ARRAY and summaries.size() == 3, "snapshot exposes ordered hole summaries")

	print("POC-12A: invalid course membership/order rejected")
	var wrong_course = CourseDefinition.from_dictionary({
		"schema_version": 1,
		"course_id": "wrong_course",
		"course_name": "Wrong Course",
		"holes": ["res://data/courses/poc12_hole_1.json"]
	})
	_assert_true(wrong_course == null, "hole from another course id is rejected")

	var wrong_order = CourseDefinition.from_dictionary({
		"schema_version": 1,
		"course_id": "poc12_proving_course",
		"course_name": "Wrong Order",
		"holes": [
			"res://data/courses/poc12_hole_2.json",
			"res://data/courses/poc12_hole_1.json"
		]
	})
	_assert_true(wrong_order == null, "holes must be ordered one through N")

	if failures == 0:
		print("POC-12A COURSE DEFINITION TESTS PASSED")
		quit(0)
	else:
		push_error("POC-12A COURSE DEFINITION TESTS FAILED: %d" % failures)
		quit(1)


func _assert_true(value: bool, label: String) -> void:
	if value:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)


func _assert_near(value: float, expected: float, tolerance: float, label: String) -> void:
	_assert_true(abs(value - expected) <= tolerance, label)
