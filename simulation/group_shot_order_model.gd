extends RefCounted

# POC-25D: Group Shot Order Model
# --------------------------------
# Reconstructs authoritative order of play from an already-resolved group hole.
# Tee shots follow the tee_order supplied by GroupProgressionCoordinator: random
# on the opening tee and previous-hole honors thereafter. Once every golfer has
# teed off, the golfer whose current ball is farthest from the pin plays next.
# Exact away-distance ties use stable member order. No shot is resimulated.

const GroupTeeOrderModel = preload("res://simulation/group_tee_order_model.gd")
const DISTANCE_TIE_EPSILON := 0.001

var tee_order_model = GroupTeeOrderModel.new()


func build_order(group_result: Dictionary, hole_definition, tee_id: String = "default") -> Array:
	if group_result.is_empty() or hole_definition == null:
		return []
	var member_results: Array = group_result.get("member_results", [])
	if member_results.is_empty():
		return []

	var histories: Array = []
	var cursors: Array = []
	var current_positions: Array = []
	var tee: Vector3 = hole_definition.tee_position(tee_id)
	for member_value in member_results:
		if typeof(member_value) != TYPE_DICTIONARY:
			return []
		var member: Dictionary = member_value
		var history: Array = member.get("history", [])
		if history.is_empty():
			return []
		histories.append(history)
		cursors.append(0)
		current_positions.append(tee)

	var tee_order: Array = group_result.get("tee_order", [])
	if not tee_order_model.is_valid_order(tee_order, histories.size()):
		tee_order = []
		for index in range(histories.size()):
			tee_order.append(index)

	var order: Array = []
	while true:
		var selected_member: int = _next_tee_member(cursors, histories, tee_order)
		var selected_distance: float = -1.0
		var selected_start: Vector3 = Vector3.ZERO
		var order_reason: String = "TEE_ORDER" if selected_member >= 0 else "AWAY"

		if selected_member >= 0:
			var tee_shot_index: int = int(cursors[selected_member])
			var tee_shot_value = histories[selected_member][tee_shot_index]
			if typeof(tee_shot_value) != TYPE_DICTIONARY:
				return []
			var tee_shot: Dictionary = tee_shot_value
			selected_start = _start_position(tee_shot, current_positions[selected_member])
			selected_distance = selected_start.distance_to(hole_definition.pin_position)
		else:
			for member_index in range(histories.size()):
				var shot_index: int = int(cursors[member_index])
				var history: Array = histories[member_index]
				if shot_index >= history.size():
					continue
				var shot_value = history[shot_index]
				if typeof(shot_value) != TYPE_DICTIONARY:
					return []
				var shot: Dictionary = shot_value
				var start_position: Vector3 = _start_position(shot, current_positions[member_index])
				var distance_to_hole: float = start_position.distance_to(hole_definition.pin_position)
				if (
					selected_member < 0
					or distance_to_hole > selected_distance + DISTANCE_TIE_EPSILON
					or (abs(distance_to_hole - selected_distance) <= DISTANCE_TIE_EPSILON and member_index < selected_member)
				):
					selected_member = member_index
					selected_distance = distance_to_hole
					selected_start = start_position

		if selected_member < 0:
			break

		var selected_shot_index: int = int(cursors[selected_member])
		var selected_shot: Dictionary = histories[selected_member][selected_shot_index]
		var resolved_position: Vector3 = selected_shot.get("landing_position", selected_start)
		if selected_shot.has("relief_position") and typeof(selected_shot.get("relief_position")) == TYPE_VECTOR3:
			resolved_position = selected_shot.get("relief_position")
		current_positions[selected_member] = resolved_position
		order.append({
			"sequence_index": order.size(),
			"member_index": selected_member,
			"shot_index": selected_shot_index,
			"shot_number": int(selected_shot.get("shot_number", selected_shot_index + 1)),
			"order_reason": order_reason,
			"distance_to_hole_yards": selected_distance,
			"start_position": selected_start,
			"landing_position": selected_shot.get("landing_position", selected_start),
			"resolved_position": resolved_position,
			"penalty_strokes": max(0, int(selected_shot.get("penalty_strokes", 0))),
			"outcome": str(selected_shot.get("outcome", "")),
			"club_id": str(selected_shot.get("club_id", "")),
			"shot": selected_shot.duplicate(true)
		})
		cursors[selected_member] = selected_shot_index + 1

	return order


func _next_tee_member(cursors: Array, histories: Array, tee_order: Array) -> int:
	for value in tee_order:
		var member_index: int = int(value)
		if member_index < 0 or member_index >= cursors.size() or member_index >= histories.size():
			continue
		if int(cursors[member_index]) == 0 and not histories[member_index].is_empty():
			return member_index
	return -1


func _start_position(shot: Dictionary, fallback: Vector3) -> Vector3:
	if shot.has("start_position") and typeof(shot.get("start_position")) == TYPE_VECTOR3:
		return shot.get("start_position")
	return fallback
