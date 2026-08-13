extends RefCounted

# POC-24H: Inter-Hole Transition Scheduler
# ----------------------------------------
# A following group may enter the next hole only after both conditions are true:
# 1) it has physically finished the previous hole, and
# 2) the group ahead has reached a safe clearance milestone on the next hole.
#
# The scheduler therefore turns two independently-derived absolute times into one
# deterministic transition event. It does not invent a fixed tee interval.

var pending_by_group: Dictionary = {}

func schedule_transition(
	following_group_id: String,
	lead_group_id: String,
	from_hole_number: int,
	to_hole_number: int,
	follower_arrival_time_seconds: float,
	lead_safe_time_seconds: float
) -> Dictionary:
	var follower_id := following_group_id.strip_edges()
	var lead_id := lead_group_id.strip_edges()
	if follower_id.is_empty() or lead_id.is_empty() or follower_id == lead_id:
		return {}
	if from_hole_number <= 0 or to_hole_number != from_hole_number + 1:
		return {}
	if follower_arrival_time_seconds < 0.0 or lead_safe_time_seconds < 0.0:
		return {}
	if pending_by_group.has(follower_id):
		return pending_by_group[follower_id].duplicate(true)

	var transition_time: float = max(follower_arrival_time_seconds, lead_safe_time_seconds)
	var wait_seconds: float = max(0.0, lead_safe_time_seconds - follower_arrival_time_seconds)
	var event := {
		"scheduled": true,
		"following_group_id": follower_id,
		"lead_group_id": lead_id,
		"from_hole_number": from_hole_number,
		"to_hole_number": to_hole_number,
		"follower_arrival_time_seconds": follower_arrival_time_seconds,
		"lead_safe_time_seconds": lead_safe_time_seconds,
		"transition_time_seconds": transition_time,
		"wait_seconds": wait_seconds,
		"waited_for_group_ahead": wait_seconds > 0.0,
		"status": "WAITING_FOR_GROUP_AHEAD" if wait_seconds > 0.0 else "READY_ON_ARRIVAL"
	}
	pending_by_group[follower_id] = event
	return event.duplicate(true)

func due_transitions(current_time_seconds: float) -> Array:
	if current_time_seconds < 0.0:
		return []
	var due: Array = []
	for follower_id in pending_by_group.keys():
		var event: Dictionary = pending_by_group[follower_id]
		if float(event.get("transition_time_seconds", INF)) <= current_time_seconds:
			due.append(event.duplicate(true))
	due.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_time: float = float(a.get("transition_time_seconds", 0.0))
		var b_time: float = float(b.get("transition_time_seconds", 0.0))
		if is_equal_approx(a_time, b_time):
			return str(a.get("following_group_id", "")) < str(b.get("following_group_id", ""))
		return a_time < b_time
	)
	for event in due:
		pending_by_group.erase(str(event.get("following_group_id", "")))
	return due

func pending_transition(following_group_id: String) -> Dictionary:
	return pending_by_group.get(following_group_id.strip_edges(), {}).duplicate(true)

func cancel_transition(following_group_id: String) -> bool:
	var follower_id := following_group_id.strip_edges()
	if not pending_by_group.has(follower_id):
		return false
	pending_by_group.erase(follower_id)
	return true

func snapshot() -> Dictionary:
	var pending: Array = []
	for event in pending_by_group.values():
		pending.append(event.duplicate(true))
	pending.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("transition_time_seconds", 0.0)) < float(b.get("transition_time_seconds", 0.0))
	)
	return {
		"pending_count": pending.size(),
		"pending_transitions": pending
	}
