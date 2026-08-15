extends Node

# POC-28A-F: Persistent Player World Session
# -------------------------------------------
# Long-lived authority bridge above the existing living-course stack. The player
# golfer is owned by this node so activity/presentation scenes can come and go
# without replacing the golfer. The living-course controller remains the sole
# authority for golf, traffic, scoring, and world-clock progression.
#
# A round is not a special player simulation. enter_round() inserts the exact same
# golfer object into an ordinary GolferGroup and designates that member as human
# through the existing POC-26 control contract. Per-round AutonomousRound/
# RoundState objects remain disposable activity state while golfer memory,
# development traits, GolfActivity, and world time persist here.

const ShotProgressiveLivingCourseController = preload("res://simulation/shot_progressive_living_course_controller.gd")
const GolfActivity = preload("res://simulation/golf_activity.gd")

const STATUS_IDLE := "IDLE"
const STATUS_WAITING := "WAITING"
const STATUS_PLAYING := "PLAYING"
const STATUS_FINISHED := "FINISHED"

var player_golfer = null
var course = null
var controller = null
var golf_activity = GolfActivity.new()

var world_day: int = 0
var world_time_seconds: float = 0.0
var activity_history: Array = []
var completed_rounds: Array = []
var active_round: Dictionary = {}
var round_sequence: int = 0


func configure(golfer, course_definition, starting_day: int = 0, starting_world_time_seconds: float = 0.0) -> bool:
	if golfer == null or course_definition == null or course_definition.hole_count() <= 0:
		return false
	if not active_round.is_empty():
		return false

	_adopt_player_golfer(golfer)
	player_golfer = golfer
	course = course_definition
	controller = ShotProgressiveLivingCourseController.new()
	if not controller.configure(course_definition):
		controller = null
		return false

	world_day = maxi(starting_day, 0)
	world_time_seconds = maxf(starting_world_time_seconds, 0.0)
	controller.current_time_seconds = world_time_seconds
	golf_activity = GolfActivity.new()
	activity_history.clear()
	completed_rounds.clear()
	active_round.clear()
	round_sequence = 0
	return true


func enter_round(
	group_id: String,
	other_golfers: Array,
	tee_id: String = "default",
	player_member_index: int = 0,
	seed_base: int = 1
) -> Dictionary:
	if player_golfer == null or controller == null or course == null:
		return {"entered": false, "reason": "SESSION_NOT_CONFIGURED"}
	if not active_round.is_empty():
		return {"entered": false, "reason": "PLAYER_ACTIVITY_ALREADY_ACTIVE"}
	if other_golfers.size() > 3:
		return {"entered": false, "reason": "GROUP_TOO_LARGE"}
	if player_member_index < 0 or player_member_index > other_golfers.size():
		return {"entered": false, "reason": "INVALID_PLAYER_MEMBER_INDEX"}

	var members: Array = other_golfers.duplicate()
	members.insert(player_member_index, player_golfer)
	if members.size() < 1 or members.size() > 4:
		return {"entered": false, "reason": "INVALID_GROUP_SIZE"}

	round_sequence += 1
	var normalized_group_id: String = group_id.strip_edges()
	if normalized_group_id.is_empty():
		normalized_group_id = "player_round_%d" % round_sequence

	if not controller.add_group(normalized_group_id, members, tee_id, player_member_index, seed_base):
		return {"entered": false, "reason": "GROUP_ENTRY_REJECTED"}

	active_round = {
		"activity_type": "ROUND",
		"sequence": round_sequence,
		"group_id": normalized_group_id,
		"tee_id": tee_id,
		"player_member_index": player_member_index,
		"seed_base": seed_base,
		"entered_day": world_day,
		"entered_time_seconds": world_time_seconds,
		"golfer_instance_id": player_golfer.get_instance_id(),
		"status": STATUS_WAITING
	}
	activity_history.append({
		"type": "ROUND_ENTERED",
		"sequence": round_sequence,
		"group_id": normalized_group_id,
		"day": world_day,
		"time_seconds": world_time_seconds,
		"tee_id": tee_id
	})
	return {
		"entered": true,
		"sequence": round_sequence,
		"group_id": normalized_group_id,
		"player_member_index": player_member_index,
		"tee_id": tee_id,
		"member_count": members.size(),
		"golfer_instance_id": player_golfer.get_instance_id()
	}


func add_world_group(group_id: String, golfers: Array, tee_id: String = "default", seed_base: int = 1) -> bool:
	if controller == null:
		return false
	return controller.add_group(group_id, golfers, tee_id, -1, seed_base)


func release_next_group() -> Dictionary:
	if controller == null:
		return {}
	var result: Dictionary = controller.release_next_group()
	_sync_world_clock()
	if bool(result.get("released", false)) and not active_round.is_empty() and str(result.get("group_id", "")) == str(active_round.get("group_id", "")):
		active_round["status"] = STATUS_PLAYING
	return result


func advance_world_time(delta_seconds: float) -> Array:
	if controller == null or delta_seconds < 0.0:
		return []
	var events: Array = controller.advance_time(delta_seconds)
	_sync_world_clock()
	_refresh_active_round_status()
	return events


func pending_player_decision() -> Dictionary:
	if controller == null or active_round.is_empty():
		return {}
	return controller.pending_human_decision(str(active_round.get("group_id", "")))


func submit_player_choice(candidate_index: int) -> Dictionary:
	if controller == null or active_round.is_empty():
		return {"played": false, "rejected": true, "reason": "NO_ACTIVE_PLAYER_ROUND"}
	var result: Dictionary = controller.submit_human_choice(str(active_round.get("group_id", "")), candidate_index)
	_sync_world_clock()
	_refresh_active_round_status()
	return result


func player_round_state():
	var group = _player_group()
	if group == null:
		return null
	var member_index: int = int(active_round.get("player_member_index", -1))
	if member_index < 0 or member_index >= group.rounds.size():
		return null
	var autonomous_round = group.rounds[member_index]
	if autonomous_round == null:
		return null
	return autonomous_round.round_state


func player_round_context() -> Dictionary:
	if active_round.is_empty() or controller == null:
		return {
			"activity_type": "NONE",
			"status": STATUS_IDLE,
			"day": world_day,
			"world_time_seconds": world_time_seconds
		}

	var group = _player_group()
	var round_state = player_round_state()
	if group == null or round_state == null:
		return {}
	var round_snapshot: Dictionary = round_state.snapshot()
	var hole = round_state.current_hole()
	var hole_number: int = int(round_snapshot.get("current_hole_number", 0))
	var traffic_hole: int = controller.traffic.group_hole(str(active_round.get("group_id", ""))) if controller.traffic != null else 0
	var blocked: Dictionary = controller.blocked_transitions.get(str(active_round.get("group_id", "")), {})

	return {
		"activity_type": "ROUND",
		"status": str(active_round.get("status", group.status)),
		"day": world_day,
		"world_time_seconds": world_time_seconds,
		"group_id": str(active_round.get("group_id", "")),
		"group_status": str(group.status),
		"group_member_count": group.member_count(),
		"player_member_index": int(active_round.get("player_member_index", -1)),
		"tee_id": str(active_round.get("tee_id", "default")),
		"traffic_hole_number": traffic_hole,
		"waiting": not blocked.is_empty(),
		"waiting_reason": str(blocked.get("status", "")),
		"hole_number": hole_number,
		"hole_name": str(hole.hole_name) if hole != null else "",
		"par": int(hole.par) if hole != null else 0,
		"yardage": float(hole.tee_yardage(str(active_round.get("tee_id", "default")))) if hole != null else 0.0,
		"round_phase": str(round_snapshot.get("round_phase", "")),
		"holes_completed": int(round_snapshot.get("holes_completed", 0)),
		"remaining_holes": int(round_snapshot.get("remaining_holes", 0)),
		"total_strokes": int(round_snapshot.get("total_strokes", 0)),
		"par_played": int(round_snapshot.get("par_played", 0)),
		"score_to_par": int(round_snapshot.get("score_to_par", 0)),
		"front_nine": round_snapshot.get("front_nine", {}).duplicate(true),
		"back_nine": round_snapshot.get("back_nine", {}).duplicate(true),
		"scorecard": round_snapshot.get("scorecard", []).duplicate(true),
		"round_finished": bool(round_snapshot.get("round_finished", false))
	}


# POC-28D/E/F: archive an authoritative completed round, record its actual shot
# exposure in GolfActivity, then retire the finished group so the same persistent
# golfer may enter another ordinary group without recreating the world.
func finalize_player_round() -> Dictionary:
	if controller == null or active_round.is_empty():
		return {"finalized": false, "reason": "NO_ACTIVE_PLAYER_ROUND"}

	var group_id: String = str(active_round.get("group_id", ""))
	var group = _player_group()
	var round_state = player_round_state()
	if group == null or round_state == null:
		return {"finalized": false, "reason": "MISSING_ROUND_AUTHORITY"}
	if str(group.status) != STATUS_FINISHED or not bool(round_state.complete):
		return {"finalized": false, "reason": "ROUND_NOT_FINISHED"}
	if controller.traffic != null and controller.traffic.group_hole(group_id) != 0:
		return {"finalized": false, "reason": "GROUP_STILL_ON_COURSE"}
	if controller.live_sessions.has(group_id) or controller.live_metadata.has(group_id) or controller.blocked_transitions.has(group_id):
		return {"finalized": false, "reason": "GROUP_AUTHORITY_STILL_ACTIVE"}

	var round_snapshot: Dictionary = round_state.snapshot()
	var shot_events: Array = _player_round_shot_events(group_id, int(active_round.get("player_member_index", -1)))
	var statistics: Dictionary = _authoritative_round_statistics(shot_events)
	var exposure: Dictionary = statistics.get("shot_type_exposure", {}).duplicate(true)
	var activity_result: Dictionary = golf_activity.record_round_on_day(world_day, exposure)

	var archived: Dictionary = {
		"activity_type": "ROUND",
		"sequence": int(active_round.get("sequence", round_sequence)),
		"group_id": group_id,
		"course_id": str(course.course_id) if course != null else "",
		"course_name": str(course.course_name) if course != null else "",
		"tee_id": str(active_round.get("tee_id", "default")),
		"golfer_instance_id": player_golfer.get_instance_id(),
		"entered_day": int(active_round.get("entered_day", world_day)),
		"completed_day": world_day,
		"entered_time_seconds": float(active_round.get("entered_time_seconds", world_time_seconds)),
		"completed_time_seconds": world_time_seconds,
		"elapsed_world_seconds": maxf(world_time_seconds - float(active_round.get("entered_time_seconds", world_time_seconds)), 0.0),
		"total_strokes": int(round_snapshot.get("total_strokes", 0)),
		"par_played": int(round_snapshot.get("par_played", 0)),
		"score_to_par": int(round_snapshot.get("score_to_par", 0)),
		"front_nine": round_snapshot.get("front_nine", {}).duplicate(true),
		"back_nine": round_snapshot.get("back_nine", {}).duplicate(true),
		"scorecard": round_snapshot.get("scorecard", []).duplicate(true),
		"statistics": statistics.duplicate(true),
		"activity_record": activity_result.duplicate(true)
	}

	# Population is current-world membership, not history. Archive first, then
	# release golfer assignments. Controller dictionaries are configuration for the
	# retired group and may be safely dropped only after all live authority is gone.
	if not controller.living_course.retire_finished_group(group_id):
		return {"finalized": false, "reason": "GROUP_RETIREMENT_REJECTED"}
	controller.group_controls.erase(group_id)

	completed_rounds.append(archived.duplicate(true))
	activity_history.append({
		"type": "ROUND_COMPLETED",
		"sequence": int(archived.get("sequence", 0)),
		"group_id": group_id,
		"day": world_day,
		"time_seconds": world_time_seconds,
		"total_strokes": int(archived.get("total_strokes", 0)),
		"score_to_par": int(archived.get("score_to_par", 0)),
		"authoritative_shots": int(statistics.get("total_shots", 0))
	})
	active_round.clear()
	return {
		"finalized": true,
		"round": archived.duplicate(true),
		"golfer_instance_id": player_golfer.get_instance_id(),
		"world_time_seconds": world_time_seconds,
		"career_rounds_played": golf_activity.career_rounds_played
	}


func latest_completed_round() -> Dictionary:
	if completed_rounds.is_empty():
		return {}
	return completed_rounds[completed_rounds.size() - 1].duplicate(true)


func snapshot() -> Dictionary:
	return {
		"configured": player_golfer != null and controller != null,
		"golfer_instance_id": player_golfer.get_instance_id() if player_golfer != null else 0,
		"golfer_name": str(player_golfer.get("golfer_name")) if player_golfer != null else "",
		"course_id": str(course.course_id) if course != null else "",
		"day": world_day,
		"world_time_seconds": world_time_seconds,
		"active_round": active_round.duplicate(true),
		"completed_rounds": completed_rounds.duplicate(true),
		"activity_history": activity_history.duplicate(true),
		"golf_activity": golf_activity.state() if golf_activity != null else {},
		"round_context": player_round_context(),
		"world": controller.snapshot() if controller != null else {}
	}


func _adopt_player_golfer(golfer) -> void:
	if golfer == null or golfer.get_parent() == self:
		return
	var old_parent = golfer.get_parent()
	if old_parent != null:
		old_parent.remove_child(golfer)
	add_child(golfer)


func _player_group():
	if controller == null or controller.living_course == null or active_round.is_empty():
		return null
	return controller.living_course.population.group_by_id(str(active_round.get("group_id", "")))


func _player_round_shot_events(group_id: String, member_index: int) -> Array:
	var result: Array = []
	if controller == null or group_id.is_empty() or member_index < 0:
		return result
	for event_value in controller.event_history:
		if typeof(event_value) != TYPE_DICTIONARY:
			continue
		var event: Dictionary = event_value
		if str(event.get("type", "")) != "LIVE_SHOT":
			continue
		if str(event.get("group_id", "")) != group_id or int(event.get("member_index", -1)) != member_index:
			continue
		result.append(event.duplicate(true))
	return result


func _authoritative_round_statistics(shot_events: Array) -> Dictionary:
	var exposure: Dictionary = {0: 0, 1: 0, 2: 0, 3: 0}
	var penalties: int = 0
	var putts: int = 0
	var human_provenance: int = 0
	for event_value in shot_events:
		if typeof(event_value) != TYPE_DICTIONARY:
			continue
		var event: Dictionary = event_value
		var shot: Dictionary = event.get("shot", {})
		var shot_type: int = int(shot.get("shot_type", -1))
		if exposure.has(shot_type):
			exposure[shot_type] = int(exposure.get(shot_type, 0)) + 1
		if shot_type == 3:
			putts += 1
		penalties += max(0, int(event.get("penalty_strokes", shot.get("penalty_strokes", 0))))
		if str(event.get("control_source", "")) == "HUMAN" or str(event.get("choice_source", "")) == "HUMAN":
			human_provenance += 1
	return {
		"total_shots": shot_events.size(),
		"putts": putts,
		"penalty_strokes": penalties,
		"human_shots": human_provenance,
		"shot_type_exposure": exposure
	}


func _sync_world_clock() -> void:
	if controller != null:
		world_time_seconds = maxf(world_time_seconds, float(controller.current_time_seconds))


func _refresh_active_round_status() -> void:
	if active_round.is_empty():
		return
	var group = _player_group()
	if group == null:
		return
	active_round["status"] = str(group.status)