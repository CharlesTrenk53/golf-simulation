extends RefCounted

# POC-23C: Group Start Sequencer
# ------------------------------
# Provides a deterministic first-pass tee-start order for the authoritative
# CoursePopulation. Population insertion order is the queue. This object only
# releases waiting groups one at a time; tee occupancy, spacing, clocks, and
# pace-of-play constraints deliberately remain out of scope for POC-23.

const STATUS_WAITING := "WAITING"

var population = null
var released_group_ids: Array[String] = []


func configure(course_population) -> bool:
	if course_population == null or course_population.course == null:
		return false
	population = course_population
	released_group_ids.clear()
	return true


func waiting_group_ids() -> Array[String]:
	var waiting: Array[String] = []
	if population == null:
		return waiting
	for group in population.groups:
		if group != null and str(group.status) == STATUS_WAITING:
			waiting.append(str(group.group_id))
	return waiting


func next_waiting_group_id() -> String:
	var waiting: Array[String] = waiting_group_ids()
	if waiting.is_empty():
		return ""
	return waiting[0]


func start_next_waiting_group() -> Dictionary:
	if population == null:
		return {}
	var group_id: String = next_waiting_group_id()
	if group_id.is_empty():
		return {}
	if not population.start_group(group_id):
		return {}
	released_group_ids.append(group_id)
	return {
		"group_id": group_id,
		"release_number": released_group_ids.size(),
		"remaining_waiting": waiting_group_ids().size()
	}


func snapshot() -> Dictionary:
	return {
		"released_count": released_group_ids.size(),
		"released_group_ids": released_group_ids.duplicate(),
		"waiting_group_ids": waiting_group_ids(),
		"next_waiting_group_id": next_waiting_group_id()
	}
