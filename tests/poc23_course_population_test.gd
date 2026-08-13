extends SceneTree

const CourseDefinition = preload("res://simulation/course_definition.gd")
const CoursePopulation = preload("res://simulation/course_population.gd")
const Golfer = preload("res://scenes/golfer.gd")

var failures: int = 0
var created_golfers: Array = []


func _init() -> void:
	print("POC-23A: living course population foundation")

	var course = CourseDefinition.load_json("res://data/courses/poc12_proving_course.json")
	_assert_true(course != null, "three-hole proving course loads")
	if course == null:
		_finish()
		return

	var population = CoursePopulation.new()
	_assert_true(population.configure(course), "course population configures against authoritative CourseDefinition")

	var morning_twosome: Array = [
		_new_golfer(Golfer.GolferProfile.CAREFUL_CARL),
		_new_golfer(Golfer.GolferProfile.WILD_BILL)
	]
	var following_foursome: Array = [
		_new_golfer(Golfer.GolferProfile.RECKLESS_RICK),
		_new_golfer(Golfer.GolferProfile.CAREFUL_CARL),
		_new_golfer(Golfer.GolferProfile.WILD_BILL),
		_new_golfer(Golfer.GolferProfile.RECKLESS_RICK)
	]

	_assert_true(population.add_group("morning_twosome", morning_twosome), "twosome enters the course population")
	_assert_true(population.add_group("following_foursome", following_foursome), "foursome enters the same course population")
	_assert_false(population.add_group("morning_twosome", [following_foursome[0]]), "group ids are unique")
	_assert_false(population.add_group("illegal_overlap", [morning_twosome[0]]), "one golfer cannot belong to two groups")

	var twosome = population.group_by_id("morning_twosome")
	var foursome = population.group_by_id("following_foursome")
	_assert_true(twosome != null, "twosome is addressable by stable group identity")
	_assert_true(foursome != null, "foursome is addressable by stable group identity")
	if twosome == null or foursome == null:
		_finish()
		return

	_assert_equal(twosome.member_count(), 2, "twosome preserves two golfer members")
	_assert_equal(foursome.member_count(), 4, "foursome preserves four golfer members")
	_assert_equal(twosome.rounds.size(), 2, "each twosome golfer owns an independent authoritative round")
	_assert_equal(foursome.rounds.size(), 4, "each foursome golfer owns an independent authoritative round")
	_assert_true(twosome.rounds[0] != twosome.rounds[1], "group does not collapse golfers into one shared score state")
	_assert_equal(twosome.current_hole_number(), 1, "twosome begins on hole one")
	_assert_equal(foursome.current_hole_number(), 1, "foursome begins on hole one")

	var waiting_snapshot: Dictionary = population.snapshot()
	_assert_equal(int(waiting_snapshot.get("group_count", 0)), 2, "course population contains two simultaneous groups")
	_assert_equal(int(waiting_snapshot.get("golfer_count", 0)), 6, "course population contains six assigned golfers")
	_assert_equal(int(waiting_snapshot.get("waiting_groups", 0)), 2, "both groups begin waiting")
	_assert_equal(int(waiting_snapshot.get("playing_groups", 0)), 0, "no group is silently started")

	_assert_true(population.start_group("morning_twosome"), "first group can start independently")
	_assert_equal(twosome.status, "PLAYING", "started twosome becomes playing")
	_assert_equal(foursome.status, "WAITING", "second group remains independently waiting")
	_assert_false(population.start_group("morning_twosome"), "group cannot be started twice")
	_assert_true(population.start_group("following_foursome"), "second group can start later")

	var active_snapshot: Dictionary = population.snapshot()
	_assert_equal(int(active_snapshot.get("playing_groups", 0)), 2, "multiple groups can coexist as active course population")
	_assert_equal(int(active_snapshot.get("waiting_groups", 0)), 0, "both explicitly started groups leave waiting state")
	_assert_equal(twosome.current_hole_number(), 1, "starting population state does not mutate golfer round progress")
	_assert_equal(foursome.current_hole_number(), 1, "second group retains its own hole-one round state")

	print("POC23_POPULATION_SUMMARY groups=%d golfers=%d twosome_status=%s foursome_status=%s hole=%d" % [
		population.group_count(),
		population.golfer_count(),
		twosome.status,
		foursome.status,
		twosome.current_hole_number()
	])
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


func _assert_false(value: bool, label: String) -> void:
	_assert_true(not value, label)


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
		print("POC-23A LIVING COURSE POPULATION FOUNDATION PASSED")
		quit(0)
	else:
		push_error("POC-23A LIVING COURSE POPULATION FOUNDATION FAILED: %d" % failures)
		quit(1)
