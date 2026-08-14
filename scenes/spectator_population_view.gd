extends Node3D

# POC-25B: Spectator Population View
# ----------------------------------
# Projects the authoritative living-course population into the shared spectator
# world. This node owns only visual children and mirrors group/traffic state.

const SpectatorGroupVisual = preload("res://scenes/spectator_group_visual.gd")

@export var first_tee_waiting_backoff_yards: float = 20.0

var course_world = null
var controller = null
var group_visuals: Dictionary = {}


func configure(world_value, controller_value) -> bool:
	clear_view()
	if world_value == null or controller_value == null:
		return false
	if controller_value.living_course == null or controller_value.traffic == null:
		return false

	course_world = world_value
	controller = controller_value
	for group in controller.living_course.population.groups:
		var visual = SpectatorGroupVisual.new()
		visual.waiting_backoff_yards = maxf(first_tee_waiting_backoff_yards, 0.0)
		add_child(visual)
		if not visual.configure(group, course_world, controller.traffic):
			clear_view()
			return false
		group_visuals[str(group.group_id)] = visual
	return true


func sync_from_authority() -> bool:
	if controller == null:
		return false
	for group_id in group_visuals.keys():
		var visual = group_visuals[group_id]
		if visual == null or not visual.sync_from_authority():
			return false
	return true


func group_visual(group_id: String):
	return group_visuals.get(group_id.strip_edges(), null)


func snapshot() -> Dictionary:
	var groups: Array = []
	var ids: Array = group_visuals.keys()
	ids.sort()
	for group_id in ids:
		var visual = group_visuals[group_id]
		groups.append(visual.snapshot() if visual != null else {})
	return {
		"group_count": groups.size(),
		"groups": groups
	}


func clear_view() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	group_visuals.clear()
	course_world = null
	controller = null
