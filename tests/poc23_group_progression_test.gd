extends SceneTree

const CourseDefinition = preload("res://simulation/course_definition.gd")
const CoursePopulation = preload("res://simulation/course_population.gd")
const GroupProgressionCoordinator = preload("res://simulation/group_progression_coordinator.gd")
const Golfer = preload("res://scenes/golfer.gd")

var failures: int = 0
var created_golfers: Array = []


func _init() -> void:
	print("POC-23B: independent golfer-group course progression")
	var course = CourseDefinition.load_json("res://data/courses/poc12_proving_course.json")
	_assert_true(course != null, "three-hole proving course loads")
	if course == null:
		_finish()
		return

	var population = CoursePopulation.new()
	_assert_true(population.configure(course), "course population configures")
	var lead_golfers: Array = [_new_golfer(Golfer.GolferProfile.CAREFUL_CARL), _new_golfer(Golfer.GolferProfile.WILD_BILL)]
	var following_golfers: Array = [_new_golfer(Golfer.GolferProfile.RECKLESS_RICK), _new_golfer(Golfer.GolferProfile.CAREFUL_CARL), _new_golfer(Golfer.GolferProfile.WILD_BILL)]
	_assert_true(population.add_group("lead", lead_golfers), "lead twosome enters population")
	_assert_true(population.add_group("following", following_golfers), "following threesome enters population")
	_assert_true(population.start_group("lead"), "lead group starts")
	_assert_true(population.start_group("following"), "following group starts")

	var lead = population.group_by_id("lead")
	var following = population.group_by_id("following")
	var coordinator = GroupProgressionCoordinator.new()
	_assert_equal(lead.current_hole_number(), 1, "lead begins on hole one")
	_assert_equal(following.current_hole_number(), 1, "following begins on hole one")

	var lead_one: Dictionary = coordinator.play_current_hole(lead, 23001)
	_assert_true(bool(lead_one.get("completed", false)), "lead group completes hole one")
	_assert_equal(int(lead_one.get("member_results", []).size()), 2, "lead group records one authoritative result per golfer")
	_assert_equal(lead.current_hole_number(), 2, "lead advances to hole two")
	_assert_equal(following.current_hole_number(), 1, "following remains independently on hole one")
	_assert_equal(lead.rounds[0].round_state.holes_completed(), 1, "lead golfer one owns one completed hole")
	_assert_equal(lead.rounds[1].round_state.holes_completed(), 1, "lead golfer two owns one completed hole")
	_assert_equal(following.rounds[0].round_state.holes_completed(), 0, "lead play does not mutate following group")

	var following_one: Dictionary = coordinator.play_current_hole(following, 23101)
	_assert_true(bool(following_one.get("completed", false)), "following group progresses independently")
	_assert_equal(following.current_hole_number(), 2, "following advances to hole two")

	_assert_true(bool(coordinator.play_current_hole(lead, 23201).get("completed", false)), "lead completes hole two")
	_assert_equal(lead.current_hole_number(), 3, "lead advances to hole three")
	_assert_equal(following.current_hole_number(), 2, "following remains on hole two")

	_assert_true(bool(coordinator.play_current_hole(lead, 23301).get("completed", false)), "lead completes final hole")
	_assert_equal(lead.status, "FINISHED", "lead becomes finished after every member finishes")
	_assert_equal(lead.current_hole_number(), 0, "finished lead group has no active hole")
	_assert_equal(following.status, "PLAYING", "following remains active")
	_assert_equal(following.current_hole_number(), 2, "following retains independent course position")
	_assert_equal(lead.rounds[0].round_state.holes_completed(), 3, "lead golfer one completed all holes")
	_assert_equal(lead.rounds[1].round_state.holes_completed(), 3, "lead golfer two completed all holes")
	_assert_equal(following.rounds[0].round_state.holes_completed(), 1, "following golfer remains one hole into course")

	var snapshot: Dictionary = population.snapshot()
	_assert_equal(int(snapshot.get("finished_groups", 0)), 1, "population reports one finished group")
	_assert_equal(int(snapshot.get("playing_groups", 0)), 1, "population reports one still-playing group")
	_assert_true(coordinator.play_current_hole(lead, 23401).is_empty(), "finished group cannot play another hole")

	print("POC23_GROUP_PROGRESS_SUMMARY lead_status=%s following_status=%s following_hole=%d" % [lead.status, following.status, following.current_hole_number()])
	_finish()


func _new_golfer(profile_value: int):
	var golfer = Golfer.new()
	golfer.profile = profile_value
	golfer.apply_profile()
	get_root().add_child(golfer)
	created_golfers.append(golfer)
	return golfer


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
	for golfer in created_golfers:
		if golfer != null:
			golfer.queue_free()
	if failures == 0:
		print("POC-23B INDEPENDENT GOLFER-GROUP PROGRESSION PASSED")
		quit(0)
	else:
		push_error("POC-23B INDEPENDENT GOLFER-GROUP PROGRESSION FAILED: %d" % failures)
		quit(1)
