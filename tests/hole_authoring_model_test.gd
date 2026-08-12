extends SceneTree

const HoleAuthoringModel = preload("res://simulation/hole_authoring_model.gd")

var failures: int = 0


func _init() -> void:
	print("POC-17A: hole authoring model")

	var authoring := HoleAuthoringModel.new()
	authoring.configure_identity("poc17_builder", 1, "Builder Proof Hole", 5, 525.0)
	authoring.add_tee("back", "Back Tee", Vector3(0, 0, 525), 525.0)
	authoring.add_tee("forward", "Forward Tee", Vector3(0, 0, 470), 470.0)
	authoring.set_pin(Vector3(35, 0, 0))
	authoring.set_green(PackedVector2Array([
		Vector2(20, -18),
		Vector2(52, -18),
		Vector2(55, 18),
		Vector2(18, 18)
	]))
	authoring.add_surface_region("fairway_1", "Main Fairway", "FAIRWAY", PackedVector2Array([
		Vector2(-24, 500),
		Vector2(24, 500),
		Vector2(55, 190),
		Vector2(15, 80),
		Vector2(-18, 100),
		Vector2(-45, 260)
	]))
	authoring.add_surface_region("left_rough", "Left Rough", "ROUGH", PackedVector2Array([
		Vector2(-70, 500),
		Vector2(-24, 500),
		Vector2(-45, 260),
		Vector2(-18, 100),
		Vector2(-85, 80)
	]))
	authoring.add_hazard("pond", "Cross Pond", "WATER", PackedVector2Array([
		Vector2(-15, 225),
		Vector2(50, 225),
		Vector2(52, 185),
		Vector2(-10, 185)
	]), 1, "lateral")
	authoring.add_out_of_bounds_region("right_ob", "Right Boundary", PackedVector2Array([
		Vector2(80, 540),
		Vector2(120, 540),
		Vector2(120, -20),
		Vector2(80, -20)
	]))
	authoring.add_elevation_point(Vector3(0, 0, 525), 0.0)
	authoring.add_elevation_point(Vector3(35, 0, 0), 12.0)

	var data: Dictionary = authoring.to_dictionary()
	var definition = authoring.build_definition()

	_assert_true(definition != null, "authored data builds a valid HoleDefinition")
	if definition != null:
		_assert_equal(str(definition.course_id), "poc17_builder", "course id survives authoring roundtrip")
		_assert_equal(int(definition.hole_number), 1, "hole number survives authoring roundtrip")
		_assert_equal(int(definition.par), 5, "par survives authoring roundtrip")
		_assert_near(float(definition.tee_yardage("back")), 525.0, 0.001, "back tee yardage survives authoring roundtrip")
		_assert_near(float(definition.tee_yardage("forward")), 470.0, 0.001, "forward tee yardage survives authoring roundtrip")
		_assert_equal(definition.green_polygon.size(), 4, "green polygon survives authoring roundtrip")
		_assert_equal(definition.surface_regions.size(), 2, "surface regions survive authoring roundtrip")
		_assert_equal(definition.hazards.size(), 1, "hazard survives authoring roundtrip")
		_assert_equal(definition.out_of_bounds_regions.size(), 1, "out-of-bounds region survives authoring roundtrip")
		_assert_equal(definition.elevation_points.size(), 2, "elevation points survive authoring roundtrip")
		var pond: Dictionary = definition.region_by_id("pond")
		_assert_equal(str(pond.get("type", "")), "WATER", "hazard classification survives authoring roundtrip")
		_assert_equal(int(pond.get("penalty_strokes", 0)), 1, "hazard penalty survives authoring roundtrip")
		_assert_equal(str(pond.get("relief_rule", "")), "lateral", "hazard relief rule survives authoring roundtrip")

	_assert_true(typeof(data.get("green_polygon", null)) == TYPE_ARRAY, "authoring output is JSON-compatible geometry data")
	_assert_true(typeof(data.get("tees", null)) == TYPE_ARRAY, "authoring output is JSON-compatible tee data")

	if failures == 0:
		print("POC-17A HOLE AUTHORING MODEL PASSED")
		quit(0)
	else:
		push_error("POC-17A HOLE AUTHORING MODEL FAILED: %d" % failures)
		quit(1)


func _assert_true(value: bool, label: String) -> void:
	if value:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)


func _assert_equal(actual, expected, label: String) -> void:
	_assert_true(actual == expected, "%s (actual=%s expected=%s)" % [label, str(actual), str(expected)])


func _assert_near(actual: float, expected: float, tolerance: float, label: String) -> void:
	_assert_true(abs(actual - expected) <= tolerance, "%s (actual=%.3f expected=%.3f)" % [label, actual, expected])
