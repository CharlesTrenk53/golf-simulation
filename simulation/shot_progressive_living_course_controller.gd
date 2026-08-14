extends RefCounted

# POC-26D: Shot-Progressive Living Course Controller
# -------------------------------------------------
# Runs every active group through the same live GroupHoleSession authority instead
# of resolving a complete hole before the course clock starts. AI-only groups and
# mixed human/AI groups therefore share one world clock, one traffic state, one
# tee/away-order authority, and one spacing rule.
#
# A human turn is simply a group event with no automatic execution. The course
# clock may continue and other groups may keep playing while that decision remains
# pending. Tee releases and inter-hole catch-up are evaluated from current
# authoritative ball states after real shots; no future hole is pre-simulated.

const LivingCourseController = preload("res://simulation/living_course_controller.gd")
const ConcurrentHoleTrafficState = preload("res://simulation/concurrent_hole_traffic_state.gd")
const GroupPaceModel = preload("res://simulation/group_pace_model.gd")
const SameHoleSpacingModel = preload("res://simulation/same_hole_spacing_model.gd")

const CONTROL_AI := "AI"
const CONTROL_HUMAN := "HUMAN"
const TIME_EPSILON := 0.001
const CLEARANCE_EPSILON := 0.001

var course = null
var living_course = null
var traffic = null
var pace_model = null
var spacing_model = null
var current_time_seconds: float = 0.0

# Configuration persists for the full round. Each group uses the same human
# designation on every hole; -1 means fully autonomous.
var group_controls: Dictionary = {}

# RefCounted GroupHoleSession values are intentionally kept separate from the
# serializable metadata used by diagnostics/snapshots.
var live_sessions: Dictionary = {}
var live_metadata: Dictionary = {}
var blocked_transitions: Dictionary = {}
var event_history: Array = []


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
	current_time_seconds = 0.0
	group_controls.clear()
	live_sessions.clear()
	live_metadata.clear()
	blocked_transitions.clear()
	event_history.clear()
	return true


func add_group(
	group_id: String,
	golfers: Array,
	tee_id: String = "default",
	human_member_index: int = -1,
	seed_base: int = 1
) -> bool:
	if living_course == null:
		return false
	if human_member_index < -1 or human_member_index >= golfers.size():
		return false
	if not living_course.add_group(group_id, golfers, tee_id):
		return false
	group_controls[group_id] = {
		"human_member_index": human_member_index,
		"seed_base": seed_base
	}
	return true


func release_next_group() -> Dictionary:
	if living_course == null or traffic == null:
		return {}
	var group_id: String = living_course.start_sequencer.next_waiting_group_id()
	if group_id.is_empty():
		return {}

	var occupants: Array = traffic.groups_on_hole(1)
	if occupants.is_empty():
		return _release_and_start_first_hole(group_id, "OPEN_FIRST_HOLE", {})

	# The last occupant is the immediately preceding group on this hole. Safety
	# must be established relative to that group, not some arbitrary tee interval.
	var lead_group_id: String = str(occupants[occupants.size() - 1])
	var following_group = living_course.population.group_by_id(group_id)
	var safety: Dictionary = _live_spacing_status(lead_group_id, following_group)
	if bool(safety.get("safe", false)):
		return _release_and_start_first_hole(group_id, str(safety.get("status", "SAFE_LIVE_SPACING")), safety)
	return {
		"released": false,
		"group_id": group_id,
		"lead_group_id": lead_group_id,
		"hole_number": 1,
		"reason": str(safety.get("status", "WAITING_FOR_LIVE_SPACING")),
		"time_seconds": current_time_seconds,
		"spacing": safety.duplicate(true)
	}


func advance_time(delta_seconds: float) -> Array:
	if delta_seconds < 0.0:
		return []
	var target_time: float = current_time_seconds + delta_seconds
	var processed: Array = []

	while true:
		var due: Dictionary = _next_ai_turn_due(target_time)
		if due.is_empty():
			break
		current_time_seconds = float(due.get("time_seconds", current_time_seconds))
		var group_id: String = str(due.get("group_id", ""))
		if not live_sessions.has(group_id):
			continue
		var session = live_sessions[group_id]
		var step: Dictionary = session.play_current_turn()
		if step.is_empty() or bool(step.get("awaiting_human", false)):
			# A live AI event must never consume a human turn. The latter is skipped by
			# _next_ai_turn_due(), but this guard prevents accidental silent autoplay.
			continue
		if not bool(step.get("played", false)):
			processed.append(_record_event({
				"type": "LIVE_SHOT_FAILED",
				"group_id": group_id,
				"time_seconds": current_time_seconds,
				"failed": bool(step.get("failed", false))
			}))
			continue

		processed.append(_record_live_shot(group_id, step))
		processed.append_array(_after_completed_turn(group_id, step))

	current_time_seconds = target_time
	return processed


func pending_human_decision(group_id: String) -> Dictionary:
	if not live_sessions.has(group_id) or not live_metadata.has(group_id):
		return {}
	var session = live_sessions[group_id]
	if session == null or session.has_failed() or session.is_complete():
		return {}
	var turn: Dictionary = session.current_turn()
	if str(turn.get("control_source", CONTROL_AI)) != CONTROL_HUMAN:
		return {}
	var metadata: Dictionary = live_metadata[group_id]
	if current_time_seconds + TIME_EPSILON < float(metadata.get("next_action_time_seconds", INF)):
		return {}
	return session.pending_human_decision()


func submit_human_choice(group_id: String, candidate_index: int) -> Dictionary:
	if not live_sessions.has(group_id) or not live_metadata.has(group_id):
		return {"played": false, "rejected": true, "reason": "NO_LIVE_SESSION"}
	var session = live_sessions[group_id]
	var turn: Dictionary = session.current_turn()
	if str(turn.get("control_source", CONTROL_AI)) != CONTROL_HUMAN:
		return {"played": false, "rejected": true, "reason": "OUT_OF_TURN", "turn": turn.duplicate(true)}
	var metadata: Dictionary = live_metadata[group_id]
	if current_time_seconds + TIME_EPSILON < float(metadata.get("next_action_time_seconds", INF)):
		return {
			"played": false,
			"rejected": true,
			"reason": "TURN_NOT_READY",
			"ready_time_seconds": float(metadata.get("next_action_time_seconds", INF)),
			"time_seconds": current_time_seconds
		}

	var human_index: int = int(group_controls.get(group_id, {}).get("human_member_index", -1))
	var step: Dictionary = session.submit_human_choice(human_index, candidate_index)
	if not bool(step.get("played", false)):
		return step

	var shot_event: Dictionary = _record_live_shot(group_id, step)
	var world_events: Array = _after_completed_turn(group_id, step)
	return {
		"played": true,
		"rejected": false,
		"group_id": group_id,
		"time_seconds": current_time_seconds,
		"turn": step.get("turn", {}).duplicate(true),
		"shot": step.get("shot", {}).duplicate(true),
		"shot_event": shot_event.duplicate(true),
		"world_events": world_events.duplicate(true),
		"complete": bool(step.get("complete", false))
	}


func live_session_snapshot(group_id: String) -> Dictionary:
	if not live_sessions.has(group_id):
		return {}
	var session = live_sessions[group_id]
	var result: Dictionary = session.snapshot()
	var metadata: Dictionary = live_metadata.get(group_id, {})
	result["next_action_time_seconds"] = float(metadata.get("next_action_time_seconds", -1.0))
	result["time_seconds"] = current_time_seconds
	return result


func live_spacing_status(lead_group_id: String, following_group_id: String) -> Dictionary:
	if living_course == null:
		return {}
	var following_group = living_course.population.group_by_id(following_group_id)
	if following_group == null:
		return {}
	return _live_spacing_status(lead_group_id, following_group)


func group_live_shot_count(group_id: String) -> int:
	var count: int = 0
	for event_value in event_history:
		if typeof(event_value) != TYPE_DICTIONARY:
			continue
		var event: Dictionary = event_value
		if str(event.get("type", "")) == "LIVE_SHOT" and str(event.get("group_id", "")) == group_id:
			count += 1
	return count


func snapshot() -> Dictionary:
	var session_snapshots: Dictionary = {}
	for group_id in live_sessions.keys():
		session_snapshots[group_id] = live_session_snapshot(str(group_id))
	return {
		"time_seconds": current_time_seconds,
		"traffic": traffic.snapshot() if traffic != null else {},
		"live_sessions": session_snapshots,
		"live_metadata": live_metadata.duplicate(true),
		"blocked_transitions": blocked_transitions.duplicate(true),
		"event_history": event_history.duplicate(true),
		"living_course": living_course.snapshot() if living_course != null else {}
	}


func _next_ai_turn_due(target_time: float) -> Dictionary:
	var due: Array = []
	for group_value in live_sessions.keys():
		var group_id: String = str(group_value)
		var session = live_sessions[group_id]
		if session == null or session.has_failed() or session.is_complete():
			continue
		var turn: Dictionary = session.current_turn()
		if turn.is_empty() or str(turn.get("control_source", CONTROL_AI)) != CONTROL_AI:
			continue
		var metadata: Dictionary = live_metadata.get(group_id, {})
		var action_time: float = float(metadata.get("next_action_time_seconds", INF))
		if action_time <= target_time + TIME_EPSILON:
			due.append({
				"group_id": group_id,
				"time_seconds": action_time
			})
	if due.is_empty():
		return {}
	due.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_time: float = float(a.get("time_seconds", 0.0))
		var b_time: float = float(b.get("time_seconds", 0.0))
		if not is_equal_approx(a_time, b_time):
			return a_time < b_time
		return str(a.get("group_id", "")) < str(b.get("group_id", ""))
	)
	return due[0].duplicate(true)


func _record_live_shot(group_id: String, step: Dictionary) -> Dictionary:
	var shot: Dictionary = step.get("shot", {})
	var turn: Dictionary = step.get("turn", {})
	return _record_event({
		"type": "LIVE_SHOT",
		"group_id": group_id,
		"hole_number": int(turn.get("hole_number", 0)),
		"member_index": int(turn.get("member_index", -1)),
		"control_source": str(turn.get("control_source", shot.get("choice_source", CONTROL_AI))),
		"choice_source": str(shot.get("choice_source", turn.get("control_source", CONTROL_AI))),
		"shot_number": int(shot.get("shot_number", 0)),
		"decision_id": str(shot.get("decision_id", "")),
		"outcome": str(shot.get("outcome", "")),
		"penalty_strokes": max(0, int(shot.get("penalty_strokes", 0))),
		"time_seconds": current_time_seconds,
		"shot": shot.duplicate(true)
	})


func _after_completed_turn(group_id: String, step: Dictionary) -> Array:
	var events: Array = []
	if not live_sessions.has(group_id):
		return events
	var session = live_sessions[group_id]
	if bool(step.get("complete", false)) or session.is_complete():
		events.append_array(_complete_live_hole(group_id))
	else:
		_schedule_next_action(group_id, step)
		var release_event: Dictionary = _attempt_waiting_first_release()
		if not release_event.is_empty():
			events.append(release_event)
		events.append_array(_reevaluate_blocked_transitions())
	return events


func _schedule_next_action(group_id: String, step: Dictionary) -> void:
	if not live_sessions.has(group_id) or not live_metadata.has(group_id):
		return
	var session = live_sessions[group_id]
	var shot: Dictionary = step.get("shot", {})
	var delay: float = maxf(0.0, pace_model.shot_routine_seconds)
	delay += float(max(0, int(shot.get("penalty_strokes", 0)))) * maxf(0.0, pace_model.penalty_recovery_seconds)

	# After a shot the group must reach the next ball before that golfer can begin
	# their routine. This uses live ball positions rather than a precomputed hole
	# duration, preserving the POC-24 pace ingredients at shot granularity.
	var next_turn: Dictionary = session.current_turn()
	var next_member: int = int(next_turn.get("member_index", -1))
	var from_position = shot.get("start_position", null)
	if next_member >= 0 and session.group != null and next_member < session.group.rounds.size() and typeof(from_position) == TYPE_VECTOR3:
		var next_round = session.group.rounds[next_member]
		if next_round != null and next_round.has_active_hole() and pace_model.walking_yards_per_second > 0.0:
			var walk_yards: float = from_position.distance_to(next_round.active_hole_state.ball_position)
			delay += walk_yards / pace_model.walking_yards_per_second

	var metadata: Dictionary = live_metadata[group_id]
	metadata["next_action_time_seconds"] = current_time_seconds + delay
	live_metadata[group_id] = metadata


func _complete_live_hole(group_id: String) -> Array:
	var events: Array = []
	if not live_sessions.has(group_id):
		return events
	var session = live_sessions[group_id]
	var hole_number: int = int(session.hole_number)
	var group_result: Dictionary = session.result()
	var next_hole: int = int(group_result.get("next_hole_number", 0))

	traffic.leave_hole(group_id, hole_number)
	live_sessions.erase(group_id)
	live_metadata.erase(group_id)

	events.append(_record_event({
		"type": "LIVE_HOLE_FINISH",
		"group_id": group_id,
		"hole_number": hole_number,
		"next_hole_number": next_hole,
		"time_seconds": current_time_seconds,
		"play_result": group_result.duplicate(true)
	}))

	if next_hole > 0:
		var transition: Dictionary = _attempt_enter_next_hole(group_id, hole_number, next_hole)
		if not transition.is_empty():
			events.append(transition)

	var release_event: Dictionary = _attempt_waiting_first_release()
	if not release_event.is_empty():
		events.append(release_event)
	events.append_array(_reevaluate_blocked_transitions())
	return events


func _attempt_enter_next_hole(group_id: String, from_hole: int, to_hole: int) -> Dictionary:
	var group = living_course.population.group_by_id(group_id)
	if group == null:
		return {}
	var occupants: Array = traffic.groups_on_hole(to_hole)
	if occupants.is_empty():
		if not traffic.enter_hole(group_id, to_hole):
			return {}
		var started: bool = _begin_live_session(group_id)
		return _record_event({
			"type": "LIVE_INTER_HOLE_TRANSITION",
			"group_id": group_id,
			"from_hole_number": from_hole,
			"to_hole_number": to_hole,
			"entered": started,
			"reason": "OPEN_NEXT_HOLE",
			"time_seconds": current_time_seconds
		})

	var lead_group_id: String = str(occupants[occupants.size() - 1])
	var safety: Dictionary = _live_spacing_status(lead_group_id, group)
	if bool(safety.get("safe", false)):
		if not traffic.enter_hole(group_id, to_hole):
			return {}
		var started: bool = _begin_live_session(group_id)
		return _record_event({
			"type": "LIVE_INTER_HOLE_TRANSITION",
			"group_id": group_id,
			"lead_group_id": lead_group_id,
			"from_hole_number": from_hole,
			"to_hole_number": to_hole,
			"entered": started,
			"reason": str(safety.get("status", "SAFE_LIVE_SPACING")),
			"time_seconds": current_time_seconds,
			"spacing": safety.duplicate(true)
		})

	blocked_transitions[group_id] = {
		"group_id": group_id,
		"lead_group_id": lead_group_id,
		"from_hole_number": from_hole,
		"to_hole_number": to_hole,
		"arrival_time_seconds": current_time_seconds,
		"status": str(safety.get("status", "WAITING_FOR_LIVE_SPACING")),
		"spacing": safety.duplicate(true)
	}
	return _record_event({
		"type": "LIVE_INTER_HOLE_WAIT",
		"group_id": group_id,
		"lead_group_id": lead_group_id,
		"from_hole_number": from_hole,
		"to_hole_number": to_hole,
		"entered": false,
		"reason": str(safety.get("status", "WAITING_FOR_LIVE_SPACING")),
		"time_seconds": current_time_seconds,
		"spacing": safety.duplicate(true)
	})


func _reevaluate_blocked_transitions() -> Array:
	var events: Array = []
	var waiting: Array = blocked_transitions.keys().duplicate()
	waiting.sort_custom(func(a, b) -> bool:
		return float(blocked_transitions[a].get("arrival_time_seconds", 0.0)) < float(blocked_transitions[b].get("arrival_time_seconds", 0.0))
	)
	for group_value in waiting:
		var group_id: String = str(group_value)
		if not blocked_transitions.has(group_id):
			continue
		var blocked: Dictionary = blocked_transitions[group_id]
		var to_hole: int = int(blocked.get("to_hole_number", 0))
		var from_hole: int = int(blocked.get("from_hole_number", 0))
		var group = living_course.population.group_by_id(group_id)
		if group == null or to_hole <= 0:
			continue
		var occupants: Array = traffic.groups_on_hole(to_hole)
		var safety: Dictionary = {"safe": true, "status": "HOLE_CLEARED"}
		var lead_group_id: String = ""
		if not occupants.is_empty():
			lead_group_id = str(occupants[occupants.size() - 1])
			safety = _live_spacing_status(lead_group_id, group)
		if not bool(safety.get("safe", false)):
			blocked["lead_group_id"] = lead_group_id
			blocked["status"] = str(safety.get("status", "WAITING_FOR_LIVE_SPACING"))
			blocked["spacing"] = safety.duplicate(true)
			blocked_transitions[group_id] = blocked
			continue
		if not traffic.enter_hole(group_id, to_hole):
			continue
		blocked_transitions.erase(group_id)
		var started: bool = _begin_live_session(group_id)
		events.append(_record_event({
			"type": "LIVE_INTER_HOLE_TRANSITION",
			"group_id": group_id,
			"lead_group_id": lead_group_id,
			"from_hole_number": from_hole,
			"to_hole_number": to_hole,
			"entered": started,
			"reason": str(safety.get("status", "SAFE_LIVE_SPACING")),
			"wait_seconds": current_time_seconds - float(blocked.get("arrival_time_seconds", current_time_seconds)),
			"time_seconds": current_time_seconds,
			"spacing": safety.duplicate(true)
		}))
	return events


func _attempt_waiting_first_release() -> Dictionary:
	if living_course == null or living_course.start_sequencer.next_waiting_group_id().is_empty():
		return {}
	var result: Dictionary = release_next_group()
	if bool(result.get("released", false)):
		return result
	return {}


func _release_and_start_first_hole(group_id: String, reason: String, spacing: Dictionary) -> Dictionary:
	var expected: String = living_course.start_sequencer.next_waiting_group_id()
	if expected != group_id:
		return {}
	var release_result: Dictionary = living_course.release_next_group()
	if release_result.is_empty() or str(release_result.get("group_id", "")) != group_id:
		return {}
	if not traffic.enter_hole(group_id, 1):
		return {}
	var started: bool = _begin_live_session(group_id)
	var event := {
		"type": "LIVE_TEE_RELEASE",
		"released": started,
		"group_id": group_id,
		"hole_number": 1,
		"reason": reason,
		"time_seconds": current_time_seconds
	}
	if not spacing.is_empty():
		event["spacing"] = spacing.duplicate(true)
	return _record_event(event)


func _begin_live_session(group_id: String) -> bool:
	if live_sessions.has(group_id):
		return false
	var group = living_course.population.group_by_id(group_id)
	if group == null:
		return false
	var hole_number: int = group.current_hole_number()
	if hole_number <= 0 or traffic.group_hole(group_id) != hole_number:
		return false
	var control: Dictionary = group_controls.get(group_id, {"human_member_index": -1, "seed_base": 1})
	var human_index: int = int(control.get("human_member_index", -1))
	var seed_value: int = int(control.get("seed_base", 1)) + hole_number - 1
	var session = living_course.progression_coordinator.begin_session(group, seed_value, human_index)
	if session == null:
		return false
	live_sessions[group_id] = session
	live_metadata[group_id] = {
		"hole_number": hole_number,
		"human_member_index": human_index,
		"seed_value": seed_value,
		"started_at_seconds": current_time_seconds,
		"next_action_time_seconds": current_time_seconds + maxf(0.0, pace_model.shot_routine_seconds)
	}
	_record_event({
		"type": "LIVE_HOLE_START",
		"group_id": group_id,
		"hole_number": hole_number,
		"human_member_index": human_index,
		"time_seconds": current_time_seconds
	})
	return true


func _live_spacing_status(lead_group_id: String, following_group) -> Dictionary:
	if spacing_model == null or following_group == null:
		return {"safe": false, "status": "INVALID"}
	if not live_sessions.has(lead_group_id):
		# If the lead no longer owns a live session and is no longer on this hole,
		# the hole has cleared. A stale/missing session while still occupying traffic
		# is treated as unsafe instead of guessed through.
		if traffic.group_hole(lead_group_id) == 0:
			return {"safe": true, "status": "HOLE_CLEARED", "release_rule": "LEAD_GROUP_CLEARED_HOLE"}
		return {"safe": false, "status": "MISSING_LIVE_LEAD_AUTHORITY"}

	var session = live_sessions[lead_group_id]
	if session == null:
		return {"safe": false, "status": "MISSING_LIVE_LEAD_AUTHORITY"}
	if session.is_complete():
		return {"safe": true, "status": "HOLE_CLEARED", "release_rule": "LEAD_GROUP_CLEARED_HOLE"}

	var lead_group = session.group
	var hole = session.hole_definition
	if lead_group == null or hole == null:
		return {"safe": false, "status": "INVALID_LIVE_LEAD"}
	var credible_reach: float = spacing_model.maximum_tee_reach(following_group.golfers)
	if credible_reach <= 0.0:
		return {"safe": false, "status": "INVALID_CREDIBLE_REACH", "credible_reach_yards": credible_reach}

	var tee: Vector3 = hole.tee_position(str(lead_group.tee_id))
	var minimum_clearance: float = INF
	var all_green_or_holed: bool = true
	var member_states: Array = []
	for member_index in range(lead_group.member_count()):
		var position: Vector3 = tee
		var surface: String = "UNKNOWN"
		var holed: bool = false
		var autonomous_round = lead_group.rounds[member_index]
		if autonomous_round != null and autonomous_round.has_active_hole():
			position = autonomous_round.active_hole_state.ball_position
			surface = autonomous_round.active_hole_state.surface_name().to_upper()
			holed = bool(autonomous_round.active_hole_state.finished)
		else:
			var member_result: Dictionary = {}
			if member_index < session.member_results.size() and typeof(session.member_results[member_index]) == TYPE_DICTIONARY:
				member_result = session.member_results[member_index]
			if not member_result.is_empty():
				position = member_result.get("final_position", tee)
				surface = str(member_result.get("final_surface", "UNKNOWN")).to_upper()
				holed = bool(member_result.get("finished", false))
		var clearance: float = tee.distance_to(position)
		minimum_clearance = minf(minimum_clearance, clearance)
		var green_or_holed: bool = surface == "GREEN" or holed
		if not green_or_holed:
			all_green_or_holed = false
		member_states.append({
			"member_index": member_index,
			"surface": surface,
			"holed": holed,
			"clearance_yards": clearance,
			"green_or_holed": green_or_holed
		})

	if minimum_clearance == INF:
		minimum_clearance = 0.0
	var range_safe: bool = minimum_clearance > credible_reach + CLEARANCE_EPSILON
	var safe: bool = range_safe and all_green_or_holed
	var status: String = "SAFE_LIVE_SPACING"
	if not all_green_or_holed:
		status = "WAIT_FOR_LEAD_GROUP_GREEN"
	elif not range_safe:
		status = "WAIT_FOR_CREDIBLE_REACH_CLEARANCE"
	return {
		"safe": safe,
		"status": status,
		"release_rule": "RANGE_SAFE_AND_ALL_LEAD_GOLFERS_ON_GREEN",
		"credible_reach_yards": credible_reach,
		"minimum_clearance_yards": minimum_clearance,
		"range_safe": range_safe,
		"all_lead_golfers_green_or_holed": all_green_or_holed,
		"member_states": member_states
	}


func _record_event(event: Dictionary) -> Dictionary:
	var stored: Dictionary = event.duplicate(true)
	stored["event_index"] = event_history.size()
	event_history.append(stored)
	return stored.duplicate(true)
