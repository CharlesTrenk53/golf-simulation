extends Node

# POC-26E: Participate Spectator Session
# ---------------------------------------
# Bridges the shot-progressive POC-26D living-course authority into the existing
# POC-25 spectator world and group visuals. It consumes LIVE_* events after they
# are authoritative and queues them for presentation. It never predicts or
# resimulates outcomes.

const ParticipateLiveGroupPlayback = preload("res://scenes/participate_live_group_playback.gd")

var controller = null
var course_world = null
var population_view = null
var started: bool = false
var active_playbacks: Dictionary = {}
var completed_playbacks: Array = []
var event_log: Array = []
var pending_next_hole: Dictionary = {}


func configure(controller_value, world_value, population_view_value) -> bool:
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
	return true


func start_session() -> Dictionary:
	if controller == null or started:
		return {}
	var release: Dictionary = controller.release_next_group()
	if release.is_empty() or not bool(release.get("released", false)):
		return {}
	started = true
	_handle_authority_event(release, false)
	var record := {
		"type": "PARTICIPATE_SESSION_START",
		"group_id": str(release.get("group_id", "")),
		"time_seconds": controller.current_time_seconds,
		"release": release.duplicate(true)
	}
	event_log.append(record.duplicate(true))
	return record


func advance_time(delta_seconds: float, animate: bool = false) -> Array:
	if not started or controller == null or delta_seconds < 0.0:
		return []
	# Interactive presentation never allows later authority to visually overtake an
	# already-active ball flight or tee/inter-hole walk. Headless callers can drain
	# everything immediately.
	if animate and presentation_busy():
		return []
	var processed: Array = controller.advance_time(delta_seconds)
	for event_value in processed:
		if typeof(event_value) == TYPE_DICTIONARY:
			_handle_authority_event(event_value, animate)
	if not animate:
		drain_visuals_immediate()
	else:
		_present_next_global(true)
	return processed


func advance_visuals(delta_seconds: float) -> bool:
	if controller == null:
		return false
	var changed: bool = false
	for playback in active_playbacks.values():
		if playback == null:
			continue
		if playback.complete_finished_flights() > 0:
			changed = true
		if playback.has_active_tee_dispersion():
			playback.advance_tee_dispersion(delta_seconds)
			changed = true
	for group_id in active_playbacks.keys():
		var visual = population_view.group_visual(str(group_id)) if population_view != null else null
		if visual != null and visual.has_active_inter_hole_transition():
			visual.advance_inter_hole_transition(delta_seconds)
			changed = true
	_finalize_idle_playbacks()
	# Pending events intentionally keep simulation time paused until presentation
	# catches up, but they must never prevent their own playback. _present_next_global
	# already refuses to start anything while an actual flight/walk is still moving.
	if not _present_next_global(true).is_empty():
		changed = true
	return changed


func drain_visuals_immediate() -> int:
	var presented: int = 0
	var guard: int = 0
	while guard < 10000:
		guard += 1
		var progress: bool = false
		for playback in active_playbacks.values():
			if playback != null:
				var count: int = playback.drain_immediate()
				if count > 0:
					presented += count
					progress = true
		for group_id in active_playbacks.keys():
			var visual = population_view.group_visual(str(group_id)) if population_view != null else null
			if visual != null and visual.has_active_inter_hole_transition():
				var transition: Dictionary = visual.transition_snapshot()
				var duration: float = maxf(float(transition.get("duration_seconds", 0.0)), 0.001)
				var elapsed: float = maxf(float(transition.get("elapsed_seconds", 0.0)), 0.0)
				visual.advance_inter_hole_transition(maxf(duration - elapsed, 0.001))
				progress = true
		_finalize_idle_playbacks()
		var presented_global: Dictionary = _present_next_global(false)
		if not presented_global.is_empty():
			presented += 1
			progress = true
		if not progress:
			break
	return presented


func pending_human_decision(group_id: String) -> Dictionary:
	if controller == null or group_presentation_busy(group_id):
		return {}
	return controller.pending_human_decision(group_id)


func submit_human_choice(group_id: String, candidate_index: int, animate: bool = false) -> Dictionary:
	if controller == null:
		return {"played": false, "rejected": true, "reason": "NO_CONTROLLER"}
	# Only unfinished presentation work for this group blocks its authoritative
	# command. Other groups remain visually alive without erasing or disabling a
	# stable player decision.
	if group_presentation_busy(group_id):
		return {"played": false, "rejected": true, "reason": "GROUP_PRESENTATION_NOT_CAUGHT_UP"}
	var result: Dictionary = controller.submit_human_choice(group_id, candidate_index)
	if not bool(result.get("played", false)):
		return result
	var shot_event: Dictionary = result.get("shot_event", {})
	if not shot_event.is_empty():
		_handle_authority_event(shot_event, animate)
	for event_value in result.get("world_events", []):
		if typeof(event_value) == TYPE_DICTIONARY:
			_handle_authority_event(event_value, animate)
	if not animate:
		drain_visuals_immediate()
	else:
		_present_next_global(true)
	return result


func playback_for_group(group_id: String):
	return active_playbacks.get(group_id.strip_edges(), null)


func group_presentation_busy(group_id: String) -> bool:
	var normalized: String = group_id.strip_edges()
	if normalized.is_empty():
		return false
	var playback = active_playbacks.get(normalized, null)
	if playback != null and (playback.is_busy() or playback.has_pending_events()):
		return true
	if population_view != null:
		var visual = population_view.group_visual(normalized)
		if visual != null and visual.has_active_inter_hole_transition():
			return true
	return false


func presentation_busy() -> bool:
	for playback in active_playbacks.values():
		if playback != null and (playback.is_busy() or playback.has_pending_events()):
			return true
	if population_view != null:
		for visual in population_view.group_visuals.values():
			if visual != null and visual.has_active_inter_hole_transition():
				return true
	return false


func snapshot() -> Dictionary:
	var playbacks: Array = []
	var ids: Array = active_playbacks.keys()
	ids.sort()
	for group_id in ids:
		var playback = active_playbacks[group_id]
		playbacks.append(playback.snapshot() if playback != null else {})
	return {
		"started": started,
		"time_seconds": controller.current_time_seconds if controller != null else 0.0,
		"presentation_busy": presentation_busy(),
		"active_playbacks": playbacks,
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
	pending_next_hole.clear()
	controller = null
	course_world = null
	population_view = null
	started = false


func _handle_authority_event(event: Dictionary, animate: bool) -> void:
	if event.is_empty():
		return
	event_log.append(event.duplicate(true))
	var event_type: String = str(event.get("type", ""))
	var group_id: String = str(event.get("group_id", ""))
	if group_id.is_empty():
		return
	if event_type == "LIVE_TEE_RELEASE" and bool(event.get("released", false)):
		_sync_group(group_id)
		_ensure_playback(group_id, int(event.get("hole_number", 1)))
	elif event_type == "LIVE_SHOT":
		var hole_number: int = int(event.get("hole_number", 0))
		if _ensure_playback(group_id, hole_number):
			var playback = active_playbacks.get(group_id, null)
			if playback != null:
				playback.enqueue_authoritative_shot(event)
				if not animate:
					playback.drain_immediate()
	elif event_type == "LIVE_HOLE_FINISH":
		pending_next_hole[group_id] = int(event.get("next_hole_number", 0))
	elif event_type == "LIVE_INTER_HOLE_TRANSITION" and bool(event.get("entered", false)):
		pending_next_hole[group_id] = int(event.get("to_hole_number", 0))
		if not _playback_has_visual_work(group_id):
			_retire_and_sync_to_next(group_id)
	elif event_type == "LIVE_INTER_HOLE_WAIT":
		_sync_group(group_id)


func _ensure_playback(group_id: String, hole_number: int) -> bool:
	if population_view == null or hole_number <= 0:
		return false
	if active_playbacks.has(group_id):
		var existing = active_playbacks[group_id]
		if existing != null and int(existing.hole_number) == hole_number:
			return true
		if _playback_has_visual_work(group_id):
			return false
		_retire_playback(group_id)
	var visual = population_view.group_visual(group_id)
	if visual == null:
		return false
	var playback = ParticipateLiveGroupPlayback.new()
	playback.name = "ParticipatePlayback_%s_Hole%d" % [group_id, hole_number]
	add_child(playback)
	if not playback.configure(visual, group_id, hole_number):
		remove_child(playback)
		playback.queue_free()
		return false
	active_playbacks[group_id] = playback
	return true


func _present_next_global(animate: bool) -> Dictionary:
	if _any_active_motion():
		return {}
	var selected_group_id: String = ""
	var selected_time: float = INF
	for group_id_value in active_playbacks.keys():
		var group_id: String = str(group_id_value)
		var playback = active_playbacks[group_id]
		if playback == null:
			continue
		var event: Dictionary = playback.next_event()
		if event.is_empty():
			continue
		var event_time: float = float(event.get("time_seconds", INF))
		if event_time < selected_time - 0.0001 or (abs(event_time - selected_time) <= 0.0001 and (selected_group_id.is_empty() or group_id < selected_group_id)):
			selected_time = event_time
			selected_group_id = group_id
	if selected_group_id.is_empty():
		return {}
	var selected = active_playbacks[selected_group_id]
	return selected.present_next(animate) if selected != null else {}


func _any_active_motion() -> bool:
	for playback in active_playbacks.values():
		if playback != null and playback.is_busy():
			return true
	if population_view != null:
		for visual in population_view.group_visuals.values():
			if visual != null and visual.has_active_inter_hole_transition():
				return true
	return false


func _playback_has_visual_work(group_id: String) -> bool:
	if not active_playbacks.has(group_id):
		return false
	var playback = active_playbacks[group_id]
	return playback != null and (playback.is_busy() or playback.has_pending_events())


func _finalize_idle_playbacks() -> void:
	var ids: Array = pending_next_hole.keys().duplicate()
	for group_id_value in ids:
		var group_id: String = str(group_id_value)
		if not _playback_has_visual_work(group_id):
			_retire_and_sync_to_next(group_id)


func _retire_and_sync_to_next(group_id: String) -> void:
	var next_hole: int = int(pending_next_hole.get(group_id, 0))
	_retire_playback(group_id)
	pending_next_hole.erase(group_id)
	_sync_group(group_id)
	if next_hole > 0 and controller != null and int(controller.traffic.group_hole(group_id)) == next_hole:
		_ensure_playback(group_id, next_hole)


func _retire_playback(group_id: String) -> void:
	if not active_playbacks.has(group_id):
		return
	var playback = active_playbacks[group_id]
	if playback != null:
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
