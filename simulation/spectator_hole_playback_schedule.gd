extends RefCounted

# POC-25D: Spectator Hole Playback Schedule
# ------------------------------------------
# Converts an already-resolved POC-24 hole event into visual shot timestamps.
# The schedule reuses the same shot-wave clearance milestones that govern
# same-hole traffic spacing. It never changes shot order, outcomes, positions,
# scores, or traffic authority.

const SameHoleSpacingModel = preload("res://simulation/same_hole_spacing_model.gd")

var spacing_model = SameHoleSpacingModel.new()


func build(active_event: Dictionary, hole_definition, tee_id: String = "default") -> Dictionary:
	if active_event.is_empty() or hole_definition == null:
		return {}
	var play_result: Dictionary = active_event.get("play_result", {})
	if play_result.is_empty():
		return {}
	var start_time: float = float(active_event.get("start_time_seconds", 0.0))
	var finish_time: float = float(active_event.get("finish_time_seconds", start_time))
	if finish_time < start_time:
		return {}

	var member_results: Array = play_result.get("member_results", [])
	if member_results.is_empty():
		return {}
	var timeline: Array = spacing_model.build_clearance_timeline(play_result, hole_definition, tee_id)
	if timeline.is_empty():
		return {}

	var histories: Array = []
	var max_waves: int = 0
	for member_value in member_results:
		if typeof(member_value) != TYPE_DICTIONARY:
			return {}
		var member: Dictionary = member_value
		var history: Array = member.get("history", [])
		histories.append(history)
		max_waves = max(max_waves, history.size())

	var events: Array = []
	var previous_wave_elapsed: float = 0.0
	for wave_index in range(min(max_waves, timeline.size())):
		var milestone: Dictionary = timeline[wave_index]
		var wave_elapsed: float = float(milestone.get("elapsed_seconds", previous_wave_elapsed))
		wave_elapsed = max(previous_wave_elapsed, wave_elapsed)
		var wave_entries: Array = []
		for member_index in range(histories.size()):
			var history: Array = histories[member_index]
			if wave_index >= history.size():
				continue
			if typeof(history[wave_index]) != TYPE_DICTIONARY:
				continue
			var shot: Dictionary = history[wave_index]
			wave_entries.append({
				"member_index": member_index,
				"shot_index": wave_index,
				"shot_number": int(shot.get("shot_number", wave_index + 1)),
				"outcome": str(shot.get("outcome", "")),
				"club_id": str(shot.get("club_id", ""))
			})
		if wave_entries.is_empty():
			continue

		var routine_window: float = float(wave_entries.size()) * spacing_model.pace_model.shot_routine_seconds
		var window_start: float = max(previous_wave_elapsed, wave_elapsed - routine_window)
		var available: float = max(0.0, wave_elapsed - window_start)
		for index in range(wave_entries.size()):
			var entry: Dictionary = wave_entries[index]
			var fraction: float = float(index + 1) / float(wave_entries.size())
			var elapsed: float = window_start + available * fraction
			entry["shot_wave"] = wave_index + 1
			entry["elapsed_seconds"] = elapsed
			entry["time_seconds"] = min(finish_time, start_time + elapsed)
			entry["wave_clearance_time_seconds"] = min(finish_time, start_time + wave_elapsed)
			events.append(entry)
		previous_wave_elapsed = wave_elapsed

	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_time: float = float(a.get("time_seconds", 0.0))
		var b_time: float = float(b.get("time_seconds", 0.0))
		if not is_equal_approx(a_time, b_time):
			return a_time < b_time
		return int(a.get("member_index", 0)) < int(b.get("member_index", 0))
	)

	return {
		"group_id": str(play_result.get("group_id", active_event.get("group_id", ""))),
		"hole_number": int(play_result.get("hole_number", active_event.get("hole_number", 0))),
		"start_time_seconds": start_time,
		"finish_time_seconds": finish_time,
		"event_count": events.size(),
		"events": events,
		"clearance_timeline": timeline.duplicate(true)
	}
