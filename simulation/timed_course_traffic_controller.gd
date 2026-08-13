extends RefCounted

# POC-24D: Timed Course Traffic Controller
# -----------------------------------------
# Resolves authoritative golf play up front, but keeps physical course occupancy
# on the completed hole until the simulated event clock reaches that group's
# mechanically-derived finish time. This preserves the existing simulation-first
# architecture while giving traffic an explicit time dimension.

const LivingCourseController = preload("res://simulation/living_course_controller.gd")
const CourseTrafficState = preload("res://simulation/course_traffic_state.gd")
const GroupPaceModel = preload("res://simulation/group_pace_model.gd")

var course = null
var living_course = null
var traffic = null
var pace_model = null
var current_time_seconds: float = 0.0
var active_hole_events: Dictionary = {}

func configure(course_definition) -> bool:
	if course_definition == null or course_definition.hole_count() <= 0:
		return false
	course = course_definition
	living_course = LivingCourseController.new()
	if not living_course.configure(course_definition):
		return false
	traffic = CourseTrafficState.new()
	if not traffic.configure(course_definition):
		return false
	pace_model = GroupPaceModel.new()
	current_time_seconds = 0.0
	active_hole_events.clear()
	return true

func add_group(group_id: String, golfers: Array, tee_id: String = "default") -> bool:
	return living_course != null and living_course.add_group(group_id, golfers, tee_id)

func release_next_group() -> Dictionary:
	if living_course == null or traffic == null:
		return {}
	var group_id: String = living_course.start_sequencer.next_waiting_group_id()
	if group_id.is_empty():
		return {}
	var occupant: String = traffic.occupant_for_hole(1)
	if not occupant.is_empty():
		return {
			"released": false,
			"group_id": group_id,
			"blocked_hole_number": 1,
			"occupant_group_id": occupant,
			"time_seconds": current_time_seconds
		}
	var release_result: Dictionary = living_course.release_next_group()
	if release_result.is_empty():
		return {}
	var entry: Dictionary = traffic.request_hole_entry(group_id, 1)
	if not bool(entry.get("allowed", false)):
		return {}
	var result: Dictionary = release_result.duplicate(true)
	result["released"] = true
	result["traffic_entry"] = entry
	result["time_seconds"] = current_time_seconds
	return result

func start_group_current_hole(group_id: String, seed_value: int = 1) -> Dictionary:
	if living_course == null or traffic == null or pace_model == null:
		return {}
	if active_hole_events.has(group_id):
		return {
			"started": false,
			"group_id": group_id,
			"reason": "ACTIVE_HOLE_EVENT",
			"time_seconds": current_time_seconds
		}
	var group = living_course.population.group_by_id(group_id)
	if group == null:
		return {}
	var hole_number: int = group.current_hole_number()
	if hole_number <= 0:
		return {}
	if traffic.occupant_for_hole(hole_number) != group_id:
		return {
			"started": false,
			"group_id": group_id,
			"hole_number": hole_number,
			"reason": "NO_TRAFFIC_AUTHORITY",
			"time_seconds": current_time_seconds
		}

	var play_result: Dictionary = living_course.play_group_current_hole(group_id, seed_value)
	if play_result.is_empty() or not bool(play_result.get("completed", false)):
		return play_result
	var hole = course.hole_by_number(hole_number)
	var duration: Dictionary = pace_model.estimate_hole_duration(play_result, hole, str(group.tee_id))
	if duration.is_empty():
		return {}
	var finish_time: float = current_time_seconds + float(duration.get("total_seconds", 0.0))
	var event := {
		"group_id": group_id,
		"hole_number": hole_number,
		"next_hole_number": int(play_result.get("next_hole_number", 0)),
		"start_time_seconds": current_time_seconds,
		"finish_time_seconds": finish_time,
		"duration": duration.duplicate(true),
		"play_result": play_result.duplicate(true)
	}
	active_hole_events[group_id] = event
	return {
		"started": true,
		"group_id": group_id,
		"hole_number": hole_number,
		"start_time_seconds": current_time_seconds,
		"finish_time_seconds": finish_time,
		"duration": duration.duplicate(true),
		"play_result": play_result.duplicate(true)
	}

func advance_time(delta_seconds: float) -> Array:
	if delta_seconds < 0.0:
		return []
	var target_time: float = current_time_seconds + delta_seconds
	var due: Array = []
	for group_id in active_hole_events.keys():
		var event: Dictionary = active_hole_events[group_id]
		if float(event.get("finish_time_seconds", INF)) <= target_time:
			due.append(event.duplicate(true))
	due.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_time: float = float(a.get("finish_time_seconds", 0.0))
		var b_time: float = float(b.get("finish_time_seconds", 0.0))
		if is_equal_approx(a_time, b_time):
			return str(a.get("group_id", "")) < str(b.get("group_id", ""))
		return a_time < b_time
	)

	var completed: Array = []
	for event in due:
		current_time_seconds = float(event.get("finish_time_seconds", current_time_seconds))
		completed.append(_complete_event(str(event.get("group_id", ""))))
	current_time_seconds = target_time
	return completed

func active_event(group_id: String) -> Dictionary:
	return active_hole_events.get(group_id, {}).duplicate(true)

func snapshot() -> Dictionary:
	return {
		"time_seconds": current_time_seconds,
		"active_hole_events": active_hole_events.duplicate(true),
		"traffic": traffic.snapshot() if traffic != null else {},
		"living_course": living_course.snapshot() if living_course != null else {}
	}

func _complete_event(group_id: String) -> Dictionary:
	if not active_hole_events.has(group_id):
		return {}
	var event: Dictionary = active_hole_events[group_id]
	var hole_number: int = int(event.get("hole_number", 0))
	var next_hole: int = int(event.get("next_hole_number", 0))
	traffic.release_hole(group_id, hole_number)
	var admitted_behind: Dictionary = traffic.admit_next_waiting(hole_number)
	var next_entry: Dictionary = {}
	if next_hole > 0:
		next_entry = traffic.request_hole_entry(group_id, next_hole)
	active_hole_events.erase(group_id)
	return {
		"group_id": group_id,
		"hole_number": hole_number,
		"completed_at_seconds": current_time_seconds,
		"next_hole_number": next_hole,
		"next_traffic_entry": next_entry,
		"admitted_behind": admitted_behind,
		"duration": event.get("duration", {}).duplicate(true)
	}
