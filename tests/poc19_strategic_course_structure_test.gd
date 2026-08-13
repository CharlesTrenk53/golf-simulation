extends SceneTree

const StrategicCourseFixture = preload("res://tests/fixtures/poc19_strategic_course_fixture.gd")

var failures: int = 0


func _init() -> void:
	print("POC-19A: strategic proving course structure")
	var fixture = StrategicCourseFixture.new()
	var course = fixture.build_course()
	_assert_true(course != null, "strategic proving course builds")
	if course == null:
		_finish()
		return

	_assert_equal(course.hole_count(), 18, "course contains 18 holes")
	_assert_equal(course.total_par(), 72, "course totals par 72")
	_assert_true(course.total_yardage("back") > 6800.0, "course has full-length back-tee yardage")
	_assert_equal(fixture.strategic_hole_numbers().size(), 9, "course contains nine designated strategic holes")
	_assert_equal(fixture.water_hole_numbers().size(), 5, "course contains five water-choice holes")
	_assert_equal(fixture.bunker_hole_numbers().size(), 4, "course contains four bunker-bailout holes")

	var par3_count := 0
	var par4_count := 0
	var par5_count := 0
	var water_holes := 0
	var bunker_holes := 0
	for hole in course.holes:
		match int(hole.par):
			3:
				par3_count += 1
			4:
				par4_count += 1
			5:
				par5_count += 1
		var has_water := false
		var has_bunker := false
		for hazard in hole.hazards:
			var hazard_type := str(hazard.get("type", "")).to_upper()
			if hazard_type == "WATER":
				has_water = true
			elif hazard_type == "BUNKER":
				has_bunker = true
		if has_water:
			water_holes += 1
		if has_bunker:
			bunker_holes += 1

	_assert_equal(par3_count, 4, "course retains four par 3s")
	_assert_equal(par4_count, 10, "course retains ten par 4s")
	_assert_equal(par5_count, 4, "course retains four par 5s")
	_assert_equal(water_holes, 5, "authored definitions retain five water-choice holes")
	_assert_equal(bunker_holes, 4, "authored definitions retain four bunker-bailout holes")

	print("POC19_COURSE_SUMMARY holes=%d par=%d yardage=%.0f strategic=%d water=%d bunker=%d" % [
		course.hole_count(),
		course.total_par(),
		course.total_yardage("back"),
		fixture.strategic_hole_numbers().size(),
		water_holes,
		bunker_holes
	])
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
		print("POC-19A STRATEGIC PROVING COURSE STRUCTURE PASSED")
		quit(0)
	else:
		push_error("POC-19A STRATEGIC PROVING COURSE STRUCTURE FAILED: %d" % failures)
		quit(1)
