extends SceneTree

const POC33VisualTargetDemo = preload("res://scenes/poc33_isometric_visual_target_demo.gd")

var failures: int = 0


func _init() -> void:
	print("POC-33E: dense miniature-course visual target")
	call_deferred("_run")


func _run() -> void:
	var demo = POC33VisualTargetDemo.new()
	demo.auto_advance = false
	get_root().add_child(demo)
	_assert_true(demo.initialized, "visual-target scene initializes inherited authoritative living course")
	if not demo.initialized:
		demo.queue_free()
		_finish()
		return

	var visual: Dictionary = demo.visual_snapshot()
	var polish: Dictionary = visual.get("polish", {})
	var art: Dictionary = visual.get("golfer_art", {})
	var counts: Dictionary = polish.get("counts", {})
	var tree_count: int = int(counts.get("TREE", 0)) + int(counts.get("PINE", 0)) + int(counts.get("FLOWERING_TREE", 0))

	_assert_true(bool(polish.get("configured", false)), "environment polish layer configures over authoritative grid")
	_assert_true(int(polish.get("decoration_count", 0)) > 120, "visual target creates dense environmental dressing")
	_assert_true(tree_count > 70, "visual target contains clustered tree canopy density")
	_assert_true(int(counts.get("FLOWERING_TREE", 0)) > 0, "visual target includes flowering accent trees")
	_assert_true(int(counts.get("SHRUB", 0)) > 0, "visual target includes shrub understory")
	_assert_true(int(counts.get("FLOWERS", 0)) >= 4, "clubhouse landscape includes flower accents")
	var clubhouse: Vector2 = polish.get("clubhouse_grid", Vector2(-1.0, -1.0))
	_assert_true(clubhouse.x >= 0.0 and clubhouse.y >= 0.0, "visual target locates a rough-ground clubhouse landmark")
	_assert_true(int(polish.get("path_points", 0)) >= 2, "visual target connects clubhouse with a presentation path")

	_assert_true(bool(visual.get("placeholder_layer_hidden", false)), "placeholder stick-golfer rendering is hidden")
	_assert_true(bool(art.get("configured", false)), "stylized golfer art layer configures")
	_assert_equal(int(art.get("source_golfers", 0)), 6, "stylized art reads all authoritative projected golfers")
	_assert_equal(int(art.get("source_balls", 0)), 6, "stylized art reads all authoritative runtime balls")
	_assert_true(int(art.get("visible_golfers", 0)) > 0, "on-property golfers remain visible in miniature art pass")
	_assert_true(float(visual.get("visual_zoom", 0.0)) >= 0.49, "visual target uses closer management-game framing")

	var grid_before: Dictionary = demo.grid.to_dictionary()
	_assert_true(demo.rotate_view(1), "visual target preserves accepted cardinal camera rotation")
	var rotated: Dictionary = demo.visual_snapshot()
	_assert_equal(int(rotated.get("polish", {}).get("rotation_quarters", -1)), 1, "environment polish follows rotated projection basis")
	_assert_equal(int(rotated.get("golfer_art", {}).get("source_golfers", 0)), 6, "stylized golfer identities survive camera rotation")
	_assert_true(demo.grid.to_dictionary() == grid_before, "visual-quality pass never mutates authoritative construction terrain")

	print("POC33E_VISUAL_TARGET_SUMMARY decorations=%d trees=%d shrubs=%d flowers=%d visible_golfers=%d zoom=%.2f clubhouse=%s" % [
		int(polish.get("decoration_count", 0)),
		tree_count,
		int(counts.get("SHRUB", 0)),
		int(counts.get("FLOWERS", 0)),
		int(art.get("visible_golfers", 0)),
		float(visual.get("visual_zoom", 0.0)),
		str(clubhouse)
	])

	demo.queue_free()
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
		print("POC-33E DENSE MINIATURE-COURSE VISUAL TARGET PASSED")
		quit(0)
	else:
		push_error("POC-33E DENSE MINIATURE-COURSE VISUAL TARGET FAILED: %d" % failures)
		quit(1)
