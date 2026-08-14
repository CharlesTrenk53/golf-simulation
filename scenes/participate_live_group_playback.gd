extends Node

# POC-26E: Live Participate Group Playback
# -----------------------------------------
# Presentation-only adapter for the shot-progressive POC-26D runtime. It consumes
# already-resolved LIVE_SHOT events and feeds them into the existing POC-25 golfer
# and ball visuals. It never chooses a shot, changes a landing position, advances
# traffic, or mutates scoring authority.
#
# The POC-25 visual rules remain intact: one visible ball flight at a time, all
# golfers remain on the tee until every member has played a first shot, then the
# group disperses to the authoritative first-shot resolved positions.

@export var tee_dispersion_duration_seconds: float = 2.25

var group_visual = null
var group_id: String = ""
var hole_number: int = 0
var queued_events: Array = []
var presented_events: Array = []
var tee_rest_positions: Array = []
var tee_destinations: Dictionary = {}
var tee_dispersion: Dictionary = {}


func configure(group_visual_value, live_group_id: String, live_hole_number: int) -> bool:
	clear_playback()
	if group_visual_value == null or live_group_id.strip_edges().is_empty() or live_hole_number <= 0:
		return false
	if group_visual_value.course_world == null or group_visual_value.group == null:
		return false
	group_visual = group_visual_value
	group_id = live_group_id.strip_edges()
	hole_number = live_hole_number
	if str(group_visual.group.group_id) != group_id:
		clear_playback()
		return false
	if group_visual.course_world.course.hole_by_number(hole_number) == null:
		clear_playback()
		return false
	if not group_visual.sync_from_authority():
		clear_playback()
		return false
	tee_rest_positions = group_visual.member_world_positions()
	return tee_rest_positions.size() == group_visual.member_visuals.size()


func enqueue_authoritative_shot(event: Dictionary) -> bool:
	if group_visual == null or event.is_empty():
		return false
	if str(event.get("type", "")) != "LIVE_SHOT":
		return false
	if str(event.get("group_id", "")) != group_id:
		return false
	if int(event.get("hole_number", 0)) != hole_number:
		return false
	var member_index: int = int(event.get("member_index", -1))
	if member_index < 0 or member_index >= group_visual.member_visuals.size():
		return false
	var shot: Dictionary = event.get("shot", {})
	if shot.is_empty() or not shot.has("start_position") or not shot.has("landing_position"):
		return false
	var queued: Dictionary = event.duplicate(true)
	queued["world_shot"] = _world_shot(shot)
	queued_events.append(queued)
	return true


func has_pending_events() -> bool:
	return not queued_events.is_empty()


func has_active_flight() -> bool:
	if group_visual == null:
		return false
	for member_index_value in group_visual.active_member_shots.keys():
		var member_index: int = int(member_index_value)
		if member_index >= 0 and member_index < group_visual.member_ball_visuals.size():
			var ball_visual = group_visual.member_ball_visuals[member_index]
			if ball_visual != null and ball_visual.is_flying:
				return true
	return false


func has_active_tee_dispersion() -> bool:
	return not tee_dispersion.is_empty()


func is_busy() -> bool:
	return has_active_flight() or has_active_tee_dispersion()


func next_event() -> Dictionary:
	if queued_events.is_empty():
		return {}
	return queued_events[0].duplicate(true)


func present_next(animate: bool = true) -> Dictionary:
	if group_visual == null or queued_events.is_empty() or is_busy():
		return {}
	if group_visual.has_active_inter_hole_transition():
		return {}
	var event: Dictionary = queued_events[0]
	var member_index: int = int(event.get("member_index", -1))
	var world_shot: Dictionary = event.get("world_shot", {})
	# A next-hole playback can be created while the visual inter-hole walk is only
	# beginning, so configure() may have captured the previous green as the tee-rest
	# formation. The first tee shot cannot present until that walk is finished; at
	# this exact boundary the visible member positions are therefore the true new
	# tee formation. Refresh once before any tee destination is recorded so later
	# first-shot completions return golfers to the new tee, never the prior green.
	if int(world_shot.get("shot_number", 0)) == 1 and tee_destinations.is_empty():
		tee_rest_positions = group_visual.member_world_positions()
	if not _begin_member_visual(member_index, world_shot, animate):
		return {}
	queued_events.remove_at(0)
	var record: Dictionary = event.duplicate(true)
	record["presented"] = true
	record["animated"] = animate
	presented_events.append(record)
	if not animate:
		_complete_member_visual(member_index)
	return record.duplicate(true)


func complete_finished_flights() -> int:
	if group_visual == null:
		return 0
	var completed: int = 0
	var active_members: Array = group_visual.active_member_shots.keys()
	active_members.sort()
	for member_index_value in active_members:
		var member_index: int = int(member_index_value)
		if member_index < 0 or member_index >= group_visual.member_ball_visuals.size():
			continue
		var ball_visual = group_visual.member_ball_visuals[member_index]
		if ball_visual != null and not ball_visual.is_flying:
			if _complete_member_visual(member_index):
				completed += 1
	return completed


func advance_tee_dispersion(delta_seconds: float) -> bool:
	if tee_dispersion.is_empty() or group_visual == null:
		return false
	var duration: float = maxf(float(tee_dispersion.get("duration_seconds", tee_dispersion_duration_seconds)), 0.001)
	var elapsed: float = float(tee_dispersion.get("elapsed_seconds", 0.0)) + maxf(delta_seconds, 0.0)
	tee_dispersion["elapsed_seconds"] = elapsed
	var t: float = clampf(elapsed / duration, 0.0, 1.0)
	var eased: float = t * t * (3.0 - 2.0 * t)
	var starts: Array = tee_dispersion.get("start_positions", [])
	var destinations: Array = tee_dispersion.get("destination_positions", [])
	for index in range(mini(group_visual.member_visuals.size(), mini(starts.size(), destinations.size()))):
		if typeof(starts[index]) != TYPE_VECTOR3 or typeof(destinations[index]) != TYPE_VECTOR3:
			continue
		group_visual.member_visuals[index].place_at_ball(starts[index].lerp(destinations[index], eased))
	if t >= 1.0:
		for index in range(mini(group_visual.member_visuals.size(), destinations.size())):
			if typeof(destinations[index]) == TYPE_VECTOR3:
				group_visual.member_visuals[index].place_at_ball(destinations[index])
		tee_dispersion.clear()
		tee_destinations.clear()
		return false
	return true


func drain_immediate() -> int:
	if group_visual == null:
		return 0
	var presented: int = 0
	var guard: int = 0
	while guard < 1000:
		guard += 1
		if group_visual.has_active_inter_hole_transition():
			var transition: Dictionary = group_visual.transition_snapshot()
			var duration: float = maxf(float(transition.get("duration_seconds", 0.0)), 0.001)
			var elapsed: float = maxf(float(transition.get("elapsed_seconds", 0.0)), 0.0)
			group_visual.advance_inter_hole_transition(maxf(duration - elapsed, 0.001))
		if has_active_flight():
			var active_members: Array = group_visual.active_member_shots.keys()
			for member_index_value in active_members:
				var member_index: int = int(member_index_value)
				if member_index >= 0 and member_index < group_visual.member_ball_visuals.size():
					var ball_visual = group_visual.member_ball_visuals[member_index]
					if ball_visual != null and ball_visual.is_flying:
						ball_visual.set_flight_progress(1.0)
			complete_finished_flights()
		if has_active_tee_dispersion():
			var duration: float = maxf(float(tee_dispersion.get("duration_seconds", tee_dispersion_duration_seconds)), 0.001)
			var elapsed: float = maxf(float(tee_dispersion.get("elapsed_seconds", 0.0)), 0.0)
			advance_tee_dispersion(maxf(duration - elapsed, 0.001))
		if is_busy():
			continue
		if queued_events.is_empty():
			break
		if not present_next(false).is_empty():
			presented += 1
		else:
			break
	return presented


func snapshot() -> Dictionary:
	return {
		"group_id": group_id,
		"hole_number": hole_number,
		"queued_event_count": queued_events.size(),
		"presented_event_count": presented_events.size(),
		"active_flight": has_active_flight(),
		"tee_dispersion": tee_dispersion.duplicate(true),
		"next_event": next_event(),
		"presented_events": presented_events.duplicate(true)
	}


func clear_playback() -> void:
	queued_events.clear()
	presented_events.clear()
	tee_rest_positions.clear()
	tee_destinations.clear()
	tee_dispersion.clear()
	group_visual = null
	group_id = ""
	hole_number = 0


func _begin_member_visual(member_index: int, world_shot: Dictionary, animate: bool) -> bool:
	if group_visual == null or world_shot.is_empty():
		return false
	if member_index < 0 or member_index >= group_visual.member_visuals.size() or member_index >= group_visual.member_ball_visuals.size():
		return false
	if group_visual.active_member_shots.has(member_index):
		return false
	var golfer_visual = group_visual.member_visuals[member_index]
	var ball_visual = group_visual.member_ball_visuals[member_index]
	ball_visual.visible = true
	golfer_visual.place_at_ball(world_shot.get("start_position", golfer_visual.course_position))
	if not golfer_visual.observe_shot_result(world_shot):
		return false
	if not ball_visual.present_shot(world_shot, animate):
		return false
	group_visual.active_member_shots[member_index] = {
		"shot_index": int(group_visual.presented_shot_counts.get(member_index, 0)),
		"shot": world_shot.duplicate(true),
		"animate": animate
	}
	return true


func _complete_member_visual(member_index: int) -> bool:
	if group_visual == null or not group_visual.active_member_shots.has(member_index):
		return false
	if member_index < 0 or member_index >= group_visual.member_visuals.size() or member_index >= group_visual.member_ball_visuals.size():
		return false
	var active: Dictionary = group_visual.active_member_shots.get(member_index, {})
	var shot: Dictionary = active.get("shot", {})
	var ball_visual = group_visual.member_ball_visuals[member_index]
	if ball_visual.is_flying:
		ball_visual.set_flight_progress(1.0)
	if ball_visual.has_relief:
		ball_visual.apply_simulation_relief()
	group_visual.member_visuals[member_index].move_to_resolved_ball(shot)
	group_visual.active_member_shots.erase(member_index)
	group_visual.presented_shot_counts[member_index] = int(group_visual.presented_shot_counts.get(member_index, 0)) + 1

	if int(shot.get("shot_number", 0)) == 1:
		var destination: Vector3 = shot.get("landing_position", Vector3.ZERO)
		if str(shot.get("outcome", "")).to_upper() == "WATER" and shot.has("relief_position"):
			destination = shot.get("relief_position", destination)
		tee_destinations[member_index] = destination
		if member_index < tee_rest_positions.size() and typeof(tee_rest_positions[member_index]) == TYPE_VECTOR3:
			group_visual.member_visuals[member_index].place_at_ball(tee_rest_positions[member_index])
		if tee_destinations.size() == group_visual.member_visuals.size():
			_begin_tee_dispersion()
	return true


func _begin_tee_dispersion() -> void:
	if group_visual == null or tee_destinations.size() != group_visual.member_visuals.size():
		return
	var starts: Array = group_visual.member_world_positions()
	var destinations: Array = []
	for member_index in range(group_visual.member_visuals.size()):
		if not tee_destinations.has(member_index) or typeof(tee_destinations[member_index]) != TYPE_VECTOR3:
			return
		destinations.append(tee_destinations[member_index])
	tee_dispersion = {
		"movement_kind": "TEE_DISPERSION",
		"hole_number": hole_number,
		"elapsed_seconds": 0.0,
		"duration_seconds": maxf(tee_dispersion_duration_seconds, 0.001),
		"start_positions": starts.duplicate(),
		"destination_positions": destinations.duplicate()
	}


func _world_shot(shot: Dictionary) -> Dictionary:
	var result: Dictionary = shot.duplicate(true)
	for key in ["start_position", "target_position", "landing_position", "relief_position", "water_entry_point"]:
		if result.has(key) and typeof(result[key]) == TYPE_VECTOR3:
			result[key] = group_visual.course_world.world_position(hole_number, result[key])
	return result
