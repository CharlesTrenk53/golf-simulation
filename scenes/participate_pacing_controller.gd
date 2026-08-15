extends RefCounted

# Pre-POC-28: Participate pacing policy
# -------------------------------------
# Keeps authoritative golf-world time separate from the amount of real time the
# player must watch. When presentation is caught up and no human decision is
# already waiting, the Participate experience may jump the world clock directly
# to the next scheduled group action. Walking, shot-routine, and penalty time
# remain represented in authoritative timestamps/traffic; they are simply not
# exposed as dead-air countdowns to the player.
#
# Once a human decision is ready, fast-forward stops. The ordinary scaled world
# clock can continue while the player thinks so autonomous groups remain alive.

const MODE_FAST_FORWARD := "FAST_FORWARD"
const MODE_REALTIME := "REALTIME"
const TIME_EPSILON := 0.001


func idle_advance(controller, human_group_id: String = "") -> Dictionary:
	if controller == null:
		return {}

	var normalized_human_group: String = human_group_id.strip_edges()
	if not normalized_human_group.is_empty() and _human_turn_ready(controller, normalized_human_group):
		return {
			"mode": MODE_REALTIME,
			"reason": "HUMAN_DECISION_READY",
			"delta_seconds": 0.0,
			"target_time_seconds": float(controller.current_time_seconds),
			"group_id": normalized_human_group
		}

	var earliest_time: float = INF
	var earliest_group: String = ""
	for group_value in controller.live_sessions.keys():
		var group_id: String = str(group_value)
		var live_session = controller.live_sessions.get(group_id, null)
		if live_session == null or live_session.has_failed() or live_session.is_complete():
			continue
		var turn: Dictionary = live_session.current_turn()
		if turn.is_empty():
			continue
		var metadata: Dictionary = controller.live_metadata.get(group_id, {})
		var ready_time: float = float(metadata.get("next_action_time_seconds", INF))
		if ready_time < earliest_time - TIME_EPSILON or (
			abs(ready_time - earliest_time) <= TIME_EPSILON
			and (earliest_group.is_empty() or group_id < earliest_group)
		):
			earliest_time = ready_time
			earliest_group = group_id

	if earliest_group.is_empty() or earliest_time == INF:
		return {}

	var current_time: float = float(controller.current_time_seconds)
	return {
		"mode": MODE_FAST_FORWARD,
		"reason": "NEXT_SCHEDULED_ACTION",
		"delta_seconds": maxf(0.0, earliest_time - current_time),
		"target_time_seconds": maxf(current_time, earliest_time),
		"group_id": earliest_group
	}


func _human_turn_ready(controller, group_id: String) -> bool:
	if not controller.live_sessions.has(group_id):
		return false
	var live_session = controller.live_sessions.get(group_id, null)
	if live_session == null or live_session.has_failed() or live_session.is_complete():
		return false
	var turn: Dictionary = live_session.current_turn()
	if turn.is_empty() or str(turn.get("control_source", "AI")) != "HUMAN":
		return false
	var metadata: Dictionary = controller.live_metadata.get(group_id, {})
	var ready_time: float = float(metadata.get("next_action_time_seconds", INF))
	return float(controller.current_time_seconds) + TIME_EPSILON >= ready_time
