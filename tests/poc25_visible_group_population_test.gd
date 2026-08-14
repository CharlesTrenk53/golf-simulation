extends SceneTree

const CourseDefinition = preload("res://simulation/course_definition.gd")
const SpacingAwareTimedCourseController = preload("res://simulation/spacing_aware_timed_course_controller.gd")
const SpectatorCourseWorld = preload("res://scenes/spectator_course_world.gd")
const SpectatorPopulationView = preload("res://scenes/spectator_population_view.gd")
const Golfer = preload("res://scenes/golfer.gd")


func _init() -> void:
	var course = CourseDefinition.load_json("res://data/courses/poc12_proving_course.json")
	assert(course != null)

	var controller = SpacingAwareTimedCourseController.new()
	assert(controller.configure(course))
	var lead_a = _golfer(Golfer.GolferProfile.CAREFUL_CARL)
	var lead_b = _golfer(Golfer.GolferProfile.CAREFUL_CARL)
	var follow_a = _golfer(Golfer.GolferProfile.WILD_BILL)
	var follow_b = _golfer(Golfer.GolferProfile.WILD_BILL)
	assert(controller.add_group("group_1", [lead_a, lead_b]))
	assert(controller.add_group("group_2", [follow_a, follow_b]))

	var release: Dictionary = controller.release_next_group()
	assert(bool(release.get("released", false)))
	assert(str(release.get("group_id", "")) == "group_1")
	assert(controller.traffic.group_hole("group_1") == 1)
	assert(controller.traffic.group_hole("group_2") == 0)

	var world = SpectatorCourseWorld.new()
	get_root().add_child(world)
	assert(world.configure(course))
	var view = SpectatorPopulationView.new()
	get_root().add_child(view)
	assert(view.configure(world, controller))

	var group_1 = view.group_visual("group_1")
	var group_2 = view.group_visual("group_2")
	assert(group_1 != null and group_2 != null)
	assert(group_1.projected_status == "PLAYING")
	assert(group_1.projected_hole_number == 1)
	assert(group_2.projected_status == "WAITING")
	assert(group_2.projected_hole_number == 1)
	assert(group_1.member_visuals.size() == 2)
	assert(group_2.member_visuals.size() == 2)

	var lead_positions: Array = group_1.member_world_positions()
	var waiting_positions: Array = group_2.member_world_positions()
	assert(lead_positions.size() == 2 and waiting_positions.size() == 2)
	assert(lead_positions[0].distance_to(lead_positions[1]) > 0.1)
	assert(waiting_positions[0].distance_to(waiting_positions[1]) > 0.1)
	var lead_center: Vector3 = (lead_positions[0] + lead_positions[1]) * 0.5
	var waiting_center: Vector3 = (waiting_positions[0] + waiting_positions[1]) * 0.5
	assert(lead_center.distance_to(waiting_center) > 1.0)

	var group_1_snapshot: Dictionary = group_1.snapshot()
	var group_2_snapshot: Dictionary = group_2.snapshot()
	assert(int(group_1_snapshot.get("traffic_hole_number", 0)) == 1)
	assert(int(group_2_snapshot.get("traffic_hole_number", -1)) == 0)
	assert(str(group_1_snapshot.get("status", "")) == "PLAYING")
	assert(str(group_2_snapshot.get("status", "")) == "WAITING")
	assert(controller.traffic.group_hole("group_1") == 1)
	assert(controller.traffic.group_hole("group_2") == 0)

	print("POC25_GROUP_SUMMARY lead=%s waiting=%s" % [str(lead_center), str(waiting_center)])
	print("POC-25B VISIBLE TWO-GROUP POPULATION PASSED")
	view.queue_free()
	world.queue_free()
	lead_a.queue_free();lead_b.queue_free();follow_a.queue_free();follow_b.queue_free()
	quit(0)


func _golfer(profile_value: int):
	var golfer = Golfer.new()
	golfer.profile = profile_value
	golfer.apply_profile()
	get_root().add_child(golfer)
	return golfer
