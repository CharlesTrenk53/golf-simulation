extends RefCounted

# POC-24A: Course Traffic State
# -----------------------------
# Coarse authoritative traffic state above golfer/group simulation. A hole may
# be occupied by one group at a time; blocked groups wait in deterministic FIFO
# order. This layer does not advance golfer rounds or decide shot outcomes.

const ENTRY_ALLOWED := "ALLOWED"
const ENTRY_WAITING := "WAITING"
const ENTRY_INVALID := "INVALID"

var course = null
var hole_occupants: Dictionary = {}
var group_holes: Dictionary = {}
var waiting_by_hole: Dictionary = {}
var waiting_hole_by_group: Dictionary = {}

func configure(course_definition) -> bool:
	if course_definition == null or course_definition.hole_count() <= 0:
		return false
	course = course_definition
	hole_occupants.clear()
	group_holes.clear()
	waiting_by_hole.clear()
	waiting_hole_by_group.clear()
	for hole_number in range(1, course.hole_count() + 1):
		waiting_by_hole[hole_number] = []
	return true

func request_hole_entry(group_id: String, hole_number: int) -> Dictionary:
	var normalized_id := group_id.strip_edges()
	if course == null or normalized_id.is_empty() or not _valid_hole(hole_number):
		return {"status": ENTRY_INVALID, "allowed": false}

	if group_holes.has(normalized_id):
		var occupied_hole := int(group_holes[normalized_id])
		return {
			"status": ENTRY_ALLOWED if occupied_hole == hole_number else ENTRY_INVALID,
			"allowed": occupied_hole == hole_number,
			"group_id": normalized_id,
			"hole_number": occupied_hole
		}

	if waiting_hole_by_group.has(normalized_id):
		var waiting_hole := int(waiting_hole_by_group[normalized_id])
		return {
			"status": ENTRY_WAITING if waiting_hole == hole_number else ENTRY_INVALID,
			"allowed": false,
			"group_id": normalized_id,
			"hole_number": waiting_hole,
			"occupant_group_id": occupant_for_hole(waiting_hole)
		}

	var occupant := occupant_for_hole(hole_number)
	if occupant.is_empty():
		hole_occupants[hole_number] = normalized_id
		group_holes[normalized_id] = hole_number
		return {
			"status": ENTRY_ALLOWED,
			"allowed": true,
			"group_id": normalized_id,
			"hole_number": hole_number
		}

	var queue: Array = waiting_by_hole.get(hole_number, [])
	queue.append(normalized_id)
	waiting_by_hole[hole_number] = queue
	waiting_hole_by_group[normalized_id] = hole_number
	return {
		"status": ENTRY_WAITING,
		"allowed": false,
		"group_id": normalized_id,
		"hole_number": hole_number,
		"occupant_group_id": occupant,
		"queue_position": queue.size()
	}

func release_hole(group_id: String, hole_number: int) -> bool:
	var normalized_id := group_id.strip_edges()
	if normalized_id.is_empty() or not _valid_hole(hole_number):
		return false
	if occupant_for_hole(hole_number) != normalized_id:
		return false
	hole_occupants.erase(hole_number)
	group_holes.erase(normalized_id)
	return true

func admit_next_waiting(hole_number: int) -> Dictionary:
	if course == null or not _valid_hole(hole_number):
		return {}
	if not occupant_for_hole(hole_number).is_empty():
		return {}
	var queue: Array = waiting_by_hole.get(hole_number, [])
	if queue.is_empty():
		return {}
	var group_id := str(queue.pop_front())
	waiting_by_hole[hole_number] = queue
	waiting_hole_by_group.erase(group_id)
	hole_occupants[hole_number] = group_id
	group_holes[group_id] = hole_number
	return {
		"status": ENTRY_ALLOWED,
		"allowed": true,
		"group_id": group_id,
		"hole_number": hole_number,
		"remaining_waiting": queue.size()
	}

func occupant_for_hole(hole_number: int) -> String:
	return str(hole_occupants.get(hole_number, ""))

func waiting_group_ids(hole_number: int) -> Array:
	if not _valid_hole(hole_number):
		return []
	return waiting_by_hole.get(hole_number, []).duplicate()

func group_hole(group_id: String) -> int:
	return int(group_holes.get(group_id.strip_edges(), 0))

func snapshot() -> Dictionary:
	var holes: Array = []
	if course != null:
		for hole_number in range(1, course.hole_count() + 1):
			holes.append({
				"hole_number": hole_number,
				"occupant_group_id": occupant_for_hole(hole_number),
				"waiting_group_ids": waiting_group_ids(hole_number)
			})
	return {
		"course_id": str(course.course_id) if course != null else "",
		"occupied_hole_count": group_holes.size(),
		"waiting_group_count": waiting_hole_by_group.size(),
		"holes": holes
	}

func _valid_hole(hole_number: int) -> bool:
	return course != null and hole_number >= 1 and hole_number <= course.hole_count()
