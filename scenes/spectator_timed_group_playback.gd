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

const SpectatorHolePlaybackSchedule = preload("res://simulation/spectator_hole_playback_schedule.gd")

var group_visual = null
var schedule_builder = SpectatorHolePlaybackSchedule.new()
var schedule: Dictionary = {}
var next_event_index: int = 0
var current_time_seconds: float = 0.0
var presented_events: Array = []


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
	return true


func advance_to(simulation_time_seconds: float, animate: bool = false) -> Array:
	if group_visual == null or schedule.is_empty():
		return []
	if simulation_time_seconds < current_time_seconds:
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
			# Interactive playback waits for the visual flight to complete before a
			# later shot for the same golfer can begin. Headless tests use immediate
			# completion so arbitrary clock jumps can consume every due event.
			break
	return emitted


func complete_active_flights() -> int:
	if group_visual == null:
		return 0
	var completed: int = 0
	var active_members: Array = group_visual.active_member_shots.keys()
	active_members.sort()
	for member_index in active_members:
		if group_visual.complete_member_shot(int(member_index)):
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
			if group_visual.complete_member_shot(member_index):
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
		"presented_events": presented_events.duplicate(true)
	}


func clear_playback() -> void:
	group_visual = null
	schedule.clear()
	next_event_index = 0
	current_time_seconds = 0.0
	presented_events.clear()