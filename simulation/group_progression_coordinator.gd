extends RefCounted

# POC-23B: Group Progression Coordinator
# ---------------------------------------
# Advances one authoritative GolferGroup through one course hole while preserving
# each golfer's independent AutonomousRound as the source of score/progression.
# Course traffic, waiting, and blocking deliberately remain out of scope.

const STATUS_PLAYING := "PLAYING"
const STATUS_FINISHED := "FINISHED"


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
		"status": str(group.status),
		"next_hole_number": next_hole
	}
