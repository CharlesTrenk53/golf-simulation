extends RefCounted

# POC-24G: Spacing-Aware Timed Course Controller
# -----------------------------------------------
# Integrates resolved golf play, mechanically-derived hole duration, golfer-
# dependent tee-clearance scheduling, and concurrent same-hole occupancy.
#
# This slice proves safe same-hole tee admission. Inter-hole catch-up spacing is
# deliberately not guessed: if a group finishes into an occupied next hole, the
# transition is recorded as blocked for a later POC-24 slice.

const LivingCourseController = preload("res://simulation/living_course_controller.gd")
const ConcurrentHoleTrafficState = preload("res://simulation/concurrent_hole_traffic_state.gd")
const GroupPaceModel = preload("res://simulation/group_pace_model.gd")
const SameHoleReleaseScheduler = preload("res://simulation/same_hole_release_scheduler.gd")

var course = null
var living_course = null
var traffic = null
var pace_model = null
var release_scheduler = null
var current_time_seconds: float = 0.0
var active_hole_events: Dictionary = {}
var blocked_transitions: Dictionary = {}

func configure(course_definition) -> bool:
	if course_definition == null or course_definition.hole_count() <= 0:
		return false
	course = course_definition
	living_course = LivingCourseController.new()
	if not living_course.configure(course_definition):
		return false
	traffic = ConcurrentHoleTrafficState.new()
	if not traffic.configure(course_definition):
		return false
	pace_model = GroupPaceModel.new()
	release_scheduler = SameHoleReleaseScheduler.new()
	current_time_seconds = 0.0
	active_hole_events.clear()
	blocked_transitions.clear()
	return true

func add_group(group_id: String, golfers: Array, tee_id: String = "default") -> bool:
	return living_course != null and living_course.add_group(group_id, golfers, tee_id)

func release_next_group() -> Dictionary:
	if living_course == null or traffic == null or release_scheduler == null:
		return {}
	var group_id: String = living_course.start_sequencer.next_waiting_group_id()
	if group_id.is_empty():
		return {}
	if traffic.groups_on_hole(1).is_empty():
		return _release_waiting_to_first_hole(group_id, "OPEN_FIRST_HOLE")
	var pending: Dictionary = release_scheduler.pending_release(group_id)
	return {
		"released": false,
		"group_id": group_id,
		"hole_number": 1,
		"reason": "WAITING_FOR_SAFE_TEE_RELEASE" if not pending.is_empty() else "WAITING_FOR_SPACING_AUTHORITY",
		"release_time_seconds": float(pending.get("release_time_seconds", -1.0)),
		"time_seconds": current_time_seconds
	}

func start_group_current_hole(group_id: String, seed_value: int = 1) -> Dictionary:
	if living_course == null or traffic == null or pace_model == null or release_scheduler == null:
		return {}
	if active_hole_events.has(group_id):
		return {
			"started": false,
			"group_id": group_id,
			"reason": "ACTIVE_HOLE_EVENT",
			"time_seconds": current_time_seconds
		}
	if blocked_transitions.has(group_id):
		return {
			"started": false,
			"group_id": group_id,
			"reason": "BLOCKED_INTER_HOLE_TRANSITION",
			"blocked_hole_number": int(blocked_transitions[group_id]),
			"time_seconds": current_time_seconds
		}

	var group = living_course.population.group_by_id(group_id)
	if group == null:
		return {}
	var hole_number: int = group.current_hole_number()
	if hole_number <= 0:
		return {}
	if traffic.group_hole(group_id) != hole_number:
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

	var tee_release: Dictionary = {}
	if hole_number == 1:
		var following_id: String = living_course.start_sequencer.next_waiting_group_id()
		if not following_id.is_empty():
			var following_group = living_course.population.group_by_id(following_id)
			if following_group != null:
				tee_release = release_scheduler.schedule_release(
					group_id,
					following_id,
					play_result,
					hole,
					following_group.golfers,
					current_time_seconds,
					str(group.tee_id)
				)

	return {
		"started": true,
		"group_id": group_id,
		"hole_number": hole_number,
		"start_time_seconds": current_time_seconds,
		"finish_time_seconds": finish_time,
		"duration": duration.duplicate(true),
		"tee_release": tee_release.duplicate(true),
		"play_result": play_result.duplicate(true)
	}

func advance_time(delta_seconds: float) -> Array:
	if delta_seconds < 0.0 or release_scheduler == null:
		return []
	var target_time: float = current_time_seconds + delta_seconds
	var due: Array = []

	var pending_snapshot: Dictionary = release_scheduler.snapshot()
	for release_value in pending_snapshot.get("pending_releases", []):
		if typeof(release_value) != TYPE_DICTIONARY:
			continue
		var release_event: Dictionary = release_value
		var release_time: float = float(release_event.get("release_time_seconds", INF))
		if release_time <= target_time:
			due.append({"type": "TEE_RELEASE", "time": release_time, "event": release_event.duplicate(true)})

	for group_id in active_hole_events.keys():
		var hole_event: Dictionary = active_hole_events[group_id]
		var finish_time: float = float(hole_event.get("finish_time_seconds", INF))
		if finish_time <= target_time:
			due.append({"type": "HOLE_FINISH", "time": finish_time, "group_id": str(group_id)})

	due.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_time: float = float(a.get("time", 0.0))
		var b_time: float = float(b.get("time", 0.0))
		if is_equal_approx(a_time, b_time):
			return str(a.get("type", "")) < str(b.get("type", ""))
		return a_time < b_time
	)

	var processed: Array = []
	for due_value in due:
		var due_event: Dictionary = due_value
		current_time_seconds = float(due_event.get("time", current_time_seconds))
		if str(due_event.get("type", "")) == "TEE_RELEASE":
			var release_event: Dictionary = due_event.get("event", {})
			var follower_id: String = str(release_event.get("following_group_id", ""))
			if not release_scheduler.pending_release(follower_id).is_empty():
				release_scheduler.cancel_release(follower_id)
				processed.append(_process_safe_tee_release(release_event))
		else:
			var finish_group_id: String = str(due_event.get("group_id", ""))
			if active_hole_events.has(finish_group_id):
				processed.append(_complete_hole_event(finish_group_id))

	current_time_seconds = target_time
	return processed

func active_event(group_id: String) -> Dictionary:
	return active_hole_events.get(group_id, {}).duplicate(true)

func snapshot() -> Dictionary:
	return {
		"time_seconds": current_time_seconds,
		"active_hole_events": active_hole_events.duplicate(true),
		"blocked_transitions": blocked_transitions.duplicate(true),
		"traffic": traffic.snapshot() if traffic != null else {},
		"tee_releases": release_scheduler.snapshot() if release_scheduler != null else {},
		"living_course": living_course.snapshot() if living_course != null else {}
	}

func _release_waiting_to_first_hole(expected_group_id: String, reason: String) -> Dictionary:
	var next_id: String = living_course.start_sequencer.next_waiting_group_id()
	if next_id.is_empty() or next_id != expected_group_id:
		return {}
	var release_result: Dictionary = living_course.release_next_group()
	if release_result.is_empty():
		return {}
	var group_id: String = str(release_result.get("group_id", ""))
	if not traffic.enter_hole(group_id, 1):
		return {}
	var result: Dictionary = release_result.duplicate(true)
	result["released"] = true
	result["hole_number"] = 1
	result["reason"] = reason
	result["time_seconds"] = current_time_seconds
	return result

func _process_safe_tee_release(release_event: Dictionary) -> Dictionary:
	var follower_id: String = str(release_event.get("following_group_id", ""))
	var hole_number: int = int(release_event.get("hole_number", 0))
	if hole_number != 1:
		return {"type": "TEE_RELEASE", "released": false, "group_id": follower_id, "reason": "UNSUPPORTED_HOLE"}
	var release_result: Dictionary = _release_waiting_to_first_hole(follower_id, "SAFE_SAME_HOLE_SPACING")
	if release_result.is_empty():
		return {"type": "TEE_RELEASE", "released": false, "group_id": follower_id, "reason": "START_SEQUENCE_CHANGED"}
	return {
		"type": "TEE_RELEASE",
		"released": true,
		"group_id": follower_id,
		"lead_group_id": str(release_event.get("lead_group_id", "")),
		"hole_number": 1,
		"time_seconds": current_time_seconds,
		"shot_wave": int(release_event.get("shot_wave", 0)),
		"credible_reach_yards": float(release_event.get("credible_reach_yards", 0.0)),
		"safe_clearance_yards": float(release_event.get("safe_clearance_yards", 0.0))
	}

func _complete_hole_event(group_id: String) -> Dictionary:
	if not active_hole_events.has(group_id):
		return {}
	var event: Dictionary = active_hole_events[group_id]
	var hole_number: int = int(event.get("hole_number", 0))
	var next_hole: int = int(event.get("next_hole_number", 0))
	traffic.leave_hole(group_id, hole_number)
	active_hole_events.erase(group_id)

	var transition_status: String = "ROUND_COMPLETE"
	if next_hole > 0:
		if traffic.groups_on_hole(next_hole).is_empty():
			traffic.enter_hole(group_id, next_hole)
			transition_status = "ENTERED_NEXT_HOLE"
		else:
			blocked_transitions[group_id] = next_hole
			transition_status = "WAITING_FOR_NEXT_HOLE_SPACING"

	if hole_number == 1 and traffic.groups_on_hole(1).is_empty():
		var next_waiting: String = living_course.start_sequencer.next_waiting_group_id()
		if not next_waiting.is_empty():
			release_scheduler.cancel_release(next_waiting)
			_release_waiting_to_first_hole(next_waiting, "HOLE_CLEARED_BEFORE_SCHEDULED_RELEASE")

	return {
		"type": "HOLE_FINISH",
		"group_id": group_id,
		"hole_number": hole_number,
		"completed_at_seconds": current_time_seconds,
		"next_hole_number": next_hole,
		"transition_status": transition_status
	}
