extends RefCounted

# POC-23B / POC-25: Group Progression Coordinator
# ------------------------------------------------
# Advances one authoritative GolferGroup through one course hole while preserving
# each golfer's independent AutonomousRound as the source of score/progression.
# POC-25 adds authoritative tee order: seeded random on the opening tee, then
# previous-hole honors with stable tie order. Away play is derived separately
# from the resolved shot histories.

const GroupTeeOrderModel = preload("res://simulation/group_tee_order_model.gd")

const STATUS_PLAYING := "PLAYING"
const STATUS_FINISHED := "FINISHED"

var tee_order_model = GroupTeeOrderModel.new()


func play_current_hole(group, seed_value: int = 1) -> Dictionary:
	if group == null or str(group.status) != STATUS_PLAYING:
		return {}
	if group.rounds.is_empty() or group.golfers.size() != group.rounds.size():
		return {}

	var hole_number: int = group.current_hole_number()
	if hole_number <= 0:
		return {}

	# Preflight the whole group before any golfer round is advanced.
	for autonomous_round in group.rounds:
		if autonomous_round == null or autonomous_round.round_state == null:
			return {}
		if autonomous_round.round_state.complete:
			return {}
		if autonomous_round.round_state.current_hole_number() != hole_number:
			return {}

	var tee_context: Dictionary = _tee_order_context(group, seed_value)
	var tee_order: Array = tee_context.get("tee_order", [])
	if not tee_order_model.is_valid_order(tee_order, group.member_count()):
		return {}
	if not group.set_tee_order(tee_order):
		return {}

	var member_results: Array = []
	for index in range(group.rounds.size()):
		var autonomous_round = group.rounds[index]
		var golfer = group.golfers[index]
		var member_seed: int = seed_value + index * 997
		var result: Dictionary = autonomous_round.play_current_hole(golfer, member_seed)
		var member_result: Dictionary = result.duplicate(true)
		member_result["member_index"] = index
		member_result["golfer_name"] = str(golfer.get("golfer_name")) if golfer != null else ""
		member_results.append(member_result)
		if result.is_empty() or not bool(result.get("recorded", false)):
			return {
				"group_id": str(group.group_id),
				"hole_number": hole_number,
				"completed": false,
				"failed_member_index": index,
				"member_results": member_results,
				"tee_order": tee_order.duplicate(),
				"tee_order_source": str(tee_context.get("source", "")),
				"previous_hole_scores": tee_context.get("previous_hole_scores", []).duplicate(),
				"status": str(group.status),
				"next_hole_number": group.current_hole_number()
			}

	var next_hole: int = group.current_hole_number()
	if next_hole == 0:
		group.status = STATUS_FINISHED

	return {
		"group_id": str(group.group_id),
		"hole_number": hole_number,
		"completed": next_hole >= 0,
		"member_results": member_results,
		"tee_order": tee_order.duplicate(),
		"tee_order_source": str(tee_context.get("source", "")),
		"previous_hole_scores": tee_context.get("previous_hole_scores", []).duplicate(),
		"status": str(group.status),
		"next_hole_number": next_hole
	}


func _tee_order_context(group, seed_value: int) -> Dictionary:
	if group == null or group.rounds.is_empty():
		return {}
	var first_round = group.rounds[0]
	if first_round == null or first_round.round_state == null:
		return {}
	var current_index: int = int(first_round.round_state.current_hole_index)
	if current_index <= 0:
		return {
			"tee_order": tee_order_model.first_tee_order(group.member_count(), seed_value + 7919),
			"source": "RANDOM_FIRST_TEE",
			"previous_hole_scores": []
		}

	var previous_scores: Array = []
	for autonomous_round in group.rounds:
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
		"tee_order": tee_order_model.honors_order(previous_scores, group.current_tee_order()),
		"source": "PREVIOUS_HOLE_HONORS",
		"previous_hole_scores": previous_scores
	}
