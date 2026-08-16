extends RefCounted

# POC-29A: Persistent World Hub Foundation
# ----------------------------------------
# Read-only player-facing coordinator over PlayerWorldSession. The hub deliberately
# owns no golfer, course, controller, round state, or world clock. It projects the
# current persistent session into a stable world/activity context so presentation
# scenes can come and go without creating a second "menu world" or copying state.

const STATE_WORLD := "WORLD"
const STATE_ACTIVITY := "ACTIVITY"
const ACTIVITY_NONE := "NONE"

var world_session = null


func configure(session) -> bool:
	if session == null:
		return false
	var session_snapshot: Dictionary = session.snapshot()
	if not bool(session_snapshot.get("configured", false)):
		return false
	world_session = session
	return true


func is_configured() -> bool:
	if world_session == null:
		return false
	var session_snapshot: Dictionary = world_session.snapshot()
	return bool(session_snapshot.get("configured", false))


func context() -> Dictionary:
	if not is_configured():
		return {
			"configured": false,
			"state": STATE_WORLD,
			"can_choose_activity": false,
			"active_activity_type": ACTIVITY_NONE
		}

	var session_snapshot: Dictionary = world_session.snapshot()
	var active_round: Dictionary = session_snapshot.get("active_round", {})
	var active_activity_type: String = ACTIVITY_NONE
	if not active_round.is_empty():
		active_activity_type = str(active_round.get("activity_type", "ROUND"))
	var hub_state: String = STATE_WORLD if active_activity_type == ACTIVITY_NONE else STATE_ACTIVITY

	var population: Dictionary = {}
	if world_session.controller != null and world_session.controller.living_course != null:
		population = world_session.controller.living_course.population.snapshot()

	var golfer = world_session.player_golfer
	var golf_activity: Dictionary = session_snapshot.get("golf_activity", {})
	return {
		"configured": true,
		"state": hub_state,
		"can_choose_activity": hub_state == STATE_WORLD,
		"active_activity_type": active_activity_type,
		"golfer_instance_id": golfer.get_instance_id() if golfer != null else 0,
		"golfer_name": str(golfer.get("golfer_name")) if golfer != null else "",
		"controller_instance_id": world_session.controller.get_instance_id() if world_session.controller != null else 0,
		"course_id": str(world_session.course.course_id) if world_session.course != null else "",
		"course_name": str(world_session.course.course_name) if world_session.course != null else "",
		"day": int(session_snapshot.get("day", 0)),
		"world_time_seconds": float(session_snapshot.get("world_time_seconds", 0.0)),
		"completed_rounds": session_snapshot.get("completed_rounds", []).size(),
		"activity_history_count": session_snapshot.get("activity_history", []).size(),
		"career_rounds_played": int(golf_activity.get("career_rounds_played", 0)),
		"population": population.duplicate(true),
		"abilities": _golfer_abilities(golfer),
		"active_round": active_round.duplicate(true)
	}


func _golfer_abilities(golfer) -> Dictionary:
	if golfer == null:
		return {}
	return {
		"driving": float(golfer.driving),
		"approach": float(golfer.approach),
		"short_game": float(golfer.short_game),
		"putting": float(golfer.putting)
	}
