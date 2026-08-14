extends RefCounted

# POC-25D: Group Shot Order Model
# --------------------------------
# Derives the real order of play from already-resolved member histories. Among
# golfers who still have a shot remaining, the golfer whose current ball is
# farthest from the pin plays next. Exact distance ties use stable member order
# so tee-box order is deterministic. This model never resimulates a golf shot.

const DISTANCE_TIE_EPSILON := 0.001


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

	var order: Array = []
	while true:
		var selected_member: int = -1
		var selected_distance: float = -1.0
		var selected_start: Vector3 = Vector3.ZERO
		for member_index in range(histories.size()):
			var shot_index: int = int(cursors[member_index])
			var history: Array = histories[member_index]
			if shot_index >= history.size():
				continue
			var shot_value = history[shot_index]
			if typeof(shot_value) != TYPE_DICTIONARY:
				return []
			var shot: Dictionary = shot_value
			var start_position: Vector3 = current_positions[member_index]
			if shot.has("start_position") and typeof(shot.get("start_position")) == TYPE_VECTOR3:
				start_position = shot.get("start_position")
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
