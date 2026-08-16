extends RefCounted

# POC-29E: Return-to-World Coordinator
# ------------------------------------
# Gives player-facing hub scenes one lifecycle seam for leaving an activity while
# preserving persistent-world authority. Completed activities delegate to the
# existing PlayerWorldSession finalizers. Practice may be cancelled before results
# are committed; cancellation awards no repetitions, development, or time cost.
# An unfinished scored round is never silently abandoned through this layer.

const ACTION_AUTO := "AUTO"
const ACTION_COMPLETE := "COMPLETE"
const ACTION_CANCEL := "CANCEL"

const ACTIVITY_NONE := "NONE"
const ACTIVITY_ROUND := "ROUND"
const ACTIVITY_PRACTICE := "PRACTICE"

const REASON_SESSION_NOT_CONFIGURED := "SESSION_NOT_CONFIGURED"
const REASON_INVALID_RETURN_ACTION := "INVALID_RETURN_ACTION"
const REASON_ROUND_ABANDONMENT_NOT_SUPPORTED := "ROUND_ABANDONMENT_NOT_SUPPORTED"


func return_to_world(session, action: String = ACTION_AUTO, payload: Dictionary = {}) -> Dictionary:
	if session == null:
		return _rejected(ACTIVITY_NONE, REASON_SESSION_NOT_CONFIGURED)
	var session_snapshot: Dictionary = session.snapshot()
	if not bool(session_snapshot.get("configured", false)):
		return _rejected(ACTIVITY_NONE, REASON_SESSION_NOT_CONFIGURED)

	var normalized_action: String = action.strip_edges().to_upper()
	if normalized_action.is_empty():
		normalized_action = ACTION_AUTO
	if not normalized_action in [ACTION_AUTO, ACTION_COMPLETE, ACTION_CANCEL]:
		return _rejected(ACTIVITY_NONE, REASON_INVALID_RETURN_ACTION)

	var active_round: Dictionary = session_snapshot.get("active_round", {})
	var active_practice: Dictionary = session_snapshot.get("active_practice", {})
	if active_round.is_empty() and active_practice.is_empty():
		return {
			"returned": true,
			"already_world": true,
			"activity_type": ACTIVITY_NONE,
			"reason": "",
			"golfer_instance_id": session.player_golfer.get_instance_id() if session.player_golfer != null else 0,
			"controller_instance_id": session.controller.get_instance_id() if session.controller != null else 0,
			"world_time_seconds": session.world_time_seconds
		}

	if not active_practice.is_empty():
		if normalized_action == ACTION_CANCEL:
			return _cancel_practice(session, active_practice)
		return _complete_practice(session, payload)

	if normalized_action == ACTION_CANCEL:
		return _rejected(ACTIVITY_ROUND, REASON_ROUND_ABANDONMENT_NOT_SUPPORTED)
	return _complete_round(session)


func _complete_practice(session, payload: Dictionary) -> Dictionary:
	var observations_value = payload.get("observations", {})
	if typeof(observations_value) != TYPE_DICTIONARY:
		return _rejected(ACTIVITY_PRACTICE, "INVALID_PRACTICE_OBSERVATIONS")
	var finalized: Dictionary = session.finalize_practice(observations_value)
	if not bool(finalized.get("finalized", false)):
		return {
			"returned": false,
			"already_world": false,
			"activity_type": ACTIVITY_PRACTICE,
			"reason": str(finalized.get("reason", "PRACTICE_FINALIZATION_REJECTED")),
			"finalization": finalized.duplicate(true)
		}
	return {
		"returned": true,
		"already_world": false,
		"activity_type": ACTIVITY_PRACTICE,
		"reason": "",
		"completed": true,
		"cancelled": false,
		"finalization": finalized.duplicate(true),
		"golfer_instance_id": session.player_golfer.get_instance_id(),
		"controller_instance_id": session.controller.get_instance_id(),
		"world_time_seconds": session.world_time_seconds
	}


func _cancel_practice(session, active_practice: Dictionary) -> Dictionary:
	var cancelled: Dictionary = active_practice.duplicate(true)
	session.activity_history.append({
		"type": "PRACTICE_CANCELLED",
		"sequence": int(cancelled.get("sequence", 0)),
		"day": session.world_day,
		"time_seconds": session.world_time_seconds,
		"total_repetitions": int(cancelled.get("total_repetitions", 0))
	})
	session.active_practice.clear()
	return {
		"returned": true,
		"already_world": false,
		"activity_type": ACTIVITY_PRACTICE,
		"reason": "",
		"completed": false,
		"cancelled": true,
		"cancelled_activity": cancelled,
		"golfer_instance_id": session.player_golfer.get_instance_id(),
		"controller_instance_id": session.controller.get_instance_id(),
		"world_time_seconds": session.world_time_seconds
	}


func _complete_round(session) -> Dictionary:
	var finalized: Dictionary = session.finalize_player_round()
	if not bool(finalized.get("finalized", false)):
		return {
			"returned": false,
			"already_world": false,
			"activity_type": ACTIVITY_ROUND,
			"reason": str(finalized.get("reason", "ROUND_FINALIZATION_REJECTED")),
			"finalization": finalized.duplicate(true)
		}
	return {
		"returned": true,
		"already_world": false,
		"activity_type": ACTIVITY_ROUND,
		"reason": "",
		"completed": true,
		"cancelled": false,
		"finalization": finalized.duplicate(true),
		"golfer_instance_id": session.player_golfer.get_instance_id(),
		"controller_instance_id": session.controller.get_instance_id(),
		"world_time_seconds": session.world_time_seconds
	}


func _rejected(activity_type: String, reason: String) -> Dictionary:
	return {
		"returned": false,
		"already_world": false,
		"activity_type": activity_type,
		"reason": reason
	}
