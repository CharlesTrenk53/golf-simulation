extends SceneTree

const CourseDefinition = preload("res://simulation/course_definition.gd")
const LivingCourseController = preload("res://simulation/living_course_controller.gd")
const Golfer = preload("res://scenes/golfer.gd")

var failures := 0
var golfers: Array = []

func _init() -> void:
	print("POC-23D: authoritative living-course controller")
	var course = CourseDefinition.load_json("res://data/courses/poc12_proving_course.json")
	var controller = LivingCourseController.new()
	_check(course != null, "proving course loads")
	_check(controller.configure(course), "controller configures")
	_check(controller.add_group("lead", [_golfer(Golfer.GolferProfile.CAREFUL_CARL), _golfer(Golfer.GolferProfile.WILD_BILL)]), "lead group joins")
	_check(controller.add_group("follow", [_golfer(Golfer.GolferProfile.RECKLESS_RICK), _golfer(Golfer.GolferProfile.CAREFUL_CARL), _golfer(Golfer.GolferProfile.WILD_BILL)]), "following group joins")

	var initial := controller.snapshot()
	_check(int(initial.population.waiting_groups) == 2, "two groups begin waiting")
	_check(str(initial.start_sequence.next_waiting_group_id) == "lead", "lead is first release")

	_check(str(controller.release_next_group().get("group_id", "")) == "lead", "lead releases first")
	_check(bool(controller.play_group_current_hole("lead", 23001).get("completed", false)), "lead completes hole one")
	_check(int(controller.group_snapshot("lead").current_hole_number) == 2, "lead advances to hole two")
	_check(int(controller.group_snapshot("follow").current_hole_number) == 1, "follower remains on hole one")
	_check(controller.play_group_current_hole("follow", 23101).is_empty(), "waiting follower cannot play")

	_check(str(controller.release_next_group().get("group_id", "")) == "follow", "follower releases second")
	_check(bool(controller.play_group_current_hole("follow", 23201).get("completed", false)), "follower completes hole one")
	_check(int(controller.group_snapshot("follow").current_hole_number) == 2, "follower advances to hole two")
	_check(bool(controller.play_group_current_hole("lead", 23301).get("completed", false)), "lead completes hole two")
	_check(int(controller.group_snapshot("lead").current_hole_number) == 3, "lead advances independently to hole three")
	_check(int(controller.group_snapshot("follow").current_hole_number) == 2, "follower remains independently on hole two")

	var final := controller.snapshot()
	_check(int(final.population.playing_groups) == 2, "both released groups are playing")
	_check(int(final.start_sequence.released_count) == 2, "controller records both releases")
	print("POC23_LIVING_COURSE_SUMMARY lead_hole=%d follow_hole=%d playing=%d" % [controller.group_snapshot("lead").current_hole_number, controller.group_snapshot("follow").current_hole_number, final.population.playing_groups])
	_finish()

func _golfer(profile_value: int):
	var golfer = Golfer.new()
	golfer.profile = profile_value
	golfer.apply_profile()
	get_root().add_child(golfer)
	golfers.append(golfer)
	return golfer

func _check(value: bool, label: String) -> void:
	if value:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)

func _finish() -> void:
	for golfer in golfers:
		golfer.queue_free()
	if failures == 0:
		print("POC-23D AUTHORITATIVE LIVING-COURSE CONTROLLER PASSED")
		quit(0)
	else:
		quit(1)
