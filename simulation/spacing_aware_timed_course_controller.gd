extends RefCounted

# POC-24G/H: Spacing-Aware Timed Course Controller
# -------------------------------------------------
# Integrates resolved golf play, mechanically-derived hole duration, golfer-
# dependent tee clearance, concurrent same-hole occupancy, and inter-hole
# catch-up waiting. A following group advances only when it has both arrived at
# the next tee and the group ahead has reached a safe clearance milestone.

const LivingCourseController = preload("res://simulation/living_course_controller.gd")
const ConcurrentHoleTrafficState = preload("res://simulation/concurrent_hole_traffic_state.gd")
const GroupPaceModel = preload("res://simulation/group_pace_model.gd")
const SameHoleSpacingModel = preload("res://simulation/same_hole_spacing_model.gd")
const SameHoleReleaseScheduler = preload("res://simulation/same_hole_release_scheduler.gd")
const InterHoleTransitionScheduler = preload("res://simulation/inter_hole_transition_scheduler.gd")

var course = null
var living_course = null
var traffic = null
var pace_model = null
var spacing_model = null
var release_scheduler = null
var transition_scheduler = null
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
	spacing_model = SameHoleSpacingModel.new()
	release_scheduler = SameHoleReleaseScheduler.new()
	transition_scheduler = InterHoleTransitionScheduler.new()
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
	if living_course == null or traffic == null or pace_model == null or release_scheduler == null or transition_scheduler == null:
		return {}
	if active_hole_events.has(group_id):
		return {
			"started": false,
			"group_id": group_id,
			"reason": "ACTIVE_HOLE_EVENT",
			"time_seconds": current_time_seconds
		}
	if blocked_transitions.has(group_id):
		var blocked: Dictionary = _blocked_as_dictionary(group_id)
		return {
			"started": false,
			"group_id": group_id,
			"reason": "BLOCKED_INTER_HOLE_TRANSITION",
			"blocked_hole_number": int(blocked.get("to_hole_number", 0)),
			"lead_group_id": str(blocked.get("lead_group_id", "")),
			"transition_time_seconds": float(blocked.get("transition_time_seconds", -1.0)),
			"wait_seconds": float(blocked.get("wait_seconds", 0.0)),
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

	_schedule_waiters_behind_started_lead(group_id, hole_number, event)

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
	if delta_seconds < 0.0 or release_scheduler == null or transition_scheduler == null:
		return []
	var target_time: float = current_time_seconds + delta_seconds
	var processed: Array = []

	while true:
		var due_event: Dictionary = _next_due_event(target_time)
		if due_event.is_empty():
			break
		current_time_seconds = float(due_event.get("time", current_time_seconds))
		var event_type: String = str(due_event.get("type", ""))
		if event_type == "TEE_RELEASE":
			var release_event: Dictionary = due_event.get("event", {})
			var follower_id: String = str(release_event.get("following_group_id", ""))
			if not release_scheduler.pending_release(follower_id).is_empty():
				release_scheduler.cancel_release(follower_id)
				processed.append(_process_safe_tee_release(release_event))
		elif event_type == "INTER_HOLE_TRANSITION":
			var transition_event: Dictionary = due_event.get("event", {})
			var transition_follower: String = str(transition_event.get("following_group_id", ""))
			if not transition_scheduler.pending_transition(transition_follower).is_empty():
				transition_scheduler.cancel_transition(transition_follower)
				processed.append(_process_inter_hole_transition(transition_event))
		elif event_type == "HOLE_FINISH":
			var finish_group_id: String = str(due_event.get("group_id", ""))
			if active_hole_events.has(finish_group_id):
				processed.append(_complete_hole_event(finish_group_id))

	current_time_seconds = target_time
	return processed

func active_event(group_id: String) -> Dictionary:
	return active_hole_events.get(group_id, {}).duplicate(true)

func blocked_transition(group_id: String) -> Dictionary:
	return _blocked_as_dictionary(group_id).duplicate(true)

func snapshot() -> Dictionary:
	return {
		"time_seconds": current_time_seconds,
		"active_hole_events": active_hole_events.duplicate(true),
		"blocked_transitions": blocked_transitions.duplicate(true),
		"traffic": traffic.snapshot() if traffic != null else {},
		"tee_releases": release_scheduler.snapshot() if release_scheduler != null else {},
		"inter_hole_transitions": transition_scheduler.snapshot() if transition_scheduler != null else {},
		"living_course": living_course.snapshot() if living_course != null else {}
	}

func _next_due_event(target_time: float) -> Dictionary:
	var due: Array = []
	var release_snapshot: Dictionary = release_scheduler.snapshot()
	for release_value in release_snapshot.get("pending_releases", []):
		if typeof(release_value) != TYPE_DICTIONARY:
			continue
		var release_event: Dictionary = release_value
		var release_time: float = float(release_event.get("release_time_seconds", INF))
		if release_time <= target_time:
			due.append({
				"type": "TEE_RELEASE",
				"time": release_time,
				"sort_key": str(release_event.get("following_group_id", "")),
				"event": release_event.duplicate(true)
			})

	var transition_snapshot: Dictionary = transition_scheduler.snapshot()
	for transition_value in transition_snapshot.get("pending_transitions", []):
		if typeof(transition_value) != TYPE_DICTIONARY:
			continue
		var transition_event: Dictionary = transition_value
		var transition_time: float = float(transition_event.get("transition_time_seconds", INF))
		if transition_time <= target_time:
			due.append({
				"type": "INTER_HOLE_TRANSITION",
				"time": transition_time,
				"sort_key": str(transition_event.get("following_group_id", "")),
				"event": transition_event.duplicate(true)
			})

	for group_id in active_hole_events.keys():
		var hole_event: Dictionary = active_hole_events[group_id]
		var finish_time: float = float(hole_event.get("finish_time_seconds", INF))
		if finish_time <= target_time:
			due.append({
				"type": "HOLE_FINISH",
				"time": finish_time,
				"sort_key": str(group_id),
				"group_id": str(group_id)
			})

	if due.is_empty():
		return {}
	due.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_time: float = float(a.get("time", 0.0))
		var b_time: float = float(b.get("time", 0.0))
		if not is_equal_approx(a_time, b_time):
			return a_time < b_time
		var a_priority: int = _event_priority(str(a.get("type", "")))
		var b_priority: int = _event_priority(str(b.get("type", "")))
		if a_priority != b_priority:
			return a_priority < b_priority
		return str(a.get("sort_key", "")) < str(b.get("sort_key", ""))
	)
	return due[0].duplicate(true)

func _event_priority(event_type: String) -> int:
	if event_type == "HOLE_FINISH":
		return 0
	if event_type == "INTER_HOLE_TRANSITION":
		return 1
	return 2

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

func _process_inter_hole_transition(transition_event: Dictionary) -> Dictionary:
	var follower_id: String = str(transition_event.get("following_group_id", ""))
	var to_hole: int = int(transition_event.get("to_hole_number", 0))
	if follower_id.is_empty() or to_hole <= 0:
		return {"type": "INTER_HOLE_TRANSITION", "entered": false, "group_id": follower_id, "reason": "INVALID_TRANSITION"}
	if traffic.group_hole(follower_id) != 0:
		return {"type": "INTER_HOLE_TRANSITION", "entered": false, "group_id": follower_id, "reason": "GROUP_ALREADY_ON_HOLE"}
	if not traffic.enter_hole(follower_id, to_hole):
		return {"type": "INTER_HOLE_TRANSITION", "entered": false, "group_id": follower_id, "reason": "TRAFFIC_ENTRY_FAILED"}
	blocked_transitions.erase(follower_id)
	return {
		"type": "INTER_HOLE_TRANSITION",
		"entered": true,
		"group_id": follower_id,
		"lead_group_id": str(transition_event.get("lead_group_id", "")),
		"from_hole_number": int(transition_event.get("from_hole_number", 0)),
		"to_hole_number": to_hole,
		"time_seconds": current_time_seconds,
		"wait_seconds": float(transition_event.get("wait_seconds", 0.0)),
		"waited_for_group_ahead": bool(transition_event.get("waited_for_group_ahead", false))
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
	var transition_event: Dictionary = {}
	if next_hole > 0:
		var occupants: Array = traffic.groups_on_hole(next_hole)
		if occupants.is_empty():
			traffic.enter_hole(group_id, next_hole)
			transition_status = "ENTERED_NEXT_HOLE"
		else:
			var lead_group_id: String = str(occupants[occupants.size() - 1])
			transition_event = _schedule_inter_hole_transition(group_id, lead_group_id, hole_number, next_hole, current_time_seconds)
			if transition_event.is_empty():
				blocked_transitions[group_id] = {
					"following_group_id": group_id,
					"lead_group_id": lead_group_id,
					"from_hole_number": hole_number,
					"to_hole_number": next_hole,
					"follower_arrival_time_seconds": current_time_seconds,
					"transition_time_seconds": -1.0,
					"wait_seconds": 0.0,
					"status": "WAITING_FOR_LEAD_PLAY_START"
				}
				transition_status = "WAITING_FOR_LEAD_PLAY_START"
			else:
				blocked_transitions[group_id] = transition_event.duplicate(true)
				transition_status = str(transition_event.get("status", "WAITING_FOR_GROUP_AHEAD"))
				if float(transition_event.get("transition_time_seconds", INF)) <= current_time_seconds:
					transition_scheduler.cancel_transition(group_id)
					var immediate: Dictionary = _process_inter_hole_transition(transition_event)
					transition_status = "ENTERED_NEXT_HOLE" if bool(immediate.get("entered", false)) else transition_status

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
		"transition_status": transition_status,
		"transition_event": transition_event.duplicate(true)
	}

func _schedule_inter_hole_transition(follower_id: String, lead_id: String, from_hole: int, to_hole: int, arrival_time: float) -> Dictionary:
	if spacing_model == null or transition_scheduler == null:
		return {}
	var lead_event: Dictionary = active_hole_events.get(lead_id, {})
	if lead_event.is_empty() or int(lead_event.get("hole_number", 0)) != to_hole:
		return {}
	var follower_group = living_course.population.group_by_id(follower_id)
	if follower_group == null:
		return {}
	var hole = course.hole_by_number(to_hole)
	if hole == null:
		return {}

	var spacing: Dictionary = spacing_model.earliest_safe_tee_time(
		lead_event.get("play_result", {}),
		hole,
		follower_group.golfers,
		str(follower_group.tee_id)
	)
	var lead_finish: float = float(lead_event.get("finish_time_seconds", arrival_time))
	var lead_safe_time: float = lead_finish
	if bool(spacing.get("safe", false)):
		lead_safe_time = min(
			lead_finish,
			float(lead_event.get("start_time_seconds", 0.0)) + float(spacing.get("safe_time_seconds", 0.0))
		)
	return transition_scheduler.schedule_transition(
		follower_id,
		lead_id,
		from_hole,
		to_hole,
		arrival_time,
		lead_safe_time
	)

func _schedule_waiters_behind_started_lead(lead_id: String, hole_number: int, _lead_event: Dictionary) -> void:
	var waiting_ids: Array = blocked_transitions.keys().duplicate()
	for follower_value in waiting_ids:
		var follower_id: String = str(follower_value)
		var blocked: Dictionary = _blocked_as_dictionary(follower_id)
		if str(blocked.get("lead_group_id", "")) != lead_id:
			continue
		if int(blocked.get("to_hole_number", 0)) != hole_number:
			continue
		if str(blocked.get("status", "")) != "WAITING_FOR_LEAD_PLAY_START":
			continue
		var scheduled: Dictionary = _schedule_inter_hole_transition(
			follower_id,
			lead_id,
			int(blocked.get("from_hole_number", hole_number - 1)),
			hole_number,
			float(blocked.get("follower_arrival_time_seconds", current_time_seconds))
		)
		if not scheduled.is_empty():
			blocked_transitions[follower_id] = scheduled.duplicate(true)

func _blocked_as_dictionary(group_id: String) -> Dictionary:
	if not blocked_transitions.has(group_id):
		return {}
	var value = blocked_transitions[group_id]
	if typeof(value) == TYPE_DICTIONARY:
		return value.duplicate(true)
	return {"to_hole_number": int(value)}
