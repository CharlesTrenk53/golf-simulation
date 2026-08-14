extends RefCounted

# POC-23B / POC-25 / POC-26A / POC-26C: Group Progression Coordinator
# ---------------------------------------------------------------------
# Advances one authoritative GolferGroup through one course hole while preserving
# each golfer's independent AutonomousRound as the source of score/progression.
# POC-25 added tee honors. POC-26A moves tee/away order into a live incremental
# GroupHoleSession while retaining play_current_hole() as the whole-hole
# compatibility facade used by the existing living-course stack.
#
# POC-26C allows begin_session() to designate one normal member as human-controlled.
# The default remains -1, so every pre-existing autonomous caller retains its
# original behavior while mixed participation uses the same GroupHoleSession.

const GroupTeeOrderModel = preload("res://simulation/group_tee_order_model.gd")
const GroupHoleSession = preload("res://simulation/group_hole_session.gd")

var tee_order_model = GroupTeeOrderModel.new()


func begin_session(group, seed_value: int = 1, human_member_index: int = -1):
	var session = GroupHoleSession.new()
	if not session.begin(group, seed_value, human_member_index):
		return null
	return session


func play_current_hole(group, seed_value: int = 1) -> Dictionary:
	var session = begin_session(group, seed_value)
	if session == null:
		return {}

	# Existing autonomous callers still request a fully resolved group hole. They
	# now drive the exact same one-turn-at-a-time authority that player
	# participation pauses between turns. No human member is designated here.
	var safety_turns: int = 0
	while not session.is_complete() and not session.has_failed() and safety_turns < 1000:
		var turn_result: Dictionary = session.play_current_turn()
		if turn_result.is_empty():
			break
		safety_turns += 1

	return session.result()


# Retained as a compatibility/read seam for existing diagnostics. GroupHoleSession
# contains the same calculation and is the live authority during actual play.
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
