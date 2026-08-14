extends SceneTree

const CourseDefinition = preload("res://simulation/course_definition.gd")
const GroupTeeOrderModel = preload("res://simulation/group_tee_order_model.gd")
const GroupShotOrderModel = preload("res://simulation/group_shot_order_model.gd")


func _init() -> void:
	var course = CourseDefinition.load_json("res://data/courses/poc12_proving_course.json")
	assert(course != null)
	var hole = course.hole_by_number(1)
	assert(hole != null)

	var tee_model = GroupTeeOrderModel.new()
	var opening_a: Array = tee_model.first_tee_order(4, 25001)
	var opening_b: Array = tee_model.first_tee_order(4, 25001)
	assert(opening_a == opening_b)
	assert(tee_model.is_valid_order(opening_a, 4))

	# Member 1 wins honors with 3. Members 2 and 3 tie with 4 and retain their
	# relative order from the prior tee (3 before 2). Member 0's 5 goes last.
	var previous_scores: Array = [5, 3, 4, 4]
	var previous_tee_order: Array = [3, 0, 2, 1]
	var honors: Array = tee_model.honors_order(previous_scores, previous_tee_order)
	assert(honors == [1, 3, 2, 0])

	var tee: Vector3 = hole.tee_position("default")
	var pin: Vector3 = hole.pin_position
	var forward: Vector3 = pin - tee
	forward.y = 0.0
	forward = forward.normalized()
	var member_results: Array = []
	var first_landings: Array = [
		tee + forward * 120.0,
		tee + forward * 220.0,
		tee + forward * 190.0,
		tee + forward * 200.0
	]
	for member_index in range(4):
		var first: Vector3 = first_landings[member_index]
		var second: Vector3 = first + forward * 80.0
		member_results.append({
			"member_index": member_index,
			"history": [
				{"shot_number": 1, "start_position": tee, "landing_position": first, "relief_position": first, "club_id": "DRIVER"},
				{"shot_number": 2, "start_position": first, "landing_position": second, "relief_position": second, "club_id": "IRON"}
			]
		})

	var shot_model = GroupShotOrderModel.new()
	var order: Array = shot_model.build_order({
		"tee_order": honors,
		"member_results": member_results
	}, hole, "default")
	assert(order.size() == 8)
	for index in range(4):
		assert(int(order[index].get("member_index", -1)) == int(honors[index]))
		assert(int(order[index].get("shot_index", -1)) == 0)
		assert(str(order[index].get("order_reason", "")) == "TEE_ORDER")

	# After all four tee shots, member 0 is farthest from the pin and therefore
	# plays next even though member 0 was last in the honors order.
	assert(int(order[4].get("member_index", -1)) == 0)
	assert(int(order[4].get("shot_index", -1)) == 1)
	assert(str(order[4].get("order_reason", "")) == "AWAY")

	print("POC25_HONORS_SUMMARY opening=%s honors=%s next_away=%d" % [str(opening_a), str(honors), int(order[4].get("member_index", -1))])
	print("POC-25 TEE HONORS AND AWAY-ORDER HANDOFF PASSED")
	quit(0)
