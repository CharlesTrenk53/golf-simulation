extends RefCounted

# POC-23A: Golfer Group
# Authoritative group identity above golfer-level AutonomousRound state.

const AutonomousRound = preload("res://simulation/autonomous_round.gd")

const STATUS_WAITING := "WAITING"
const STATUS_PLAYING := "PLAYING"
const STATUS_FINISHED := "FINISHED"
const MIN_GROUP_SIZE := 1
const MAX_GROUP_SIZE := 4

var group_id: String = ""
var course = null
var tee_id: String = "default"
var golfers: Array = []
var rounds: Array = []
var status: String = STATUS_WAITING
var tee_order: Array = []


func configure(new_group_id: String, golfer_values: Array, course_definition, selected_tee_id: String = "default") -> bool:
	if new_group_id.strip_edges().is_empty():
		return false
	if course_definition == null or course_definition.hole_count() <= 0:
		return false
	if golfer_values.size() < MIN_GROUP_SIZE or golfer_values.size() > MAX_GROUP_SIZE:
		return false

	var seen_golfers: Dictionary = {}
	for golfer in golfer_values:
		if golfer == null:
			return false
		var golfer_key: int = golfer.get_instance_id()
		if seen_golfers.has(golfer_key):
			return false
		seen_golfers[golfer_key] = true

	group_id = new_group_id.strip_edges()
	course = course_definition
	tee_id = selected_tee_id
	golfers = golfer_values.duplicate()
	rounds.clear()
	tee_order.clear()
	for _golfer in golfers:
		var autonomous_round = AutonomousRound.new(course, tee_id)
		if autonomous_round.round_state == null or autonomous_round.round_state.complete:
			return false
		rounds.append(autonomous_round)

	status = STATUS_WAITING
	return true


func start() -> bool:
	if status != STATUS_WAITING or rounds.is_empty():
		return false
	status = STATUS_PLAYING
	return true


func member_count() -> int:
	return golfers.size()


func contains_golfer(golfer) -> bool:
	if golfer == null:
		return false
	for member in golfers:
		if member == golfer:
			return true
	return false


func set_tee_order(order: Array) -> bool:
	if order.size() != member_count():
		return false
	var seen: Dictionary = {}
	for value in order:
		var member_index: int = int(value)
		if member_index < 0 or member_index >= member_count() or seen.has(member_index):
			return false
		seen[member_index] = true
	tee_order = order.duplicate()
	return true


func current_tee_order() -> Array:
	return tee_order.duplicate()


func current_hole_number() -> int:
	if rounds.is_empty():
		return 0
	var expected_hole: int = -2
	for autonomous_round in rounds:
		if autonomous_round == null or autonomous_round.round_state == null:
			return -1
		var member_hole: int = 0
		if not autonomous_round.round_state.complete:
			member_hole = autonomous_round.round_state.current_hole_number()
		if expected_hole == -2:
			expected_hole = member_hole
		elif member_hole != expected_hole:
			return -1
	return maxi(expected_hole, 0)


func snapshot() -> Dictionary:
	var members: Array = []
	for index in range(golfers.size()):
		var golfer = golfers[index]
		var autonomous_round = rounds[index] if index < rounds.size() else null
		var round_snapshot: Dictionary = autonomous_round.snapshot() if autonomous_round != null else {}
		members.append({
			"member_index": index,
			"golfer_name": str(golfer.get("golfer_name")) if golfer != null else "",
			"current_hole_number": int(round_snapshot.get("current_hole_number", 0)),
			"holes_completed": int(round_snapshot.get("holes_completed", 0)),
			"round_finished": bool(round_snapshot.get("round_finished", false))
		})
	return {
		"group_id": group_id,
		"status": status,
		"tee_id": tee_id,
		"member_count": member_count(),
		"current_hole_number": current_hole_number(),
		"tee_order": current_tee_order(),
		"members": members
	}
