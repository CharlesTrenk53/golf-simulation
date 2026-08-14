extends SceneTree

const CourseDefinition = preload("res://simulation/course_definition.gd")
const CourseTrafficState = preload("res://simulation/course_traffic_state.gd")

var failures: int = 0

func _init() -> void:
	print("POC-24A: authoritative course occupancy and waiting queues")

	var course = CourseDefinition.load_json("res://data/courses/poc12_proving_course.json")
	_assert_true(course != null, "three-hole proving course loads")
	if course == null:
		_finish()
		return

	var traffic = CourseTrafficState.new()
	_assert_true(traffic.configure(course), "traffic state configures against authoritative course")

	var lead_entry: Dictionary = traffic.request_hole_entry("lead_group", 1)
	_assert_true(bool(lead_entry.get("allowed", false)), "lead group occupies open first hole")
	_assert_equal(traffic.occupant_for_hole(1), "lead_group", "first hole records lead occupancy")

	var follower_entry: Dictionary = traffic.request_hole_entry("following_group", 1)
	_assert_false(bool(follower_entry.get("allowed", true)), "following group cannot enter occupied hole")
	_assert_equal(str(follower_entry.get("status", "")), "WAITING", "blocked follower becomes waiting")
	_assert_equal(str(follower_entry.get("occupant_group_id", "")), "lead_group", "blocked request identifies group ahead")
	_assert_equal(int(follower_entry.get("queue_position", 0)), 1, "first blocked group receives queue position one")

	var third_entry: Dictionary = traffic.request_hole_entry("third_group", 1)
	_assert_equal(int(third_entry.get("queue_position", 0)), 2, "second blocked group queues behind first follower")
	_assert_equal(traffic.waiting_group_ids(1), ["following_group", "third_group"], "hole waiting queue preserves FIFO order")

	var repeated_request: Dictionary = traffic.request_hole_entry("following_group", 1)
	_assert_equal(str(repeated_request.get("status", "")), "WAITING", "repeat request preserves existing waiting state")
	_assert_equal(traffic.waiting_group_ids(1), ["following_group", "third_group"], "repeat request does not duplicate queue membership")
	_assert_false(traffic.release_hole("following_group", 1), "waiting group cannot release another group's hole")

	_assert_true(traffic.release_hole("lead_group", 1), "lead group can release its occupied hole")
	_assert_equal(traffic.occupant_for_hole(1), "", "released hole becomes open")

	var admitted_follower: Dictionary = traffic.admit_next_waiting(1)
	_assert_equal(str(admitted_follower.get("group_id", "")), "following_group", "first waiting group is admitted next")
	_assert_equal(traffic.occupant_for_hole(1), "following_group", "admitted follower becomes hole occupant")
	_assert_equal(traffic.waiting_group_ids(1), ["third_group"], "third group remains waiting")

	var lead_second_hole: Dictionary = traffic.request_hole_entry("lead_group", 2)
	_assert_true(bool(lead_second_hole.get("allowed", false)), "lead group can occupy next hole while follower occupies previous hole")
	_assert_equal(traffic.occupant_for_hole(2), "lead_group", "second hole independently records lead occupancy")
	_assert_equal(traffic.group_hole("lead_group"), 2, "traffic state tracks lead course position")
	_assert_equal(traffic.group_hole("following_group"), 1, "traffic state tracks follower behind lead")

	var snapshot: Dictionary = traffic.snapshot()
	_assert_equal(int(snapshot.get("occupied_hole_count", 0)), 2, "two different holes can be simultaneously occupied")
	_assert_equal(int(snapshot.get("waiting_group_count", 0)), 1, "one group remains blocked in traffic")

	_assert_true(traffic.release_hole("following_group", 1), "follower eventually clears first hole")
	var admitted_third: Dictionary = traffic.admit_next_waiting(1)
	_assert_equal(str(admitted_third.get("group_id", "")), "third_group", "next queued group advances after hole clears")
	_assert_equal(traffic.occupant_for_hole(1), "third_group", "third group now owns first-hole occupancy")
	_assert_equal(traffic.waiting_group_ids(1), [], "first-hole queue drains after final admission")

	print("POC24_TRAFFIC_SUMMARY hole1=%s hole2=%s waiting=%d" % [
		traffic.occupant_for_hole(1),
		traffic.occupant_for_hole(2),
		int(traffic.snapshot().get("waiting_group_count", 0))
	])
	_finish()

func _assert_true(value: bool, label: String) -> void:
	if value:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)

func _assert_false(value: bool, label: String) -> void:
	_assert_true(not value, label)

func _assert_equal(actual, expected, label: String) -> void:
	if actual == expected:
		print("PASS: %s (actual=%s expected=%s)" % [label, str(actual), str(expected)])
	else:
		failures += 1
		push_error("FAIL: %s (actual=%s expected=%s)" % [label, str(actual), str(expected)])

func _finish() -> void:
	if failures == 0:
		print("POC-24A COURSE OCCUPANCY AND WAITING QUEUES PASSED")
		quit(0)
	else:
		push_error("POC-24A COURSE OCCUPANCY AND WAITING QUEUES FAILED: %d" % failures)
		quit(1)
