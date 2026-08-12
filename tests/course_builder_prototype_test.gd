extends SceneTree

var failures: int = 0


func _init() -> void:
	print("POC-17E: developer course builder prototype")
	var scene: PackedScene = load("res://tools/course_builder/course_builder.tscn")
	_expect(scene != null, "course builder scene loads")
	if scene == null:
		_finish()
		return

	var builder = scene.instantiate()
	root.add_child(builder)
	await process_frame

	builder.begin_draw(builder.DrawMode.FAIRWAY)
	builder.add_canvas_point(Vector2(250, 640))
	builder.add_canvas_point(Vector2(390, 640))
	builder.add_canvas_point(Vector2(430, 210))
	builder.add_canvas_point(Vector2(215, 210))
	_expect(builder.finish_shape(), "fairway polygon can be completed from canvas points")

	builder.begin_draw(builder.DrawMode.GREEN)
	builder.add_canvas_point(Vector2(275, 120))
	builder.add_canvas_point(Vector2(365, 120))
	builder.add_canvas_point(Vector2(380, 175))
	builder.add_canvas_point(Vector2(265, 175))
	_expect(builder.finish_shape(), "green polygon can be completed from canvas points")

	builder.begin_draw(builder.DrawMode.WATER)
	builder.add_canvas_point(Vector2(205, 315))
	builder.add_canvas_point(Vector2(285, 315))
	builder.add_canvas_point(Vector2(295, 385))
	builder.add_canvas_point(Vector2(190, 385))
	_expect(builder.finish_shape(), "water polygon can be completed from canvas points")

	builder.set_meta("place_tee", true)
	builder.add_canvas_point(Vector2(320, 680))
	builder.set_meta("place_pin", true)
	builder.add_canvas_point(Vector2(320, 145))

	var snapshot: Dictionary = builder.authored_snapshot()
	_expect(bool(snapshot.get("valid", false)), "visual builder produces a valid HoleDefinition")
	_expect_equal(int(snapshot.get("surfaces", 0)), 1, "visual builder authors one fairway")
	_expect_equal(int(snapshot.get("hazards", 0)), 1, "visual builder authors one water hazard")
	_expect_equal(int(snapshot.get("green_points", 0)), 4, "visual builder authors a green polygon")
	_expect_equal(int(snapshot.get("tees", 0)), 1, "visual builder preserves one tee")

	var definition = builder.authored_definition()
	_expect(definition != null, "visual prototype round-trips through HoleDefinition")
	if definition != null:
		_expect(definition.tee_position("back") != Vector3.ZERO, "placed tee reaches authored definition")
		_expect(definition.pin_position != Vector3.ZERO, "placed pin reaches authored definition")
		_expect(str(definition.hazards[0].get("type", "")) == "WATER", "drawn water remains classified as WATER")

	builder.queue_free()
	await process_frame
	_finish()


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		failures += 1
		push_error("FAIL: %s" % label)


func _expect_equal(actual, expected, label: String) -> void:
	if actual == expected:
		print("PASS: %s (actual=%s expected=%s)" % [label, str(actual), str(expected)])
	else:
		failures += 1
		push_error("FAIL: %s (actual=%s expected=%s)" % [label, str(actual), str(expected)])


func _finish() -> void:
	if failures == 0:
		print("POC-17E COURSE BUILDER PROTOTYPE PASSED")
		quit(0)
	else:
		push_error("POC-17E COURSE BUILDER PROTOTYPE FAILED: %d" % failures)
		quit(1)
