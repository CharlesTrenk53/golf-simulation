extends SceneTree

const HoleDefinition = preload("res://simulation/hole_definition.gd")

var failures: int = 0


func _init() -> void:
	_test_fixture_loads()
	_test_geometry_reconstructs()
	_test_tee_lookup()
	_test_region_lookup()
	_test_invalid_definition_rejected()

	if failures == 0:
		print("POC-11A HOLE DEFINITION TESTS PASSED")
		quit(0)
	else:
		push_error("POC-11A HOLE DEFINITION TESTS FAILED: %d" % failures)
		quit(1)


func _load_fixture():
	return HoleDefinition.load_json("res://data/courses/poc11_test_hole.json")


func _test_fixture_loads() -> void:
	var hole = _load_fixture()
	_assert_true(hole != null, "fixture loads from JSON")
	if hole == null:
		return
	_assert_true(hole.course_id == "poc11_proving_ground", "course id reconstructs")
	_assert_true(hole.hole_number == 1, "hole number reconstructs")
	_assert_true(hole.hole_name == "Decision Point", "hole name reconstructs")
	_assert_true(hole.par == 4, "par reconstructs")
	_assert_near(hole.nominal_yardage, 425.0, 0.001, "nominal yardage reconstructs")
	_assert_true(hole.coordinate_units == "yards", "coordinate units reconstruct")


func _test_geometry_reconstructs() -> void:
	var hole = _load_fixture()
	if hole == null:
		return
	_assert_true(hole.green_polygon.size() == 6, "green polygon preserves vertices")
	_assert_true(hole.surface_regions.size() == 2, "surface regions reconstruct")
	_assert_true(hole.hazards.size() == 3, "hazards reconstruct")
	_assert_true(hole.out_of_bounds_regions.size() == 1, "out-of-bounds region reconstructs")
	_assert_true(hole.elevation_points.size() == 4, "elevation hooks reconstruct")
	_assert_near(hole.pin_position.x, 6.0, 0.001, "pin x reconstructs")
	_assert_near(hole.pin_position.z, 8.0, 0.001, "pin z reconstructs")
	var fairway: Dictionary = hole.region_by_id("fairway_main")
	_assert_true(not fairway.is_empty(), "fairway is addressable by id")
	_assert_true(fairway.get("surface", "") == "FAIRWAY", "fairway classification survives parsing")
	_assert_true(fairway.get("polygon", PackedVector2Array()).size() == 14, "fairway polygon preserves full geometry")


func _test_tee_lookup() -> void:
	var hole = _load_fixture()
	if hole == null:
		return
	_assert_true(hole.tees.size() == 2, "multiple tees reconstruct")
	var back: Vector3 = hole.tee_position("default")
	var forward: Vector3 = hole.tee_position("forward")
	_assert_near(back.z, 425.0, 0.001, "default tee position resolves")
	_assert_near(forward.z, 385.0, 0.001, "named tee position resolves")
	_assert_near(hole.tee_yardage("forward"), 385.0, 0.001, "named tee yardage resolves")


func _test_region_lookup() -> void:
	var hole = _load_fixture()
	if hole == null:
		return
	var water: Dictionary = hole.region_by_id("water_left")
	_assert_true(water.get("type", "") == "WATER", "water hazard classification reconstructs")
	_assert_true(int(water.get("penalty_strokes", 0)) == 1, "water penalty metadata reconstructs")
	_assert_true(water.get("relief_rule", "") == "PENALTY_AREA", "water relief metadata reconstructs")
	var bunker: Dictionary = hole.region_by_id("right_fairway_bunker")
	_assert_true(bunker.get("type", "") == "BUNKER", "bunker geometry reconstructs independently of water")
	var boundary: Dictionary = hole.region_by_id("right_ob")
	_assert_true(boundary.get("type", "") == "OUT_OF_BOUNDS", "OB classification reconstructs")
	_assert_true(boundary.get("relief_rule", "") == "STROKE_AND_DISTANCE", "OB rule metadata reconstructs")


func _test_invalid_definition_rejected() -> void:
	var invalid = HoleDefinition.from_dictionary({
		"schema_version": 1,
		"course_id": "broken",
		"hole_number": 1,
		"par": 4,
		"tees": [{"id": "default", "position": [0, 0, 100]}],
		"pin_position": [0, 0, 0],
		"green_polygon": [[0, 0], [10, 0]]
	})
	_assert_true(invalid == null, "invalid geometry is rejected")


func _assert_true(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error("FAIL: " + label)
	else:
		print("PASS: ", label)


func _assert_near(value: float, expected: float, tolerance: float, label: String) -> void:
	_assert_true(abs(value - expected) <= tolerance, label)
