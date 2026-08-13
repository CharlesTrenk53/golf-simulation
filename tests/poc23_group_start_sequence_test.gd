extends SceneTree

const CourseDefinition = preload("res://simulation/course_definition.gd")
const CoursePopulation = preload("res://simulation/course_population.gd")
const GroupStartSequencer = preload("res://simulation/group_start_sequencer.gd")
const Golfer = preload("res://scenes/golfer.gd")

var failures: int = 0
var created_golfers: Array = []


func _init() -> void:
	print("POC-23C: ordered golfer-group start sequencing")

	var course = CourseDefinition.load_json("res://data/courses/poc12_proving_course.json")
	_assert_true(course != null, "three-hole proving course loads")
	if course == null:
		_finish()
		return

	var population = CoursePopulation.new()
	_assert_true(population.configure(course), "course population configures")
	_assert_true(population.add_group("early_twosome", _make_group([Golfer.GolferProfile.CAREFUL_CARL, Golfer.GolferProfile.WILD_BILL])), "early twosome joins waiting population")
	_assert_true(population.add_group("middle_threesome", _make_group([Golfer.GolferProfile.RECKLESS_RICK, Golfer.GolferProfile.CAREFUL_CARL, Golfer.GolferProfile.WILD_BILL])), "middle threesome joins waiting population")
	_assert_true(population.add_group("late_foursome", _make_group([Golfer.GolferProfile.WILD_BILL, Golfer.GolferProfile.RECKLESS_RICK, Golfer.GolferProfile.CAREFUL_CARL, Golfer.GolferProfile.WILD_BILL])), "late foursome joins waiting population")

	var sequencer = GroupStartSequencer.new()
	_assert_true(sequencer.configure(population), "start sequencer configures against authoritative population")
	_assert_array_equal(sequencer.waiting_group_ids(), ["early_twosome", "middle_threesome", "late_foursome"], "waiting queue preserves population insertion order")
	_assert_equal(sequencer.next_waiting_group_id(), "early_twosome", "first waiting group is next to start")

	var first_release: Dictionary = sequencer.start_next_waiting_group()
	_assert_equal(str(first_release.get("group_id", "")), "early_twosome", "first release starts earliest waiting group")
	_assert_equal(population.group_by_id("early_twosome").status, "PLAYING", "first group becomes playing")
	_assert_equal(population.group_by_id("middle_threesome").status, "WAITING", "second group remains waiting")
	_assert_equal(population.group_by_id("late_foursome").status, "WAITING", "third group remains waiting")
	_assert_equal(int(first_release.get("remaining_waiting", -1)), 2, "exactly two groups remain waiting after first release")

	var second_release: Dictionary = sequencer.start_next_waiting_group()
	_assert_equal(str(second_release.get("group_id", "")), "middle_threesome", "second release starts second waiting group")
	_assert_equal(population.group_by_id("middle_threesome").status, "PLAYING", "second group becomes playing")
	_assert_equal(population.group_by_id("late_foursome").status, "WAITING", "third group is not silently released")
	_assert_equal(sequencer.next_waiting_group_id(), "late_foursome", "third group becomes next in queue")

	var third_release: Dictionary = sequencer.start_next_waiting_group()
	_assert_equal(str(third_release.get("group_id", "")), "late_foursome", "third release starts final waiting group")
	_assert_equal(population.group_by_id("late_foursome").status, "PLAYING", "final group becomes playing")
	_assert_equal(int(third_release.get("remaining_waiting", -1)), 0, "no groups remain waiting after final release")
	_assert_true(sequencer.start_next_waiting_group().is_empty(), "sequencer does nothing when no waiting groups remain")

	var snapshot: Dictionary = sequencer.snapshot()
	_assert_equal(int(snapshot.get("released_count", 0)), 3, "sequencer records three explicit releases")
	_assert_array_equal(snapshot.get("released_group_ids", []), ["early_twosome", "middle_threesome", "late_foursome"], "release history preserves deterministic start order")
	_assert_equal(int(population.snapshot().get("playing_groups", 0)), 3, "population reports all three groups playing after explicit releases")
	_assert_equal(population.group_by_id("early_twosome").current_hole_number(), 1, "starting groups does not advance golf simulation")
	_assert_equal(population.group_by_id("middle_threesome").current_hole_number(), 1, "middle group remains on first hole before play")
	_assert_equal(population.group_by_id("late_foursome").current_hole_number(), 1, "late group remains on first hole before play")

	print("POC23_START_SEQUENCE_SUMMARY releases=%s waiting=%d playing=%d" % [
		str(snapshot.get("released_group_ids", [])),
		sequencer.waiting_group_ids().size(),
		int(population.snapshot().get("playing_groups", 0))
	])
	_finish()


func _make_group(profile_values: Array) -> Array:
	var golfers: Array = []
	for profile_value in profile_values:
		var golfer = Golfer.new()
		golfer.profile = int(profile_value)
		golfer.apply_profile()
		get_root().add_child(golfer)
		created_golfers.append(golfer)
		golfers.append(golfer)
	return golfers


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


func _assert_array_equal(actual: Array, expected: Array, label: String) -> void:
	if actual == expected:
		print("PASS: %s (actual=%s expected=%s)" % [label, str(actual), str(expected)])
	else:
		failures += 1
		push_error("FAIL: %s (actual=%s expected=%s)" % [label, str(actual), str(expected)])


func _finish() -> void:
	for golfer in created_golfers:
		if golfer != null:
			golfer.queue_free()
	if failures == 0:
		print("POC-23C ORDERED GOLFER-GROUP START SEQUENCING PASSED")
		quit(0)
	else:
		push_error("POC-23C ORDERED GOLFER-GROUP START SEQUENCING FAILED: %d" % failures)
		quit(1)
