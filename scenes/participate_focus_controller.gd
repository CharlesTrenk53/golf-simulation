extends Node

# POC-26E: Participate Focus / HUD Projection
# --------------------------------------------
# Extends the POC-25 spectator read model with a human-decision state. The visual
# remains a spectator view for every ordinary moment. Only when the selected
# group's authoritative human turn is ready does it expose the POC-26B situation
# and human-selectable candidate indexes.

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
	var index: int = group_ids.find(group_id.strip_edges())
	if index < 0:
		return false
	selected_index = index
	return true


func cycle_group(step: int = 1) -> String:
	if group_ids.is_empty():
		return ""
	selected_index = (selected_index + (step % group_ids.size()) + group_ids.size()) % group_ids.size()
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
	var live_snapshot: Dictionary = controller.live_session_snapshot(group_id)
	var blocked: Dictionary = controller.blocked_transitions.get(group_id, {}).duplicate(true)
	var decision: Dictionary = session.pending_human_decision(group_id) if session != null else {}
	var physical_status: String = _physical_status(group, traffic_hole, live_snapshot, blocked)
	var display_hole: int = _display_hole_number(group, traffic_hole, physical_status)
	var completed_holes: int = _physically_completed_holes(group, traffic_hole, physical_status)
	var playback = session.playback_for_group(group_id) if session != null else null
	var playback_snapshot: Dictionary = playback.snapshot() if playback != null else {}
	var shot: Dictionary = _shot_snapshot(group, visual, playback, live_snapshot, decision)
	var members: Array = _member_score_snapshots(group, completed_holes, playback_snapshot)
	var camera_target: Vector3 = _camera_focus_target(visual, shot, decision)
	var choices: Array = _human_choices(decision)
	var mode: String = "PARTICIPATE" if not decision.is_empty() else "OBSERVE"

	return {
		"group_id": group_id,
		"available_group_ids": available_group_ids(),
		"mode": mode,
		"status": physical_status,
		"hole_number": display_hole,
		"traffic_hole_number": traffic_hole,
		"physically_completed_holes": completed_holes,
		"waiting_for_group_ahead": not blocked.is_empty(),
		"active_playback": playback != null,
		"members": members,
		"shot": shot,
		"decision": decision.duplicate(true),
		"decision_id": str(decision.get("decision_id", "")),
		"decision_kind": str(decision.get("decision_kind", "")),
		"situation": decision.get("situation", {}).duplicate(true),
		"choices": choices,
		"camera_target": camera_target
	}


func clear_focus() -> void:
	session = null
	population_view = null
	controller = null
	group_ids.clear()
	selected_index = -1


func _physical_status(group, traffic_hole: int, live_snapshot: Dictionary, blocked: Dictionary) -> String:
	if str(group.status) == "FINISHED":
		return "FINISHED"
	if traffic_hole > 0:
		if not live_snapshot.is_empty():
			if bool(live_snapshot.get("awaiting_human", false)):
				return "DECIDING"
			return "PLAYING"
		return "WAITING"
	if not blocked.is_empty():
		return "WAITING"
	return "WAITING"


func _display_hole_number(group, traffic_hole: int, physical_status: String) -> int:
	if traffic_hole > 0:
		return traffic_hole
	if physical_status == "FINISHED" and controller.course != null:
		return controller.course.hole_count()
	return maxi(1, int(group.current_hole_number()))


func _physically_completed_holes(group, traffic_hole: int, physical_status: String) -> int:
	if physical_status == "FINISHED" and controller.course != null:
		return controller.course.hole_count()
	var completed: int = 0
	if not group.rounds.is_empty() and group.rounds[0] != null and group.rounds[0].round_state != null:
		completed = group.rounds[0].round_state.holes_completed()
	if traffic_hole > 0:
		return mini(completed, maxi(0, traffic_hole - 1))
	return completed


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


func _shot_snapshot(group, visual, playback, live_snapshot: Dictionary, decision: Dictionary) -> Dictionary:
	if visual == null:
		return {"phase": "NONE"}
	var active_indices: Array = visual.active_member_shots.keys()
	active_indices.sort()
	if not active_indices.is_empty():
		var member_index: int = int(active_indices[0])
		var active: Dictionary = visual.active_member_shots.get(member_index, {})
		return _safe_shot_details(group, member_index, active.get("shot", {}), "ACTIVE")
	if playback != null:
		var next: Dictionary = playback.next_event()
		if not next.is_empty():
			return _safe_shot_details(group, int(next.get("member_index", -1)), next.get("shot", {}), "NEXT")
	if not decision.is_empty():
		var turn: Dictionary = live_snapshot.get("current_turn", {})
		return {
			"phase": "AWAITING_DECISION",
			"member_index": int(turn.get("member_index", -1)),
			"golfer_name": str(turn.get("golfer_name", "")),
			"shot_number": int(decision.get("situation", {}).get("shot_number", 0)),
			"lie": str(decision.get("situation", {}).get("surface", "")),
			"remaining_distance_yards": float(decision.get("situation", {}).get("remaining_distance_yards", 0.0))
		}
	var current_turn: Dictionary = live_snapshot.get("current_turn", {})
	if not current_turn.is_empty():
		return {
			"phase": "BETWEEN_SHOTS",
			"member_index": int(current_turn.get("member_index", -1)),
			"golfer_name": str(current_turn.get("golfer_name", "")),
			"shot_number": int(current_turn.get("shot_number", 0))
		}
	return {"phase": "NONE"}


func _safe_shot_details(group, member_index: int, shot: Dictionary, phase: String) -> Dictionary:
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
		"shot_number": int(shot.get("shot_number", 0)),
		"club_id": str(shot.get("club_id", "")),
		"club_name": str(shot.get("club_name", shot.get("club_id", ""))),
		"intent": option_name,
		"lie": str(shot.get("surface_before", "")),
		"choice_source": str(shot.get("choice_source", "")),
		"start_position": shot.get("start_position", Vector3.ZERO)
	}


func _human_choices(decision: Dictionary) -> Array:
	var choices: Array = []
	for choice_value in decision.get("choices", []):
		if typeof(choice_value) != TYPE_DICTIONARY:
			continue
		var choice: Dictionary = choice_value
		if not bool(choice.get("human_selectable", false)):
			continue
		choices.append(choice.duplicate(true))
	return choices


func _camera_focus_target(visual, shot: Dictionary, decision: Dictionary) -> Vector3:
	var member_index: int = int(shot.get("member_index", -1))
	if member_index >= 0 and member_index < visual.member_visuals.size():
		if str(shot.get("phase", "")) == "ACTIVE" and member_index < visual.member_ball_visuals.size():
			return visual.member_ball_visuals[member_index].course_position
		return visual.member_visuals[member_index].course_position
	if not decision.is_empty():
		var situation: Dictionary = decision.get("situation", {})
		var hole_number: int = int(situation.get("hole_number", 0))
		var ball_position = situation.get("ball_position", null)
		if hole_number > 0 and typeof(ball_position) == TYPE_VECTOR3:
			return visual.course_world.world_position(hole_number, ball_position)
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
