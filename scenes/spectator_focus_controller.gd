extends Node

# POC-25G: Spectator Focus / HUD Projection
# -----------------------------------------
# Human-facing read model for the living spectator session. It selects which
# authoritative group the observer is following and projects only information
# that is safe to reveal at the current PHYSICAL course time. The simulation may
# already know a hole's final result before its timed playback has completed; this
# layer deliberately hides those future scores/outcomes until the group has
# physically completed the hole.

var session = null
var population_view = null
var controller = null
var group_ids: Array[String] = []
var selected_index: int = -1


func configure(session_value, population_view_value) -> bool:
	clear_focus()
	if session_value == null or population_view_value == null:
		return false
	if session_value.controller == null or population_view_value.controller != session_value.controller:
		return false
	session = session_value
	population_view = population_view_value
	controller = session_value.controller
	if controller.living_course == null:
		clear_focus()
		return false
	for group in controller.living_course.population.groups:
		if group != null:
			group_ids.append(str(group.group_id))
	if group_ids.is_empty():
		clear_focus()
		return false
	selected_index = 0
	return true


func available_group_ids() -> Array[String]:
	return group_ids.duplicate()


func selected_group_id() -> String:
	if selected_index < 0 or selected_index >= group_ids.size():
		return ""
	return group_ids[selected_index]


func select_group(group_id: String) -> bool:
	var normalized: String = group_id.strip_edges()
	var index: int = group_ids.find(normalized)
	if index < 0:
		return false
	selected_index = index
	return true


func cycle_group(step: int = 1) -> String:
	if group_ids.is_empty():
		return ""
	var normalized_step: int = step % group_ids.size()
	selected_index = (selected_index + normalized_step + group_ids.size()) % group_ids.size()
	return selected_group_id()


func presentation_snapshot() -> Dictionary:
	var group_id: String = selected_group_id()
	if group_id.is_empty() or controller == null or population_view == null:
		return {}
	var group = controller.living_course.population.group_by_id(group_id)
	var visual = population_view.group_visual(group_id)
	if group == null or visual == null:
		return {}

	var traffic_hole: int = int(controller.traffic.group_hole(group_id))
	var active_event: Dictionary = controller.active_event(group_id)
	var blocked: Dictionary = controller.blocked_transition(group_id)
	var physical_status: String = _physical_status(group, traffic_hole, active_event, blocked)
	var display_hole: int = _display_hole_number(group, traffic_hole, physical_status)
	var physically_completed: int = _physically_completed_holes(traffic_hole, physical_status)
	var playback = session.playback_for_group(group_id)
	var playback_snapshot: Dictionary = playback.snapshot() if playback != null else {}
	var shot: Dictionary = _shot_snapshot(group, visual, playback)
	var members: Array = _member_score_snapshots(group, physically_completed, playback_snapshot)
	var camera_target: Vector3 = _camera_focus_target(visual, shot)

	return {
		"group_id": group_id,
		"available_group_ids": available_group_ids(),
		"status": physical_status,
		"hole_number": display_hole,
		"traffic_hole_number": traffic_hole,
		"physically_completed_holes": physically_completed,
		"waiting_for_group_ahead": not blocked.is_empty(),
		"active_playback": playback != null,
		"members": members,
		"shot": shot,
		"camera_target": camera_target
	}


func clear_focus() -> void:
	session = null
	population_view = null
	controller = null
	group_ids.clear()
	selected_index = -1


func _physical_status(group, traffic_hole: int, active_event: Dictionary, blocked: Dictionary) -> String:
	if traffic_hole > 0:
		if not active_event.is_empty():
			return "PLAYING"
		return "WAITING"
	if not blocked.is_empty():
		return "WAITING"
	if str(group.status) == "FINISHED":
		return "FINISHED"
	return "WAITING"


func _display_hole_number(group, traffic_hole: int, physical_status: String) -> int:
	if traffic_hole > 0:
		return traffic_hole
	if physical_status == "FINISHED" and controller.course != null:
		return controller.course.hole_count()
	return maxi(1, int(group.current_hole_number()))


func _physically_completed_holes(traffic_hole: int, physical_status: String) -> int:
	if physical_status == "FINISHED" and controller.course != null:
		return controller.course.hole_count()
	if traffic_hole > 0:
		return maxi(0, traffic_hole - 1)
	return 0


func _member_score_snapshots(group, completed_holes: int, playback_snapshot: Dictionary) -> Array:
	var members: Array = []
	for index in range(group.golfers.size()):
		var golfer = group.golfers[index]
		var autonomous_round = group.rounds[index] if index < group.rounds.size() else null
		var strokes: int = 0
		var par: int = 0
		if autonomous_round != null and autonomous_round.round_state != null:
			for hole_number in range(1, completed_holes + 1):
				var score: int = autonomous_round.round_state.score_for_hole(hole_number)
				var hole = controller.course.hole_by_number(hole_number) if controller.course != null else null
				if score > 0 and hole != null:
					strokes += score
					par += int(hole.par)
		var current_hole_strokes_seen: int = 0
		for event_value in playback_snapshot.get("presented_events", []):
			if typeof(event_value) == TYPE_DICTIONARY and int(event_value.get("member_index", -1)) == index:
				current_hole_strokes_seen += 1
		members.append({
			"member_index": index,
			"golfer_name": str(golfer.get("golfer_name")) if golfer != null else "Golfer %d" % (index + 1),
			"completed_holes": completed_holes,
			"total_strokes": strokes,
			"par_played": par,
			"score_to_par": strokes - par,
			"score_label": _score_label(strokes - par),
			"current_hole_strokes_seen": current_hole_strokes_seen
		})
	return members


func _shot_snapshot(group, visual, playback) -> Dictionary:
	if visual == null:
		return {"phase": "NONE"}
	var active_indices: Array = visual.active_member_shots.keys()
	active_indices.sort()
	if not active_indices.is_empty():
		var member_index: int = int(active_indices[0])
		var active: Dictionary = visual.active_member_shots.get(member_index, {})
		var shot: Dictionary = active.get("shot", {})
		return _safe_shot_details(group, member_index, int(active.get("shot_index", -1)), shot, "ACTIVE")
	if playback != null:
		var next: Dictionary = playback.next_event()
		if not next.is_empty():
			var member_index: int = int(next.get("member_index", -1))
			var shot_index: int = int(next.get("shot_index", -1))
			var shots: Array = visual.playback_shots(member_index)
			var shot: Dictionary = shots[shot_index] if shot_index >= 0 and shot_index < shots.size() else {}
			return _safe_shot_details(group, member_index, shot_index, shot, "NEXT")
		return {"phase": "BETWEEN_SHOTS"}
	return {"phase": "NONE"}


func _safe_shot_details(group, member_index: int, shot_index: int, shot: Dictionary, phase: String) -> Dictionary:
	var golfer_name: String = ""
	if member_index >= 0 and member_index < group.golfers.size() and group.golfers[member_index] != null:
		golfer_name = str(group.golfers[member_index].get("golfer_name"))
	var option_name: String = str(shot.get("option", ""))
	if option_name.is_empty() and typeof(shot.get("selected_option", null)) == TYPE_DICTIONARY:
		option_name = str(shot.get("selected_option", {}).get("name", ""))
	return {
		"phase": phase,
		"member_index": member_index,
		"golfer_name": golfer_name,
		"shot_index": shot_index,
		"shot_number": int(shot.get("shot_number", shot_index + 1)),
		"club_id": str(shot.get("club_id", "")),
		"club_name": str(shot.get("club_name", shot.get("club_id", ""))),
		"intent": option_name,
		"lie": str(shot.get("surface_before", "")),
		"start_position": shot.get("start_position", Vector3.ZERO)
	}


func _camera_focus_target(visual, shot: Dictionary) -> Vector3:
	var member_index: int = int(shot.get("member_index", -1))
	if member_index >= 0 and member_index < visual.member_visuals.size():
		if str(shot.get("phase", "")) == "ACTIVE" and member_index < visual.member_ball_visuals.size():
			return visual.member_ball_visuals[member_index].course_position
		return visual.member_visuals[member_index].course_position
	var positions: Array = visual.member_world_positions()
	if positions.is_empty():
		return Vector3.ZERO
	var total := Vector3.ZERO
	for position_value in positions:
		if typeof(position_value) == TYPE_VECTOR3:
			total += position_value
	return total / float(positions.size())


func _score_label(score_to_par: int) -> String:
	if score_to_par == 0:
		return "E"
	if score_to_par > 0:
		return "+%d" % score_to_par
	return str(score_to_par)
