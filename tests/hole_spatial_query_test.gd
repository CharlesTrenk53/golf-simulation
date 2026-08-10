extends SceneTree

const HoleDefinition = preload("res://simulation/hole_definition.gd")
const HoleSpatialQuery = preload("res://simulation/hole_spatial_query.gd")

var failures: int = 0


func _init() -> void:
	print("POC-11B: load hole")
	var hole = HoleDefinition.load_json("res://data/courses/poc11_test_hole.json")
	_assert_true(hole != null, "test hole loads")
	if hole == null:
		quit(1)
		return
	var query = HoleSpatialQuery.new(hole)

	print("POC-11B: surface queries")
	_test_surface_queries(query)
	print("POC-11B: distance query")
	_test_distance_query(query)
	print("POC-11B: hazard queries")
	_test_hazard_queries(query)
	print("POC-11B: out-of-bounds queries")
	_test_out_of_bounds(query)
	print("POC-11B: position snapshot")
	_test_position_snapshot(query)
	print("POC-11B: assertions complete")

	if failures == 0:
		print("POC-11B SPATIAL QUERY TESTS PASSED")
		quit(0)
	else:
		push_error("POC-11B SPATIAL QUERY TESTS FAILED: %d" % failures)
		quit(1)


func _test_surface_queries(query) -> void:
	_assert_true(query.surface_at(Vector3(0, 0, 425)) == "TEE", "tee resolves from hole data")
	_assert_true(query.surface_at(Vector3(0, 0, 340)) == "FAIRWAY", "fairway resolves from polygon")
	_assert_true(query.surface_at(Vector3(40, 0, 340)) == "ROUGH", "outside mapped surfaces defaults to rough")
	_assert_true(query.surface_at(Vector3(6, 0, 8)) == "GREEN", "green polygon resolves")
	_assert_true(query.surface_at(Vector3(-35, 0, 255)) == "WATER", "water overrides underlying course")
	_assert_true(query.surface_at(Vector3(22, 0, 195)) == "BUNKER", "bunker resolves from hazard polygon")


func _test_distance_query(query) -> void:
	var expected := Vector2(0, 425).distance_to(Vector2(6, 8))
	_assert_near(query.distance_to_pin(Vector3(0, 0, 425)), expected, 0.001, "distance to pin uses course-space geometry")


func _test_hazard_queries(query) -> void:
	var water = query.hazard_at(Vector3(-35, 0, 255))
	_assert_true(str(water.get("id", "")) == "water_left", "hazard_at identifies water")
	var bunker = query.hazard_at(Vector3(22, 0, 195))
	_assert_true(str(bunker.get("id", "")) == "right_fairway_bunker", "hazard_at identifies bunker")

	var direct_water = query.hazards_in_corridor(Vector3(-10, 0, 330), Vector3(-35, 0, 220))
	_assert_true(_contains_region(direct_water, "water_left"), "shot centerline detects intersecting water")

	var centerline_clear = query.hazards_in_corridor(Vector3(0, 0, 330), Vector3(0, 0, 180))
	_assert_true(not _contains_region(centerline_clear, "right_fairway_bunker"), "narrow centerline can miss lateral bunker")
	var wide_corridor = query.hazards_in_corridor(Vector3(0, 0, 330), Vector3(0, 0, 180), 20.0)
	_assert_true(_contains_region(wide_corridor, "right_fairway_bunker"), "shot corridor width detects nearby bunker")


func _test_out_of_bounds(query) -> void:
	_assert_true(query.is_out_of_bounds(Vector3(60, 0, 200)), "right boundary resolves as out of bounds")
	_assert_true(not query.is_out_of_bounds(Vector3(0, 0, 200)), "center of hole remains in bounds")
	var region = query.out_of_bounds_region_at(Vector3(60, 0, 200))
	_assert_true(str(region.get("relief_rule", "")) == "STROKE_AND_DISTANCE", "OB query preserves rule metadata")


func _test_position_snapshot(query) -> void:
	var snapshot = query.query_position(Vector3(0, 0, 250))
	_assert_true(snapshot["surface"] == "FAIRWAY", "position query reports surface")
	_assert_true(snapshot["out_of_bounds"] == false, "position query reports bounds")
	_assert_near(float(snapshot["elevation"]), -4.0, 0.001, "position query exposes nearest elevation sample")
	_assert_true(float(snapshot["distance_to_pin"]) > 200.0, "position query reports distance")


func _contains_region(regions: Array, region_id: String) -> bool:
	for region in regions:
		if str(region.get("id", "")) == region_id:
			return true
	return false


func _assert_true(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error("FAIL: " + label)
	else:
		print("PASS: ", label)


func _assert_near(value: float, expected: float, tolerance: float, label: String) -> void:
	_assert_true(abs(value - expected) <= tolerance, label)
