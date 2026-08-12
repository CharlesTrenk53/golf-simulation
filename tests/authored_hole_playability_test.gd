extends SceneTree

const GolferScript = preload("res://scenes/golfer.gd")
const HoleAuthoringModel = preload("res://simulation/hole_authoring_model.gd")
const DataDefinedAutonomousHole = preload("res://simulation/data_defined_autonomous_hole.gd")

var failures: int = 0


func _init() -> void:
	print("POC-17B: authored hole playability bridge")
	var author = _build_hole()
	var definition = author.to_hole_definition()
	_assert_true(definition != null, "authored hole produces a valid HoleDefinition")
	if definition == null:
		_finish()
		return

	var golfer = _build_golfer()
	var simulation = DataDefinedAutonomousHole.new(definition, "back")
	var result: Dictionary = simulation.play_hole(golfer, 170201)
	var history: Array = result.get("history", [])

	print("PLAYABILITY_SUMMARY finished=%s strokes=%d par=%d final_surface=%s remaining=%.3f shots=%d" % [
		str(bool(result.get("finished", false))),
		int(result.get("strokes", 0)),
		int(result.get("par", 0)),
		str(result.get("final_surface", "UNKNOWN")),
		float(result.get("remaining_distance", INF)),
		history.size()
	])

	_assert_true(bool(result.get("finished", false)), "golfer holes out on authored geometry")
	_assert_true(not history.is_empty(), "authored hole produces a shot history")
	_assert_equal(int(result.get("par", 0)), 4, "authored par reaches golfer engine")
	_assert_true(_history_starts_on_tee(history), "first shot begins from authored tee")
	_assert_true(_history_reaches_green(history), "authored surfaces route play onto green")
	_assert_true(_history_ends_holed(history), "authored hole finishes with a holed putt")
	_assert_true(_history_uses_course_management(history), "non-putt authored play uses data-defined course management")
	golfer.free()
	_finish()


func _build_hole():
	var author = HoleAuthoringModel.new()
	author.set_identity("poc17_playable", 1, "Builder Bridge", 4, 410.0)
	author.add_tee("back", "Back", Vector3(0, 0, 410), 410.0)
	author.set_pin(Vector3(0, 0, 0))
	author.set_green_polygon(PackedVector2Array([
		Vector2(-16, -14), Vector2(16, -14), Vector2(16, 14), Vector2(-16, 14)
	]))
	author.add_surface_region("fairway", "Fairway", "FAIRWAY", PackedVector2Array([
		Vector2(-24, 30), Vector2(24, 30), Vector2(30, 390), Vector2(-30, 390)
	]))
	author.add_surface_region("tee", "Tee", "TEE", PackedVector2Array([
		Vector2(-10, 400), Vector2(10, 400), Vector2(10, 420), Vector2(-10, 420)
	]))
	return author


func _build_golfer() -> Node:
	var golfer = GolferScript.new()
	golfer.profile = golfer.GolferProfile.CAREFUL_CARL
	golfer.apply_profile()
	golfer.golfer_name = "POC17 Builder Golfer"
	golfer.driving = 75.0
	golfer.approach = 75.0
	golfer.short_game = 75.0
	golfer.putting = 75.0
	golfer.risk_tolerance = 45.0
	golfer.confidence = 70.0
	golfer.decision_variability = 0.0
	golfer.physical_power = 70.0
	golfer.mobility = 70.0
	golfer.coordination = 70.0
	golfer.endurance = 70.0
	return golfer


func _history_starts_on_tee(history: Array) -> bool:
	if history.is_empty():
		return false
	return str(history[0].get("surface_before", "")).to_upper() == "TEE"


func _history_reaches_green(history: Array) -> bool:
	for shot in history:
		if str(shot.get("surface_after", "")).to_upper() == "GREEN":
			return true
	return false


func _history_ends_holed(history: Array) -> bool:
	if history.is_empty():
		return false
	return str(history[-1].get("outcome", "")).to_upper() == "HOLED"


func _history_uses_course_management(history: Array) -> bool:
	for shot in history:
		if str(shot.get("decision_system", "")) == "EXPECTED_STROKES_COURSE_MANAGEMENT":
			return true
	return false


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
		print("POC-17B AUTHORED HOLE PLAYABILITY PASSED")
		quit(0)
	else:
		push_error("POC-17B AUTHORED HOLE PLAYABILITY FAILED: %d" % failures)
		quit(1)
