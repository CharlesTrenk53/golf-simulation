extends SceneTree

const HoleAuthoringModel = preload("res://simulation/hole_authoring_model.gd")
const AuthoredHoleRenderer = preload("res://scenes/authored_hole_renderer.gd")

var failures: int = 0


func _init() -> void:
	print("POC-21A: authored hole 3D renderer")
	var hole = _build_hole()
	_assert_true(hole != null, "authored strategic hole builds")
	if hole == null:
		_finish()
		return

	var renderer = AuthoredHoleRenderer.new()
	get_root().add_child(renderer)
	_assert_true(renderer.render_hole(hole, "back"), "renderer accepts valid HoleDefinition")
	_assert_equal(renderer.rendered_regions.size(), 5, "renderer creates visuals for surfaces, green, hazards, and OB")

	_assert_region_matches(renderer, hole, "fairway", "FAIRWAY")
	_assert_region_matches(renderer, hole, "tee", "TEE")
	_assert_region_matches(renderer, hole, "lake", "WATER")
	_assert_region_matches(renderer, hole, "bunker", "BUNKER")
	_assert_region_matches(renderer, hole, "ob_left", "OUT_OF_BOUNDS")

	var green_visual: Node3D = renderer.region_visual("green")
	_assert_true(green_visual != null, "green visual exists")
	if green_visual != null:
		var source_polygon: PackedVector2Array = green_visual.get_meta("source_polygon", PackedVector2Array())
		_assert_polygon_equal(source_polygon, hole.green_polygon, "green visual preserves authoritative polygon")

	var tee_marker := renderer.get_node_or_null("TeeMarker")
	var pin_marker := renderer.get_node_or_null("PinMarker")
	_assert_true(tee_marker != null, "tee marker exists")
	_assert_true(pin_marker != null, "pin marker exists")
	if tee_marker != null:
		_assert_vector_close(tee_marker.get_meta("course_position", Vector3.ZERO), hole.tee_position("back"), "tee marker preserves course position")
	if pin_marker != null:
		_assert_vector_close(pin_marker.get_meta("course_position", Vector3.ZERO), hole.pin_position, "pin marker preserves course position")

	print("POC21_RENDER_SUMMARY regions=%d tee=%s pin=%s" % [
		renderer.rendered_regions.size(),
		str(hole.tee_position("back")),
		str(hole.pin_position)
	])

	renderer.queue_free()
	_finish()


func _build_hole():
	var author = HoleAuthoringModel.new()
	author.configure_identity("poc21_playable_runtime", 1, "Visible Strategy", 4, 420.0)
	author.add_tee("back", "Back", Vector3(0.0, 0.0, 420.0), 420.0)
	author.set_pin(Vector3(6.0, 0.0, 0.0))
	author.set_green(_rect(-20.0, -18.0, 24.0, 20.0))
	author.add_surface_region("fairway", "Fairway", "FAIRWAY", PackedVector2Array([
		Vector2(-34.0, 24.0), Vector2(30.0, 24.0), Vector2(36.0, 385.0), Vector2(-28.0, 385.0)
	]))
	author.add_surface_region("tee", "Tee", "TEE", _rect(-10.0, 408.0, 10.0, 432.0))
	author.add_hazard("lake", "Lake", "WATER", _rect(22.0, 180.0, 62.0, 285.0), 1, "lateral")
	author.add_hazard("bunker", "Front Bunker", "BUNKER", _rect(-26.0, 22.0, -10.0, 55.0), 0, "")
	author.add_out_of_bounds_region("ob_left", "Left OB", PackedVector2Array([
		Vector2(-62.0, 0.0), Vector2(-48.0, 0.0), Vector2(-48.0, 440.0), Vector2(-62.0, 440.0)
	]), 1, "stroke_and_distance")
	return author.build_definition()


func _rect(left: float, near_z: float, right: float, far_z: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(left, near_z), Vector2(right, near_z), Vector2(right, far_z), Vector2(left, far_z)
	])


func _assert_region_matches(renderer, hole, region_id: String, classification: String) -> void:
	var visual: Node3D = renderer.region_visual(region_id)
	_assert_true(visual != null, "%s visual exists" % region_id)
	if visual == null:
		return
	_assert_equal(str(visual.get_meta("classification", "")), classification, "%s visual classification matches" % region_id)
	var source_polygon: PackedVector2Array = visual.get_meta("source_polygon", PackedVector2Array())
	var expected: PackedVector2Array = hole.region_by_id(region_id).get("polygon", PackedVector2Array())
	_assert_polygon_equal(source_polygon, expected, "%s visual preserves authoritative polygon" % region_id)


func _assert_polygon_equal(actual: PackedVector2Array, expected: PackedVector2Array, label: String) -> void:
	if actual == expected:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: %s (actual=%s expected=%s)" % [label, str(actual), str(expected)])


func _assert_vector_close(actual: Vector3, expected: Vector3, label: String) -> void:
	if actual.distance_to(expected) <= 0.001:
		print("PASS: %s (actual=%s expected=%s)" % [label, str(actual), str(expected)])
	else:
		failures += 1
		push_error("FAIL: %s (actual=%s expected=%s)" % [label, str(actual), str(expected)])


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
		print("POC-21A AUTHORED HOLE 3D RENDERER PASSED")
		quit(0)
	else:
		push_error("POC-21A AUTHORED HOLE 3D RENDERER FAILED: %d" % failures)
		quit(1)
