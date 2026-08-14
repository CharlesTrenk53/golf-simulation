extends Node

# POC-25E: Living Multi-Hole Spectator Session
# ---------------------------------------------
# Orchestrates the already-authoritative POC-24 traffic clock for presentation.
# It releases/starts groups only through SpacingAwareTimedCourseController public
# APIs, attaches POC-25D playback to active hole events, and mirrors resulting
# traffic transitions into the spectator visuals. It never decides a golf shot,
# changes a resolved result, or creates its own traffic authority.

const SpectatorTimedGroupPlayback = preload("res://scenes/spectator_timed_group_playback.gd")

var controller = null
var course_world = null
var population_view = null
var seed_base: int = 26001
var started: bool = false
var active_playbacks: Dictionary = {}
var completed_playbacks: Array = []
var event_log: Array = []


func configure(controller_value, world_value, population_view_value, seed_value: int = 26001) -> bool:
	clear_session()
	if controller_value == null or world_value == null or population_view_value == null:
		return false
	if controller_value.living_course == null or controller_value.traffic == null:
		return false
	if world_value.course == null or population_view_value.controller != controller_value:
		return false
	controller = controller_value
	course_world = world_value
	population_view = population_view_value
	seed_base = seed_value
	return true


func start_session() -> Dictionary:
	if controller == null or started:
		return {}
	var release: Dictionary = controller.release_next_group()
	if release.is_empty() or not bool(release.get("released", false)):
		return {}
	started = true
	_sync_group(str(release.get("group_id", "")))
	var play_starts: Array = _start_all_eligible_groups()
	var record := {
		"type": "SESSION_START",
		"time_seconds": controller.current_time_seconds,
		"release": release.duplicate(true),
		"play_starts": play_starts.duplicate(true)
	}
	event_log.append(record.duplicate(true))
	return record


func advance_time(delta_seconds: float, animate: bool = false) -> Array:
	if not started or controller == null or delta_seconds < 0.0:
		return []
	var target_time: float = controller.current_time_seconds + delta_seconds
	var emitted: Array = []
	var guard: int = 0
	while controller.current_time_seconds < target_time - 0.0001:
		guard += 1
		if guard > 10000:
			push_error("LivingSpectatorSession exceeded event-boundary guard")
			break
		var before: float = controller.current_time_seconds
		var boundary: float = _next_controller_boundary(target_time)
		_advance_playbacks_to(boundary, animate)
		var processed: Array = controller.advance_time(max(0.0, boundary - before))
		for event_value in processed:
			if typeof(event_value) == TYPE_DICTIONARY:
				emitted.append(event_value.duplicate(true))
		_handle_authority_events(processed)
		var play_starts: Array = _start_all_eligible_groups()
		for start_value in play_starts:
			emitted.append(start_value.duplicate(true))

		if boundary >= target_time - 0.0001:
			break
		if controller.current_time_seconds <= before + 0.0001 and processed.is_empty() and play_starts.is_empty():
			push_error("LivingSpectatorSession made no progress at %.3f" % before)
			break

	return emitted


func playback_for_group(group_id: String):
	return active_playbacks.get(group_id.strip_edges(), null)


func snapshot() -> Dictionary:
	var active: Array = []
	var ids: Array = active_playbacks.keys()
	ids.sort()
	for group_id in ids:
		var playback = active_playbacks[group_id]
		active.append(playback.snapshot() if playback != null else {})
	return {
		"started": started,
		"time_seconds": controller.current_time_seconds if controller != null else 0.0,
		"active_playback_count": active.size(),
		"active_playbacks": active,
		"completed_playback_count": completed_playbacks.size(),
		"completed_playbacks": completed_playbacks.duplicate(true),
		"event_log": event_log.duplicate(true),
		"population": population_view.snapshot() if population_view != null else {}
	}


func clear_session() -> void:
	for playback in active_playbacks.values():
		if playback != null and is_instance_valid(playback):
			if playback.get_parent() == self:
				remove_child(playback)
			playback.queue_free()
	active_playbacks.clear()
	completed_playbacks.clear()
	event_log.clear()
	controller = null
	course_world = null
	population_view = null
	started = false


func _next_controller_boundary(target_time: float) -> float:
	var current: float = controller.current_time_seconds
	var boundary: float = target_time
	var release_snapshot: Dictionary = controller.release_scheduler.snapshot()
	for value in release_snapshot.get("pending_releases", []):
		if typeof(value) == TYPE_DICTIONARY:
			boundary = _consider_boundary(boundary, current, float(value.get("release_time_seconds", INF)))
	var transition_snapshot: Dictionary = controller.transition_scheduler.snapshot()
	for value in transition_snapshot.get("pending_transitions", []):
		if typeof(value) == TYPE_DICTIONARY:
			boundary = _consider_boundary(boundary, current, float(value.get("transition_time_seconds", INF)))
	for value in controller.active_hole_events.values():
		if typeof(value) == TYPE_DICTIONARY:
			boundary = _consider_boundary(boundary, current, float(value.get("finish_time_seconds", INF)))
	return boundary


func _consider_boundary(existing: float, current: float, candidate: float) -> float:
	if candidate == INF:
		return existing
	if candidate <= current + 0.0001:
		return current
	return min(existing, candidate)


func _advance_playbacks_to(simulation_time: float, animate: bool) -> void:
	var ids: Array = active_playbacks.keys()
	ids.sort()
	for group_id in ids:
		var playback = active_playbacks[group_id]
		if playback != null:
			playback.advance_to(simulation_time, animate)


func _handle_authority_events(processed: Array) -> void:
	for event_value in processed:
		if typeof(event_value) != TYPE_DICTIONARY:
			continue
		var event: Dictionary = event_value
		event_log.append(event.duplicate(true))
		var event_type: String = str(event.get("type", ""))
		var group_id: String = str(event.get("group_id", ""))
		if event_type == "HOLE_FINISH":
			_retire_playback(group_id)
			_sync_group(group_id)
		elif event_type == "TEE_RELEASE" and bool(event.get("released", false)):
			_sync_group(group_id)
		elif event_type == "INTER_HOLE_TRANSITION" and bool(event.get("entered", false)):
			_sync_group(group_id)


func _start_all_eligible_groups() -> Array:
	var results: Array = []
	if controller == null:
		return results
	for group in controller.living_course.population.groups:
		if group == null:
			continue
		var group_id: String = str(group.group_id)
		if not controller.active_event(group_id).is_empty():
			continue
		if not controller.blocked_transition(group_id).is_empty():
			continue
		var hole_number: int = int(group.current_hole_number())
		if hole_number <= 0 or int(controller.traffic.group_hole(group_id)) != hole_number:
			continue
		var result: Dictionary = controller.start_group_current_hole(group_id, _seed_for(group_id, hole_number))
		if result.is_empty() or not bool(result.get("started", false)):
			continue
		if not _attach_playback(group_id, controller.active_event(group_id)):
			push_error("Unable to attach spectator playback for %s hole %d" % [group_id, hole_number])
			continue
		var record := {
			"type": "PLAY_START",
			"group_id": group_id,
			"hole_number": hole_number,
			"time_seconds": controller.current_time_seconds,
			"finish_time_seconds": float(result.get("finish_time_seconds", controller.current_time_seconds))
		}
		event_log.append(record.duplicate(true))
		results.append(record)
	return results


func _attach_playback(group_id: String, active_event: Dictionary) -> bool:
	if active_event.is_empty() or population_view == null or course_world == null:
		return false
	_retire_playback(group_id, false)
	var group_visual = population_view.group_visual(group_id)
	var hole_number: int = int(active_event.get("hole_number", 0))
	var hole = course_world.course.hole_by_number(hole_number)
	if group_visual == null or hole == null:
		return false
	var playback = SpectatorTimedGroupPlayback.new()
	playback.name = "Playback_%s_Hole%d" % [group_id, hole_number]
	add_child(playback)
	var group = controller.living_course.population.group_by_id(group_id)
	var tee_id: String = str(group.tee_id) if group != null else "default"
	if not playback.configure(group_visual, active_event, hole, tee_id):
		remove_child(playback)
		playback.queue_free()
		return false
	active_playbacks[group_id] = playback
	return true


func _retire_playback(group_id: String, record_snapshot: bool = true) -> void:
	if not active_playbacks.has(group_id):
		return
	var playback = active_playbacks[group_id]
	if playback != null:
		if record_snapshot:
			completed_playbacks.append(playback.snapshot())
		if playback.get_parent() == self:
			remove_child(playback)
		playback.queue_free()
	active_playbacks.erase(group_id)


func _sync_group(group_id: String) -> void:
	if population_view == null:
		return
	var visual = population_view.group_visual(group_id)
	if visual != null:
		visual.sync_from_authority()


func _seed_for(group_id: String, hole_number: int) -> int:
	var group_index: int = 0
	for index in range(controller.living_course.population.groups.size()):
		var candidate = controller.living_course.population.groups[index]
		if candidate != null and str(candidate.group_id) == group_id:
			group_index = index
			break
	return seed_base + group_index * 10000 + hole_number * 101
