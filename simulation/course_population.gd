extends RefCounted

# POC-23A: Course Population
# --------------------------
# Authoritative course-level registry of golfer groups. This layer owns group
# membership and population state while each golfer's AutonomousRound remains the
# authority for that golfer's score, decisions, and hole progression.

const GolferGroup = preload("res://simulation/golfer_group.gd")

var course = null
var groups: Array = []
var groups_by_id: Dictionary = {}
var golfer_assignments: Dictionary = {}


func configure(course_definition) -> bool:
	if course_definition == null or course_definition.hole_count() <= 0:
		return false
	course = course_definition
	groups.clear()
	groups_by_id.clear()
	golfer_assignments.clear()
	return true


func add_group(group_id: String, golfers: Array, tee_id: String = "default") -> bool:
	if course == null:
		return false
	var normalized_id: String = group_id.strip_edges()
	if normalized_id.is_empty() or groups_by_id.has(normalized_id):
		return false

	for golfer in golfers:
		if golfer == null:
			return false
		if golfer_assignments.has(golfer.get_instance_id()):
			return false

	var group = GolferGroup.new()
	if not group.configure(normalized_id, golfers, course, tee_id):
		return false

	groups.append(group)
	groups_by_id[normalized_id] = group
	for golfer in golfers:
		golfer_assignments[golfer.get_instance_id()] = normalized_id
	return true


func group_by_id(group_id: String):
	return groups_by_id.get(group_id.strip_edges(), null)


func start_group(group_id: String) -> bool:
	var group = group_by_id(group_id)
	if group == null:
		return false
	return group.start()


func group_count() -> int:
	return groups.size()


func golfer_count() -> int:
	return golfer_assignments.size()


func snapshot() -> Dictionary:
	var group_snapshots: Array = []
	var waiting_groups: int = 0
	var playing_groups: int = 0
	var finished_groups: int = 0
	for group in groups:
		group_snapshots.append(group.snapshot())
		match group.status:
			GolferGroup.STATUS_WAITING:
				waiting_groups += 1
			GolferGroup.STATUS_PLAYING:
				playing_groups += 1
			GolferGroup.STATUS_FINISHED:
				finished_groups += 1
	return {
		"course_id": str(course.course_id) if course != null else "",
		"group_count": group_count(),
		"golfer_count": golfer_count(),
		"waiting_groups": waiting_groups,
		"playing_groups": playing_groups,
		"finished_groups": finished_groups,
		"groups": group_snapshots
	}
