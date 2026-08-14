extends SceneTree

const POC27Course = preload("res://simulation/poc27_eighteen_hole_course.gd")
const SpectatorCourseLayout = preload("res://simulation/spectator_course_layout.gd")
const ShotProgressiveLivingCourseController = preload("res://simulation/shot_progressive_living_course_controller.gd")

var failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("POC-27A: 18-hole course foundation")

	var course = POC27Course.build()
	_assert_true(course != null, "18-hole proving course builds through existing authored-course path")
	if course == null:
		_finish()
		return

	_assert_equal_int(course.hole_count(), 18, "course exposes exactly 18 ordered holes")
	_assert_equal_int(course.total_par(), 72, "course is a traditional par 72")
	_assert_near(course.total_yardage("default"), 7030.0, 0.001, "back-tee yardage derives from all 18 authored holes")
	_assert_near(course.total_yardage("forward"), 6310.0, 0.001, "forward-tee yardage derives from all 18 authored holes")
	_assert_true(course.total_yardage("forward") < course.total_yardage("default"), "forward tees remain meaningfully shorter")

	var par_counts := {3: 0, 4: 0, 5: 0}
	var water_holes: int = 0
	var bunker_holes: int = 0
	var ob_holes: int = 0
	var ordered_identity_ok: bool = true
	var lateral_variety_seen: bool = false
	var previous_pin_x: float = INF

	for hole_number in range(1, 19):
		var hole = course.hole_by_number(hole_number)
		if hole == null:
			ordered_identity_ok = false
			continue
		if int(hole.hole_number) != hole_number or str(hole.course_id) != POC27Course.COURSE_ID:
			ordered_identity_ok = false
		par_counts[int(hole.par)] = int(par_counts.get(int(hole.par), 0)) + 1

		var has_water: bool = false
		var has_bunker: bool = false
		for hazard_value in hole.hazards:
			var hazard: Dictionary = hazard_value
			if str(hazard.get("type", "")) == "WATER":
				has_water = true
			elif str(hazard.get("type", "")) == "BUNKER":
				has_bunker = true
		if has_water:
			water_holes += 1
		if has_bunker:
			bunker_holes += 1
		if not hole.out_of_bounds_regions.is_empty():
			ob_holes += 1

		if previous_pin_x != INF and absf(hole.pin_position.x - previous_pin_x) >= 4.0:
			lateral_variety_seen = true
		previous_pin_x = hole.pin_position.x

	_assert_true(ordered_identity_ok, "all 18 holes preserve ordered identity inside one course")
	_assert_equal_int(int(par_counts[3]), 4, "course contains four par 3s")
	_assert_equal_int(int(par_counts[4]), 10, "course contains ten par 4s")
	_assert_equal_int(int(par_counts[5]), 4, "course contains four par 5s")
	_assert_true(water_holes >= 6, "course contains repeated water decisions")
	_assert_true(bunker_holes == 18, "every hole contains authored bunker pressure")
	_assert_true(ob_holes >= 9, "course contains boundary pressure across both nines")
	_assert_true(lateral_variety_seen, "hole geometry varies laterally instead of repeating one straight template")

	var first = course.hole_by_number(1)
	var turn = course.hole_by_number(9)
	var restart = course.hole_by_number(10)
	var last = course.hole_by_number(18)
	_assert_true(first != null and turn != null and restart != null and last != null, "front nine, turn, back nine, and finish are addressable")
	if first != null and last != null:
		_assert_equal_string(str(first.hole_name), "Opening Statement", "round begins on authored Hole 1")
		_assert_equal_string(str(last.hole_name), "Home Stretch", "round ends on authored Hole 18")

	var layout = SpectatorCourseLayout.new()
	_assert_true(layout.configure(course), "existing spectator layout configures all 18 holes without special mode")
	_assert_equal_int(int(layout.snapshot().get("hole_count", 0)), 18, "presentation layout exposes all 18 authored holes")
	var non_overlapping: bool = true
	var previous_right: float = -INF
	for hole_number in range(1, 19):
		var bounds: Rect2 = layout.world_bounds(hole_number)
		if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
			non_overlapping = false
			continue
		if previous_right != -INF and bounds.position.x < previous_right - 0.0001:
			non_overlapping = false
		previous_right = bounds.position.x + bounds.size.x
	_assert_true(non_overlapping, "presentation-only world keeps all 18 hole bounds distinct")

	var runtime = ShotProgressiveLivingCourseController.new()
	_assert_true(runtime.configure(course), "existing shot-progressive living controller accepts the 18-hole course unchanged")
	_assert_true(runtime.course == course, "living-course authority retains the exact 18-hole CourseDefinition")
	_assert_equal_int(runtime.course.hole_count(), 18, "living-course authority sees all 18 holes")

	print("POC27A_COURSE_SUMMARY holes=%d par=%d back_yards=%.0f forward_yards=%.0f water_holes=%d bunker_holes=%d ob_holes=%d" % [
		course.hole_count(),
		course.total_par(),
		course.total_yardage("default"),
		course.total_yardage("forward"),
		water_holes,
		bunker_holes,
		ob_holes
	])
	_finish()


func _assert_true(value: bool, label: String) -> void:
	if value:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)


func _assert_equal_int(actual: int, expected: int, label: String) -> void:
	if actual == expected:
		print("PASS: %s (actual=%d expected=%d)" % [label, actual, expected])
	else:
		failures += 1
		push_error("FAIL: %s (actual=%d expected=%d)" % [label, actual, expected])


func _assert_equal_string(actual: String, expected: String, label: String) -> void:
	if actual == expected:
		print("PASS: %s (actual=%s expected=%s)" % [label, actual, expected])
	else:
		failures += 1
		push_error("FAIL: %s (actual=%s expected=%s)" % [label, actual, expected])


func _assert_near(actual: float, expected: float, tolerance: float, label: String) -> void:
	if absf(actual - expected) <= tolerance:
		print("PASS: %s (actual=%.3f expected=%.3f)" % [label, actual, expected])
	else:
		failures += 1
		push_error("FAIL: %s (actual=%.3f expected=%.3f)" % [label, actual, expected])


func _finish() -> void:
	if failures == 0:
		print("POC-27A 18-HOLE COURSE FOUNDATION PASSED")
		quit(0)
	else:
		push_error("POC-27A 18-HOLE COURSE FOUNDATION FAILED: %d" % failures)
		quit(1)
