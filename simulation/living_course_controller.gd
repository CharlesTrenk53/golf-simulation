extends RefCounted

# POC-23D: Living Course Controller
# ---------------------------------
# Single authoritative course-level interface for the POC-23 population layer.
# It composes CoursePopulation, deterministic group start sequencing, and group
# hole progression while leaving golfer decisions/scores inside AutonomousRound.
# Traffic, clocks, spacing, and hole occupancy remain deliberately out of scope.

const CoursePopulation = preload("res://simulation/course_population.gd")
const GroupStartSequencer = preload("res://simulation/group_start_sequencer.gd")
const GroupProgressionCoordinator = preload("res://simulation/group_progression_coordinator.gd")

var course = null
var population = null
var start_sequencer = null
var progression_coordinator = null

func configure(course_definition) -> bool:
	if course_definition == null or course_definition.hole_count() <= 0:
		return false
	course = course_definition
	population = CoursePopulation.new()
	if not population.configure(course_definition):
		return false
	start_sequencer = GroupStartSequencer.new()
	if not start_sequencer.configure(population):
		return false
	progression_coordinator = GroupProgressionCoordinator.new()
	return true

func add_group(group_id: String, golfers: Array, tee_id: String = "default") -> bool:
	if population == null:
		return false
	return population.add_group(group_id, golfers, tee_id)

func release_next_group() -> Dictionary:
	if start_sequencer == null:
		return {}
	return start_sequencer.start_next_waiting_group()

func play_group_current_hole(group_id: String, seed_value: int = 1) -> Dictionary:
	if population == null or progression_coordinator == null:
		return {}
	var group = population.group_by_id(group_id)
	if group == null:
		return {}
	return progression_coordinator.play_current_hole(group, seed_value)

func group_snapshot(group_id: String) -> Dictionary:
	if population == null:
		return {}
	var group = population.group_by_id(group_id)
	if group == null:
		return {}
	return group.snapshot()

func snapshot() -> Dictionary:
	return {
		"course_id": str(course.course_id) if course != null else "",
		"population": population.snapshot() if population != null else {},
		"start_sequence": start_sequencer.snapshot() if start_sequencer != null else {}
	}
