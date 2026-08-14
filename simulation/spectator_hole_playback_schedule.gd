extends RefCounted

# POC-25D: Spectator Hole Playback Schedule
# ------------------------------------------
# Converts an already-resolved POC-24 hole event into visual shot timestamps.
# The schedule consumes the same farthest-from-hole clearance sequence used by
# traffic spacing, so spectator order and traffic authority share one model.

const SameHoleSpacingModel = preload("res://simulation/same_hole_spacing_model.gd")
const GroupShotOrderModel = preload("res://simulation/group_shot_order_model.gd")

var spacing_model = SameHoleSpacingModel.new()
var shot_order_model = GroupShotOrderModel.new()


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

	var order: Array = shot_order_model.build_order(play_result, hole_definition, tee_id)
	var timeline: Array = spacing_model.build_clearance_timeline(play_result, hole_definition, tee_id)
	if order.is_empty() or timeline.is_empty() or order.size() != timeline.size():
		return {}

	var events: Array = []
	for sequence_index in range(order.size()):
		var ordered: Dictionary = order[sequence_index]
		var milestone: Dictionary = timeline[sequence_index]
		var elapsed: float = float(milestone.get("elapsed_seconds", 0.0))
		events.append({
			"sequence_index": sequence_index,
			"member_index": int(ordered.get("member_index", -1)),
			"shot_index": int(ordered.get("shot_index", -1)),
			"shot_number": int(ordered.get("shot_number", 0)),
			"shot_wave": int(milestone.get("shot_wave", 0)),
			"distance_to_hole_yards": float(ordered.get("distance_to_hole_yards", 0.0)),
			"outcome": str(ordered.get("outcome", "")),
			"club_id": str(ordered.get("club_id", "")),
			"elapsed_seconds": elapsed,
			"time_seconds": min(finish_time, start_time + elapsed),
			"clearance_yards": float(milestone.get("clearance_yards", 0.0)),
			"clearance_time_seconds": min(finish_time, start_time + elapsed)
		})

	return {
		"group_id": str(play_result.get("group_id", active_event.get("group_id", ""))),
		"hole_number": int(play_result.get("hole_number", active_event.get("hole_number", 0))),
		"start_time_seconds": start_time,
		"finish_time_seconds": finish_time,
		"event_count": events.size(),
		"events": events,
		"clearance_timeline": timeline.duplicate(true)
	}
