extends SceneTree

const HoleAuthoringModel = preload("res://simulation/hole_authoring_model.gd")
const HoleCourseContext = preload("res://simulation/hole_course_context.gd")

var failures: int = 0


func _init() -> void:
	print("POC-18F: hazard corridor edge proximity regression")
	var author = HoleAuthoringModel.new()
	author.configure_identity("corridor_edge_regression", 1, "Edge Proximity", 4, 400.0)
	author.add_tee("back", "Back", Vector3(0, 0, 100), 400.0)
	author.set_pin(Vector3(0, 0, 0))
	author.set_green(PackedVector2Array([
		Vector2(-10, -10), Vector2(10, -10), Vector2(10, 10), Vector2(-10, 10)
	]))

	# This long hazard edge runs eight yards beside the shot line from z=0..100.
	# None of its vertices lies within ten yards of the finite shot segment because
	# the corners extend well beyond both endpoints. The pre-fix vertex-only test
	# therefore missed it even though the hazard boundary is inside the corridor.
	author.add_hazard("parallel_water", "Parallel Water", "WATER", PackedVector2Array([
		Vector2(8, -50), Vector2(30, -50), Vector2(30, 150), Vector2(8, 150)
	]), 1, "lateral")

	var definition = author.build_definition()
	_assert_true(definition != null, "regression hole builds")
	if definition == null:
		_finish()
		return

	var context = HoleCourseContext.new(definition)
	var start = Vector3(0, 0, 100)
	var end = Vector3(0, 0, 0)
	var narrow: Array = context.hazards_in_corridor(start, end, 7.0)
	var touching: Array = context.hazards_in_corridor(start, end, 8.0)
	var wide: Array = context.hazards_in_corridor(start, end, 10.0)

	_assert_equal(narrow.size(), 0, "seven-yard corridor stays clear")
	_assert_equal(touching.size(), 1, "eight-yard corridor detects parallel hazard edge")
	_assert_equal(wide.size(), 1, "ten-yard corridor detects parallel hazard edge")
	if not wide.is_empty():
		_assert_equal(str(wide[0].get("id", "")), "parallel_water", "correct hazard is returned")

	_finish()


func _assert_true(value: bool, label: String) -> void:
	if value:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)


func _assert_equal(actual, expected, label: String) -> void:
	if actual == expected:
		print("PASS: %s (actual=%s expected=%s)" % [label, str(actual), str(expected)])
	else:
		failures += 1
		push_error("FAIL: %s (actual=%s expected=%s)" % [label, str(actual), str(expected)])


func _finish() -> void:
	if failures == 0:
		print("POC-18F HAZARD CORRIDOR EDGE PROXIMITY PASSED")
		quit(0)
	else:
		push_error("POC-18F HAZARD CORRIDOR EDGE PROXIMITY FAILED: %d" % failures)
		quit(1)
