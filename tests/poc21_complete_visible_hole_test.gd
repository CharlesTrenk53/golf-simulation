extends SceneTree

const HoleAuthoringModel = preload("res://simulation/hole_authoring_model.gd")
const Golfer = preload("res://scenes/golfer.gd")
const PlayableHoleRuntime = preload("res://scenes/playable_hole_runtime.gd")

var failures: int = 0


func _init() -> void:
	print("POC-21D: one complete visible hole")
	var hole = _build_hole()
	_assert_true(hole != null, "authored playable hole builds")
	if hole == null:
		_finish()
		return

	var golfer = Golfer.new()
	golfer.profile = Golfer.GolferProfile.WILD_BILL
	golfer.apply_profile()
	get_root().add_child(golfer)

	var runtime = PlayableHoleRuntime.new()
	get_root().add_child(runtime)
	_assert_true(runtime.configure(hole, golfer, "back", 21021), "runtime configures authored hole and golfer")
	_assert_true(runtime.renderer != null, "runtime creates authoritative course renderer")
	_assert_true(runtime.ball_visual != null, "runtime creates visible ball")
	_assert_true(runtime.golfer_visual != null, "runtime creates visible golfer")
	_assert_vector_close(runtime.ball_visual.course_position, hole.tee_position("back"), "ball begins on authored tee")
	_assert_vector_close(runtime.golfer_visual.course_position, hole.tee_position("back"), "golfer begins on authored tee")

	var summary: Dictionary = runtime.play_to_completion(false)
	_assert_true(bool(summary.get("finished", false)), "autonomous golfer completes the visible hole")
	_assert_true(int(summary.get("strokes", 0)) > 0, "completed hole records strokes")
	_assert_equal(int(summary.get("strokes", 0)), runtime.state.strokes, "visible runtime score matches authoritative simulation state")
	_assert_equal(int(summary.get("par", 0)), hole.par, "visible runtime preserves authored par")
	_assert_equal(int(summary.get("shots_presented", 0)), runtime.presented_history.size(), "every presented shot is recorded")
	_assert_equal(runtime.presented_history.size(), runtime.playable.autonomous.shot_history.size(), "every authoritative simulated shot is presented")
	_assert_vector_close(summary.get("visual_ball_position", Vector3.ZERO), runtime.state.ball_position, "visible ball finishes at authoritative final lie")
	_assert_vector_close(summary.get("visual_golfer_position", Vector3.ZERO), runtime.state.ball_position, "visible golfer finishes at authoritative final lie")

	var sequence_consistent := true
	var previous_resolved: Vector3 = hole.tee_position("back")
	for item_value in runtime.presented_history:
		var item: Dictionary = item_value
		if item.get("start_position", Vector3.ZERO).distance_to(previous_resolved) > 0.001:
			sequence_consistent = false
			break
		previous_resolved = item.get("resolved_position", Vector3.ZERO)
	_assert_true(sequence_consistent, "visible shot sequence follows authoritative lie-to-lie progression")

	print("POC21_VISIBLE_HOLE_SUMMARY golfer=%s strokes=%d par=%d shots=%d final=%s" % [
		golfer.golfer_name,
		int(summary.get("strokes", 0)),
		int(summary.get("par", 0)),
		int(summary.get("shots_presented", 0)),
		str(summary.get("ball_position", Vector3.ZERO))
	])

	runtime.queue_free()
	golfer.queue_free()
	_finish()


func _build_hole():
	var author = HoleAuthoringModel.new()
	author.configure_identity("poc21_playable_runtime", 4, "Runtime Proof", 4, 390.0)
	author.add_tee("back", "Back", Vector3(0.0, 0.0, 390.0), 390.0)
	author.set_pin(Vector3(4.0, 0.0, 0.0))
	author.set_green(_rect(-22.0, -20.0, 26.0, 22.0))
	author.add_surface_region("fairway", "Fairway", "FAIRWAY", PackedVector2Array([
		Vector2(-38.0, 24.0), Vector2(36.0, 24.0), Vector2(34.0, 360.0), Vector2(-32.0, 360.0)
	]))
	author.add_surface_region("tee", "Tee", "TEE", _rect(-10.0, 378.0, 10.0, 402.0))
	author.add_hazard("right_bunker", "Right Bunker", "BUNKER", _rect(18.0, 28.0, 34.0, 60.0), 0, "")
	return author.build_definition()


func _rect(left: float, near_z: float, right: float, far_z: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(left, near_z), Vector2(right, near_z), Vector2(right, far_z), Vector2(left, far_z)
	])


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


func _assert_vector_close(actual: Vector3, expected: Vector3, label: String) -> void:
	if actual.distance_to(expected) <= 0.001:
		print("PASS: %s (actual=%s expected=%s)" % [label, str(actual), str(expected)])
	else:
		failures += 1
		push_error("FAIL: %s (actual=%s expected=%s)" % [label, str(actual), str(expected)])


func _finish() -> void:
	if failures == 0:
		print("POC-21D ONE COMPLETE VISIBLE HOLE PASSED")
		quit(0)
	else:
		push_error("POC-21D ONE COMPLETE VISIBLE HOLE FAILED: %d" % failures)
		quit(1)
