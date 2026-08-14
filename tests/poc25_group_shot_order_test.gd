extends SceneTree

const CourseDefinition = preload("res://simulation/course_definition.gd")
const GroupShotOrderModel = preload("res://simulation/group_shot_order_model.gd")


func _init() -> void:
	var course = CourseDefinition.load_json("res://data/courses/poc12_proving_course.json")
	assert(course != null)
	var hole = course.hole_by_number(1)
	assert(hole != null)
	var tee: Vector3 = hole.tee_position("default")
	var pin: Vector3 = hole.pin_position
	var direction: Vector3 = pin - tee
	direction.y = 0.0
	direction = direction.normalized()

	var member_0_first: Vector3 = tee + direction * 250.0
	var member_1_first: Vector3 = tee + direction * 180.0
	var member_1_second: Vector3 = tee + direction * 350.0
	var member_0_second: Vector3 = tee + direction * 360.0
	var result := {
		"member_results": [
			{"member_index": 0, "history": [
				{"shot_number": 1, "start_position": tee, "landing_position": member_0_first, "relief_position": member_0_first},
				{"shot_number": 2, "start_position": member_0_first, "landing_position": member_0_second, "relief_position": member_0_second}
			]},
			{"member_index": 1, "history": [
				{"shot_number": 1, "start_position": tee, "landing_position": member_1_first, "relief_position": member_1_first},
				{"shot_number": 2, "start_position": member_1_first, "landing_position": member_1_second, "relief_position": member_1_second}
			]}
		]
	}

	var model = GroupShotOrderModel.new()
	var order: Array = model.build_order(result, hole, "default")
	assert(order.size() == 4)
	assert(int(order[0].get("member_index", -1)) == 0 and int(order[0].get("shot_index", -1)) == 0)
	assert(int(order[1].get("member_index", -1)) == 1 and int(order[1].get("shot_index", -1)) == 0)
	# Member 1 remains farther from the pin after both tee shots, so that golfer
	# correctly plays again before member 0's second shot.
	assert(int(order[2].get("member_index", -1)) == 1 and int(order[2].get("shot_index", -1)) == 1)
	assert(int(order[3].get("member_index", -1)) == 0 and int(order[3].get("shot_index", -1)) == 1)
	assert(float(order[2].get("distance_to_hole_yards", 0.0)) > float(order[3].get("distance_to_hole_yards", 0.0)))

	print("POC25_ORDER_SUMMARY sequence=%s" % str([
		"0:1", "1:1", "1:2", "0:2"
	]))
	print("POC-25D FARTHEST-FROM-HOLE GROUP SHOT ORDER PASSED")
	quit(0)
