extends RefCounted

# POC-24G: Concurrent Hole Traffic State
# ---------------------------------------
# Authoritative ordered membership for groups that are simultaneously on the
# same hole. This does not decide whether entry is safe; the spacing scheduler
# owns that policy. It only records the resulting course occupancy.

var course = null
var groups_by_hole: Dictionary = {}
var hole_by_group: Dictionary = {}

func configure(course_definition) -> bool:
	if course_definition == null or course_definition.hole_count() <= 0:
		return false
	course = course_definition
	groups_by_hole.clear()
	hole_by_group.clear()
	for hole_number in range(1, course.hole_count() + 1):
		groups_by_hole[hole_number] = []
	return true

func enter_hole(group_id: String, hole_number: int) -> bool:
	var id := group_id.strip_edges()
	if id.is_empty() or not _valid_hole(hole_number):
		return false
	if hole_by_group.has(id):
		return int(hole_by_group[id]) == hole_number
	var occupants: Array = groups_by_hole[hole_number]
	if id in occupants:
		return false
	occupants.append(id)
	groups_by_hole[hole_number] = occupants
	hole_by_group[id] = hole_number
	return true

func leave_hole(group_id: String, hole_number: int) -> bool:
	var id := group_id.strip_edges()
	if id.is_empty() or not _valid_hole(hole_number):
		return false
	if int(hole_by_group.get(id, 0)) != hole_number:
		return false
	var occupants: Array = groups_by_hole[hole_number]
	var index: int = occupants.find(id)
	if index < 0:
		return false
	occupants.remove_at(index)
	groups_by_hole[hole_number] = occupants
	hole_by_group.erase(id)
	return true

func groups_on_hole(hole_number: int) -> Array:
	if not _valid_hole(hole_number):
		return []
	return groups_by_hole[hole_number].duplicate()

func group_ahead(group_id: String) -> String:
	var id := group_id.strip_edges()
	var hole_number: int = int(hole_by_group.get(id, 0))
	if not _valid_hole(hole_number):
		return ""
	var occupants: Array = groups_by_hole[hole_number]
	var index: int = occupants.find(id)
	if index <= 0:
		return ""
	return str(occupants[index - 1])

func group_hole(group_id: String) -> int:
	return int(hole_by_group.get(group_id.strip_edges(), 0))

func snapshot() -> Dictionary:
	var holes: Dictionary = {}
	for hole_number in groups_by_hole.keys():
		holes[hole_number] = groups_by_hole[hole_number].duplicate()
	return {
		"course_id": str(course.course_id) if course != null else "",
		"group_count": hole_by_group.size(),
		"holes": holes
	}

func _valid_hole(hole_number: int) -> bool:
	return course != null and hole_number >= 1 and hole_number <= course.hole_count()
