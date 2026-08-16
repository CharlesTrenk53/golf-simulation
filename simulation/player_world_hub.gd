extends RefCounted

# POC-29A-F: Persistent World Hub + Activity Selection/Launch/Return
# -----------------------------------------------------------------
# Player-facing coordinator over PlayerWorldSession. Hub context is a read-only
# projection and owns no golfer, course, controller, round/practice state, world
# clock, or activity state. Selection remains pure through PlayerActivityContract;
# accepted selections are handed to PlayerActivityLauncher, while activity exit is
# routed through PlayerActivityReturnCoordinator back into persistent authority.
#
# Important: routine hub rendering intentionally reads only the lightweight state it
# needs. It must not deep-snapshot the full accumulated living world/event history
# merely to answer player-facing navigation questions.

const PlayerActivityContract = preload("res://simulation/player_activity_contract.gd")
const PlayerActivityLauncher = preload("res://simulation/player_activity_launcher.gd")
const PlayerActivityReturnCoordinator = preload("res://simulation/player_activity_return_coordinator.gd")

const STATE_WORLD := "WORLD"
const STATE_ACTIVITY := "ACTIVITY"
const ACTIVITY_NONE := "NONE"

var world_session = null
var activity_contract = PlayerActivityContract.new()
var activity_launcher = PlayerActivityLauncher.new()
var activity_return = PlayerActivityReturnCoordinator.new()


func configure(session) -> bool:
	if not _session_configured(session):
		return false
	world_session = session
	return true


func is_configured() -> bool:
	return _session_configured(world_session)


func activity_catalog() -> Array:
	return activity_contract.catalog(world_session)


func select_activity(activity_type: String, options: Dictionary = {}) -> Dictionary:
	return activity_contract.select(world_session, activity_type, options)


func launch_selected_activity(selection: Dictionary) -> Dictionary:
	return activity_launcher.launch(world_session, selection)


func return_to_world(action: String = PlayerActivityReturnCoordinator.ACTION_AUTO, payload: Dictionary = {}) -> Dictionary:
	return activity_return.return_to_world(world_session, action, payload)


func context() -> Dictionary:
	if not is_configured():
		return {
			"configured": false,
			"state": STATE_WORLD,
			"can_choose_activity": false,
			"active_activity_type": ACTIVITY_NONE,
			"activity_catalog": activity_catalog()
		}

	var active_round: Dictionary = world_session.active_round.duplicate(true)
	var active_practice: Dictionary = world_session.active_practice.duplicate(true)
	var active_activity_type: String = ACTIVITY_NONE
	if not active_round.is_empty():
		active_activity_type = str(active_round.get("activity_type", "ROUND"))
	elif not active_practice.is_empty():
		active_activity_type = str(active_practice.get("activity_type", "PRACTICE"))
	var hub_state: String = STATE_WORLD if active_activity_type == ACTIVITY_NONE else STATE_ACTIVITY

	var population: Dictionary = {}
	if world_session.controller != null and world_session.controller.living_course != null:
		population = world_session.controller.living_course.population.snapshot()

	var golfer = world_session.player_golfer
	var golf_activity: Dictionary = world_session.golf_activity.state() if world_session.golf_activity != null else {}
	return {
		"configured": true,
		"state": hub_state,
		"can_choose_activity": hub_state == STATE_WORLD,
		"active_activity_type": active_activity_type,
		"activity_catalog": activity_catalog(),
		"golfer_instance_id": golfer.get_instance_id() if golfer != null else 0,
		"golfer_name": str(golfer.get("golfer_name")) if golfer != null else "",
		"controller_instance_id": world_session.controller.get_instance_id() if world_session.controller != null else 0,
		"course_id": str(world_session.course.course_id) if world_session.course != null else "",
		"course_name": str(world_session.course.course_name) if world_session.course != null else "",
		"day": int(world_session.world_day),
		"world_time_seconds": float(world_session.world_time_seconds),
		"completed_rounds": world_session.completed_rounds.size(),
		"completed_practices": world_session.completed_practices.size(),
		"activity_history_count": world_session.activity_history.size(),
		"career_rounds_played": int(golf_activity.get("career_rounds_played", 0)),
		"career_practice_repetitions": golf_activity.get("career_practice_repetitions", {}).duplicate(true),
		"total_practice_repetitions": int(golf_activity.get("total_practice_repetitions", 0)),
		"population": population.duplicate(true),
		"abilities": _golfer_abilities(golfer),
		"active_round": active_round,
		"active_practice": active_practice
	}


func _session_configured(session) -> bool:
	return (
		session != null
		and session.player_golfer != null
		and session.controller != null
		and session.course != null
	)


func _golfer_abilities(golfer) -> Dictionary:
	if golfer == null:
		return {}
	return {
		"driving": float(golfer.driving),
		"approach": float(golfer.approach),
		"short_game": float(golfer.short_game),
		"putting": float(golfer.putting)
	}
