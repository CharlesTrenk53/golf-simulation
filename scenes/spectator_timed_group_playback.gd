extends Node

# POC-25D/E/H: Timed Spectator Group Playback
# --------------------------------------------
# Drives one SpectatorGroupVisual from the authoritative POC-24 event clock.
# It consumes a deterministic visual schedule built from resolved shot histories
# and POC-24 pace milestones; it never advances or mutates simulation state.
# POC-25E refreshes the projected group state before attaching a newly-started
# playback so hole-clear releases cannot leave the visible status one cycle stale.
# POC-25H adds an interactive seam that retires a shot only after the visual ball
# has naturally finished its flight; this lets a launchable spectator scene pause
# presentation time during animation without forcing the ball to its landing.
#
# Spectator polish keeps the group together through the tee sequence. Tee-shot
# balls resolve normally, but golfers remain at the tee until every member has
# played. The group then disperses together toward the authoritative first-shot
# resolved positions. This is presentation only; shot order and outcomes remain
# unchanged.

const SpectatorHolePlaybackSchedule = preload("res://simulation/spectator_hole_playback_schedule.gd")

@export var tee_dispersion_duration_seconds: float = 2.25

var group_visual = null
var schedule_builder = SpectatorHolePlaybackSchedule.new()
var schedule: Dictionary = {}
var next_event_index: int = 0
var current_time_seconds: float = 0.0
var presented_events: Array = []
var tee_rest_positions: Array = []
var tee_destinations: Dictionary = {}
var tee_dispersion: Dictionary = {}


func _process(delta: float) -> void:
	if has_active_tee_dispersion():
		advance_tee_dispersion(delta)


func configure(group_visual_value, active_event: Dictionary, hole_definition, tee_id: String = "default") -> bool:
	clear_playback()
	if group_visual_value == null or active_event.is_empty() or hole_definition == null:
		return false
	group_visual = group_visual_value
	if not group_visual.sync_from_authority():
		clear_playback()
		return false
	var play_result: Dictionary = active_event.get("play_result", {})
	if group_visual.load_authoritative_hole_result(play_result).is_empty():
		clear_playback()
		return false
	schedule = schedule_builder.build(active_event, hole_definition, tee_id)
	if schedule.is_empty() or int(schedule.get("event_count", 0)) <= 0:
		clear_playback()
		return false
	current_time_seconds = float(schedule.get("start_time_seconds", 0.0))
	tee_rest_positions = group_visual.member_world_positions()
	return tee_rest_positions.size() == group_visual.member_visuals.size()


func advance_to(simulation_time_seconds: float, animate: bool = false) -> Array:
	if group_visual == null or schedule.is_empty():
		return []
	if simulation_time_seconds < current_time_seconds:
		return []
	if animate and has_active_tee_dispersion():
		return []
	current_time_seconds = simulation_time_seconds
	var emitted: Array = []
	var events: Array = schedule.get("events", [])
	while next_event_index < events.size():
		var scheduled: Dictionary = events[next_event_index]
		if float(scheduled.get("time_seconds", INF)) > current_time_seconds:
			break
		var presented: Dictionary = group_visual.present_member_shot(
			int(scheduled.get("member_index", -1)),
			int(scheduled.get("shot_index", -1)),
			animate
		)
		if presented.is_empty():
			break
		var event_snapshot: Dictionary = scheduled.duplicate(true)
		event_snapshot["presented"] = presented.duplicate(true)
		emitted.append(event_snapshot)
		presented_events.append(event_snapshot)
		next_event_index += 1
		if animate:
			# Interactive playback waits for the visible action to complete before a
			# later shot can begin. Headless tests use immediate completion so
			# arbitrary clock jumps can consume every due event.
			break
	return emitted


func complete_active_flights() -> int:
	if group_visual == null:
		return 0
	var completed: int = 0
	var active_members: Array = group_visual.active_member_shots.keys()
	active_members.sort()
	for member_index in active_members:
		if _complete_member_visual(int(member_index)):
			completed += 1
	return completed


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
		var start_value = starts[index]
		var destination_value = destinations[index]
		if typeof(start_value) != TYPE_VECTOR3 or typeof(destination_value) != TYPE_VECTOR3:
			continue
		group_visual.member_visuals[index].place_at_ball(start_value.lerp(destination_value, eased))

	if t >= 1.0:
		for index in range(mini(group_visual.member_visuals.size(), destinations.size())):
			if typeof(destinations[index]) == TYPE_VECTOR3:
				group_visual.member_visuals[index].place_at_ball(destinations[index])
		tee_dispersion.clear()
		tee_destinations.clear()
		return false
	return true


func tee_dispersion_snapshot() -> Dictionary:
	return tee_dispersion.duplicate(true)


func is_complete() -> bool:
	return not schedule.is_empty() and next_event_index >= int(schedule.get("event_count", 0))


func next_event() -> Dictionary:
	var events: Array = schedule.get("events", [])
	if next_event_index < 0 or next_event_index >= events.size():
		return {}
	return events[next_event_index].duplicate(true)


func snapshot() -> Dictionary:
	return {
		"group_id": str(schedule.get("group_id", "")),
		"hole_number": int(schedule.get("hole_number", 0)),
		"current_time_seconds": current_time_seconds,
		"next_event_index": next_event_index,
		"event_count": int(schedule.get("event_count", 0)),
		"presented_event_count": presented_events.size(),
		"complete": is_complete(),
		"next_event": next_event(),
		"tee_dispersion": tee_dispersion_snapshot(),
		"presented_events": presented_events.duplicate(true)
	}


func clear_playback() -> void:
	group_visual = null
	schedule.clear()
	next_event_index = 0
	current_time_seconds = 0.0
	presented_events.clear()
	tee_rest_positions.clear()
	tee_destinations.clear()
	tee_dispersion.clear()


func _complete_member_visual(member_index: int) -> bool:
	if group_visual == null or not group_visual.active_member_shots.has(member_index):
		return false
	var active: Dictionary = group_visual.active_member_shots.get(member_index, {}).duplicate(true)
	var shot_index: int = int(active.get("shot_index", -1))
	var shot: Dictionary = active.get("shot", {})
	var animated: bool = bool(active.get("animate", false))
	if not group_visual.complete_member_shot(member_index):
		return false

	# Immediate/headless playback keeps the historical snap behavior so existing
	# deterministic tests can consume a full hole without waiting on animation.
	if not animated or shot_index != 0:
		return true

	var destination: Vector3 = shot.get("landing_position", Vector3.ZERO)
	if str(shot.get("outcome", "")).to_upper() == "WATER" and shot.has("relief_position"):
		destination = shot.get("relief_position", destination)
	tee_destinations[member_index] = destination

	# The ball is already at its authoritative resolved position. Put the golfer
	# back into the tee formation until every member has completed the tee shot.
	if member_index >= 0 and member_index < tee_rest_positions.size() and member_index < group_visual.member_visuals.size():
		var rest_value = tee_rest_positions[member_index]
		if typeof(rest_value) == TYPE_VECTOR3:
			group_visual.member_visuals[member_index].place_at_ball(rest_value)

	if tee_destinations.size() == group_visual.member_visuals.size():
		_begin_tee_dispersion()
	return true


func _begin_tee_dispersion() -> void:
	if group_visual == null or tee_destinations.size() != group_visual.member_visuals.size():
		return
	var starts: Array = group_visual.member_world_positions()
	var destinations: Array = []
	for member_index in range(group_visual.member_visuals.size()):
		if not tee_destinations.has(member_index):
			return
		var destination_value = tee_destinations[member_index]
		if typeof(destination_value) != TYPE_VECTOR3:
			return
		destinations.append(destination_value)
	tee_dispersion = {
		"movement_kind": "TEE_DISPERSION",
		"hole_number": int(schedule.get("hole_number", 0)),
		"elapsed_seconds": 0.0,
		"duration_seconds": maxf(tee_dispersion_duration_seconds, 0.001),
		"start_positions": starts.duplicate(),
		"destination_positions": destinations.duplicate()
	}
