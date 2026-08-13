extends RefCounted

# POC-24B: Traffic-Aware Living Course Controller
# -----------------------------------------------
# Wraps the GREEN POC-23 living-course controller with authoritative hole
# occupancy. Golfer decisions and scoring remain inside the existing round
# simulation; this layer only decides whether a group may enter/play a hole.

const LivingCourseController = preload("res://simulation/living_course_controller.gd")
const CourseTrafficState = preload("res://simulation/course_traffic_state.gd")

var course = null
var living_course = null
var traffic = null

func configure(course_definition) -> bool:
	if course_definition == null or course_definition.hole_count() <= 0:
		return false
	course = course_definition
	living_course = LivingCourseController.new()
	if not living_course.configure(course_definition):
		return false
	traffic = CourseTrafficState.new()
	return traffic.configure(course_definition)

func add_group(group_id: String, golfers: Array, tee_id: String = "default") -> bool:
	if living_course == null:
		return false
	return living_course.add_group(group_id, golfers, tee_id)

func release_next_group() -> Dictionary:
	if living_course == null or traffic == null:
		return {}
	var next_group_id: String = living_course.start_sequencer.next_waiting_group_id()
	if next_group_id.is_empty():
		return {}
	if not traffic.occupant_for_hole(1).is_empty():
		return {
			"released": false,
			"group_id": next_group_id,
			"blocked_hole_number": 1,
			"occupant_group_id": traffic.occupant_for_hole(1)
		}

	var release_result: Dictionary = living_course.release_next_group()
	if release_result.is_empty():
		return {}
	var group_id: String = str(release_result.get("group_id", ""))
	var entry_result: Dictionary = traffic.request_hole_entry(group_id, 1)
	if not bool(entry_result.get("allowed", false)):
		return {}
	var result: Dictionary = release_result.duplicate(true)
	result["released"] = true
	result["traffic_entry"] = entry_result
	return result

func play_group_current_hole(group_id: String, seed_value: int = 1) -> Dictionary:
	if living_course == null or traffic == null:
		return {}
	var group = living_course.population.group_by_id(group_id)
	if group == null:
		return {}
	var hole_number: int = group.current_hole_number()
	if hole_number <= 0:
		return {}
	if traffic.occupant_for_hole(hole_number) != group_id:
		return {
			"played": false,
			"group_id": group_id,
			"hole_number": hole_number,
			"traffic_status": "WAITING" if traffic.waiting_hole_by_group.has(group_id) else "BLOCKED"
		}

	var play_result: Dictionary = living_course.play_group_current_hole(group_id, seed_value)
	if play_result.is_empty() or not bool(play_result.get("completed", false)):
		return play_result

	traffic.release_hole(group_id, hole_number)
	var admitted_behind: Dictionary = traffic.admit_next_waiting(hole_number)
	var next_hole: int = int(play_result.get("next_hole_number", 0))
	var next_entry: Dictionary = {}
	if next_hole > 0:
		next_entry = traffic.request_hole_entry(group_id, next_hole)

	var result: Dictionary = play_result.duplicate(true)
	result["played"] = true
	result["released_hole_number"] = hole_number
	result["next_traffic_entry"] = next_entry
	result["admitted_behind"] = admitted_behind
	return result

func group_snapshot(group_id: String) -> Dictionary:
	if living_course == null or traffic == null:
		return {}
	var result: Dictionary = living_course.group_snapshot(group_id)
	if result.is_empty():
		return result
	result["traffic_hole_number"] = traffic.group_hole(group_id)
	result["traffic_waiting_hole_number"] = int(traffic.waiting_hole_by_group.get(group_id, 0))
	return result

func snapshot() -> Dictionary:
	return {
		"living_course": living_course.snapshot() if living_course != null else {},
		"traffic": traffic.snapshot() if traffic != null else {}
	}
