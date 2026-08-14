extends RefCounted

# POC-26A: Authoritative Incremental Group Hole Session
# -----------------------------------------------------
# Owns live order of play for one GolferGroup on one hole. Tee order is decided
# before any shot is played; after every member has teed off, the golfer farthest
# from the pin plays next. Each turn advances exactly one member's existing
# authoritative AutonomousRound/DataDefinedAutonomousHole state.

const GroupTeeOrderModel = preload("res://simulation/group_tee_order_model.gd")

const STATUS_PLAYING := "PLAYING"
const STATUS_FINISHED := "FINISHED"
const DISTANCE_TIE_EPSILON := 0.001

var tee_order_model = GroupTeeOrderModel.new()
var group = null
var hole_definition = null
var hole_number: int = 0
var seed_value: int = 1
var tee_order: Array = []
var tee_order_source: String = ""
var previous_hole_scores: Array = []
var member_shots_played: Array = []
var member_results: Array = []
var turn_history: Array = []
var failed: bool = false
var failed_member_index: int = -1
var failure_reason: String = ""
var complete: bool = false


func begin(group_value, new_seed_value: int = 1) -> bool:
	if group_value == null or str(group_value.status) != STATUS_PLAYING:
		return false
	if group_value.rounds.is_empty() or group_value.golfers.size() != group_value.rounds.size():
		return false

	var current_hole: int = group_value.current_hole_number()
	if current_hole <= 0:
		return false

	# Preflight every member before creating any live hole state. This preserves
	# the POC-23 guarantee that a malformed group cannot partly start a hole.
	for autonomous_round in group_value.rounds:
		if autonomous_round == null or autonomous_round.round_state == null:
			return false
		if autonomous_round.round_state.complete:
			return false
		if autonomous_round.round_state.current_hole_number() != current_hole:
			return false
		if autonomous_round.has_active_hole():
			return false

	var tee_context: Dictionary = _tee_order_context(group_value, new_seed_value)
	var resolved_tee_order: Array = tee_context.get("tee_order", [])
	if not tee_order_model.is_valid_order(resolved_tee_order, group_value.member_count()):
		return false
	if not group_value.set_tee_order(resolved_tee_order):
		return false

	var resolved_hole = group_value.course.hole_by_number(current_hole) if group_value.course != null else null
	if resolved_hole == null:
		return false

	group = group_value
	hole_definition = resolved_hole
	hole_number = current_hole
	seed_value = new_seed_value
	tee_order = resolved_tee_order.duplicate()
	tee_order_source = str(tee_context.get("source", ""))
	previous_hole_scores = tee_context.get("previous_hole_scores", []).duplicate()
	member_shots_played.clear()
	member_results.clear()
	turn_history.clear()
	failed = false
	failed_member_index = -1
	failure_reason = ""
	complete = false

	for index in range(group.member_count()):
		member_shots_played.append(0)
		member_results.append({})
		var member_seed: int = seed_value + index * 997
		var begun: Dictionary = group.rounds[index].begin_current_hole(group.golfers[index], member_seed)
		if not bool(begun.get("begun", false)):
			failed = true
			failed_member_index = index
			failure_reason = "MEMBER_HOLE_BEGIN_FAILED"
			return false

	return true


func current_turn() -> Dictionary:
	if group == null or hole_definition == null or failed or complete:
		return {}

	# Every member must play a tee shot before away order can take over. A golfer
	# who holes out from the tee still counts as having completed their tee turn.
	for value in tee_order:
		var member_index: int = int(value)
		if member_index < 0 or member_index >= member_shots_played.size():
			continue
		if int(member_shots_played[member_index]) == 0:
			return _turn_dictionary(member_index, "TEE_ORDER")

	var selected_member: int = -1
	var selected_distance: float = -1.0
	for member_index in range(group.member_count()):
		if not _member_is_active(member_index):
			continue
		var autonomous_round = group.rounds[member_index]
		var distance_to_hole: float = autonomous_round.active_hole_state.ball_position.distance_to(hole_definition.pin_position)
		if (
			selected_member < 0
			or distance_to_hole > selected_distance + DISTANCE_TIE_EPSILON
			or (abs(distance_to_hole - selected_distance) <= DISTANCE_TIE_EPSILON and member_index < selected_member)
		):
			selected_member = member_index
			selected_distance = distance_to_hole

	if selected_member < 0:
		return {}
	return _turn_dictionary(selected_member, "AWAY", selected_distance)


func play_current_turn() -> Dictionary:
	var turn: Dictionary = current_turn()
	if turn.is_empty():
		return {}

	var member_index: int = int(turn.get("member_index", -1))
	if member_index < 0 or member_index >= group.member_count():
		return {}
	var golfer = group.golfers[member_index]
	var step_result: Dictionary = group.rounds[member_index].play_current_hole_step(golfer)
	if step_result.is_empty():
		_mark_failed(member_index, "MEMBER_SHOT_STEP_FAILED")
		return {
			"played": false,
			"turn": turn.duplicate(true),
			"failed": true,
			"session_result": result()
		}

	member_shots_played[member_index] = int(member_shots_played[member_index]) + 1
	var shot: Dictionary = step_result.get("shot", {}).duplicate(true)
	turn_history.append({
		"sequence_index": turn_history.size(),
		"member_index": member_index,
		"golfer_name": str(golfer.get("golfer_name")) if golfer != null else "",
		"order_reason": str(turn.get("order_reason", "")),
		"distance_to_hole_yards": float(turn.get("distance_to_hole_yards", -1.0)),
		"shot_number": int(shot.get("shot_number", member_shots_played[member_index])),
		"shot": shot.duplicate(true)
	})

	if bool(step_result.get("hole_ended", false)):
		var final_result: Dictionary = step_result.get("hole_result", {}).duplicate(true)
		final_result["member_index"] = member_index
		final_result["golfer_name"] = str(golfer.get("golfer_name")) if golfer != null else ""
		member_results[member_index] = final_result
		if final_result.is_empty() or not bool(final_result.get("recorded", false)):
			_mark_failed(member_index, "MEMBER_HOLE_NOT_RECORDED")
		elif _all_members_recorded():
			var next_hole: int = group.current_hole_number()
			if next_hole < 0:
				_mark_failed(member_index, "GROUP_ROUND_DESYNCHRONIZED_AFTER_COMPLETION")
			else:
				if next_hole == 0:
					group.status = STATUS_FINISHED
				complete = true

	return {
		"played": true,
		"turn": turn.duplicate(true),
		"shot": shot.duplicate(true),
		"hole_ended": bool(step_result.get("hole_ended", false)),
		"failed": failed,
		"complete": complete,
		"next_turn": current_turn(),
		"session_result": result() if failed or complete else {}
	}


func is_complete() -> bool:
	return complete and not failed


func has_failed() -> bool:
	return failed


func result() -> Dictionary:
	if group == null:
		return {}
	var next_hole: int = group.current_hole_number()
	var response := {
		"group_id": str(group.group_id),
		"hole_number": hole_number,
		"completed": is_complete(),
		"member_results": _resolved_member_results(),
		"tee_order": tee_order.duplicate(),
		"tee_order_source": tee_order_source,
		"previous_hole_scores": previous_hole_scores.duplicate(),
		"status": str(group.status),
		"next_hole_number": next_hole,
		"turn_history": turn_history.duplicate(true)
	}
	if failed:
		response["failed_member_index"] = failed_member_index
		response["failure_reason"] = failure_reason
	return response


func snapshot() -> Dictionary:
	return {
		"group_id": str(group.group_id) if group != null else "",
		"hole_number": hole_number,
		"tee_order": tee_order.duplicate(),
		"tee_order_source": tee_order_source,
		"previous_hole_scores": previous_hole_scores.duplicate(),
		"member_shots_played": member_shots_played.duplicate(),
		"current_turn": current_turn(),
		"turn_history": turn_history.duplicate(true),
		"failed": failed,
		"failed_member_index": failed_member_index,
		"failure_reason": failure_reason,
		"complete": complete
	}


func _turn_dictionary(member_index: int, reason: String, known_distance: float = -1.0) -> Dictionary:
	if member_index < 0 or member_index >= group.member_count():
		return {}
	var autonomous_round = group.rounds[member_index]
	var distance_to_hole: float = known_distance
	if distance_to_hole < 0.0 and autonomous_round != null and autonomous_round.has_active_hole():
		distance_to_hole = autonomous_round.active_hole_state.ball_position.distance_to(hole_definition.pin_position)
	return {
		"group_id": str(group.group_id),
		"hole_number": hole_number,
		"member_index": member_index,
		"golfer_name": str(group.golfers[member_index].get("golfer_name")) if group.golfers[member_index] != null else "",
		"shot_number": int(member_shots_played[member_index]) + 1,
		"order_reason": reason,
		"distance_to_hole_yards": distance_to_hole
	}


func _member_is_active(member_index: int) -> bool:
	if member_index < 0 or member_index >= group.member_count():
		return false
	if typeof(member_results[member_index]) == TYPE_DICTIONARY and not member_results[member_index].is_empty():
		return false
	var autonomous_round = group.rounds[member_index]
	return autonomous_round != null and autonomous_round.has_active_hole()


func _all_members_recorded() -> bool:
	if group == null or member_results.size() != group.member_count():
		return false
	for member_result_value in member_results:
		if typeof(member_result_value) != TYPE_DICTIONARY:
			return false
		var member_result: Dictionary = member_result_value
		if member_result.is_empty() or not bool(member_result.get("recorded", false)):
			return false
	return true


func _resolved_member_results() -> Array:
	var resolved: Array = []
	for member_result_value in member_results:
		if typeof(member_result_value) != TYPE_DICTIONARY:
			continue
		var member_result: Dictionary = member_result_value
		if not member_result.is_empty():
			resolved.append(member_result.duplicate(true))
	return resolved


func _mark_failed(member_index: int, reason: String) -> void:
	failed = true
	failed_member_index = member_index
	failure_reason = reason
	complete = false


func _tee_order_context(group_value, new_seed_value: int) -> Dictionary:
	if group_value == null or group_value.rounds.is_empty():
		return {}
	var first_round = group_value.rounds[0]
	if first_round == null or first_round.round_state == null:
		return {}
	var current_index: int = int(first_round.round_state.current_hole_index)
	if current_index <= 0:
		return {
			"tee_order": tee_order_model.first_tee_order(group_value.member_count(), new_seed_value + 7919),
			"source": "RANDOM_FIRST_TEE",
			"previous_hole_scores": []
		}

	var previous_scores: Array = []
	for autonomous_round in group_value.rounds:
		if autonomous_round == null or autonomous_round.round_state == null:
			return {}
		var scores: Array = autonomous_round.round_state.hole_scores
		if current_index - 1 < 0 or current_index - 1 >= scores.size():
			return {}
		var score: int = int(scores[current_index - 1])
		if score <= 0:
			return {}
		previous_scores.append(score)

	return {
		"tee_order": tee_order_model.honors_order(previous_scores, group_value.current_tee_order()),
		"source": "PREVIOUS_HOLE_HONORS",
		"previous_hole_scores": previous_scores
	}
