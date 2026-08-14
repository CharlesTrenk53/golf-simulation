extends SceneTree

const CourseDefinition = preload("res://simulation/course_definition.gd")
const SameHoleSpacingModel = preload("res://simulation/same_hole_spacing_model.gd")
const Golfer = preload("res://scenes/golfer.gd")


func _init() -> void:
	var course = CourseDefinition.load_json("res://data/courses/poc12_proving_course.json")
	assert(course != null)
	var hole = course.hole_by_number(3)
	assert(hole != null)
	assert(int(hole.par) == 5)
	assert(int(hole.nominal_yardage) == 510)

	var follower = Golfer.new()
	follower.profile = Golfer.GolferProfile.CAREFUL_CARL
	follower.apply_profile()
	get_root().add_child(follower)

	var tee: Vector3 = hole.tee_position("default")
	var lead_result := {
		"group_id": "lead_group",
		"hole_number": 3,
		"tee_order": [0, 1],
		"member_results": [
			{
				"member_index": 0,
				"golfer_name": "Lead A",
				"history": [
					_shot(1, tee, Vector3(0, 0, 300), "FAIRWAY"),
					_shot(2, Vector3(0, 0, 300), Vector3(-5, 0, 20), "GREEN")
				]
			},
			{
				"member_index": 1,
				"golfer_name": "Lead B",
				"history": [
					_shot(1, tee, Vector3(0, 0, 330), "FAIRWAY"),
					_shot(2, Vector3(0, 0, 330), Vector3(0, 0, 180), "FAIRWAY"),
					_shot(3, Vector3(0, 0, 180), Vector3(-4, 0, 18), "GREEN")
				]
			}
		]
	}

	var model = SameHoleSpacingModel.new()
	var spacing: Dictionary = model.earliest_safe_tee_time(lead_result, hole, [follower], "default")
	assert(bool(spacing.get("safe", false)))
	assert(str(spacing.get("release_rule", "")) == "RANGE_SAFE_AND_ALL_LEAD_GOLFERS_ON_GREEN")

	var range_time: float = float(spacing.get("range_safe_time_seconds", -1.0))
	var green_time: float = float(spacing.get("lead_group_green_time_seconds", -1.0))
	var effective_time: float = float(spacing.get("safe_time_seconds", -1.0))
	assert(range_time >= 0.0)
	assert(green_time > range_time)
	assert(is_equal_approx(effective_time, green_time))

	var green_gate: Dictionary = model.earliest_all_members_green_time(lead_result, hole, "default")
	assert(bool(green_gate.get("reached", false)))
	assert(is_equal_approx(float(green_gate.get("green_time_seconds", -1.0)), green_time))

	print("POC25_PAR5_GREEN_GATE_SUMMARY yardage=%d range=%.1f green=%.1f effective=%.1f" % [
		int(hole.nominal_yardage),
		range_time,
		green_time,
		effective_time
	])
	print("POC-25 PAR-5 GREEN-GATED TEE TIME PASSED")

	follower.queue_free()
	quit(0)


func _shot(number: int, start_position: Vector3, landing_position: Vector3, surface_after: String) -> Dictionary:
	return {
		"shot_number": number,
		"start_position": start_position,
		"landing_position": landing_position,
		"relief_position": landing_position,
		"surface_after": surface_after,
		"outcome": "SUCCESS",
		"penalty_strokes": 0,
		"club_id": "TEST_CLUB"
	}
