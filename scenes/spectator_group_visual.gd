extends Node3D

# POC-25B: Spectator Group Visual
# --------------------------------
# Visual-only projection of one authoritative GolferGroup. Group status, hole
# ownership, golfer identity, and tee choice are read from simulation. Waiting
# staging positions and member spacing are presentation details only and never
# feed back into traffic, shot choice, scoring, or golfer state.

const RuntimeGolferVisual = preload("res://scenes/runtime_golfer_visual.gd")

@export var member_spacing_yards: float = 2.25
@export var waiting_backoff_yards: float = 8.0

var group = null
var course_world = null
var traffic = null
var member_visuals: Array = []
var projected_status: String = ""
var projected_hole_number: int = 0


func configure(group_value, world_value, traffic_value) -> bool:
	clear_visual()
	if group_value == null or world_value == null or traffic_value == null:
		return false
	if group_value.golfers.is_empty():
		return false

	group = group_value
	course_world = world_value
	traffic = traffic_value
	name = "Group_%s" % str(group.group_id)
	set_meta("group_id", str(group.group_id))

	for index in range(group.golfers.size()):
		var golfer = group.golfers[index]
		var visual = RuntimeGolferVisual.new()
		visual.name = "Member%d" % (index + 1)
		add_child(visual)
		if not visual.configure_golfer(golfer):
			clear_visual()
			return false
		visual.set_meta("group_id", str(group.group_id))
		visual.set_meta("member_index", index)
		member_visuals.append(visual)

	return sync_from_authority()


func sync_from_authority() -> bool:
	if group == null or course_world == null or traffic == null:
		return false

	projected_status = str(group.status)
	var traffic_hole: int = int(traffic.group_hole(str(group.group_id)))
	projected_hole_number = traffic_hole
	if projected_hole_number <= 0 and projected_status == "WAITING":
		projected_hole_number = 1
	elif projected_hole_number <= 0:
		projected_hole_number = int(group.current_hole_number())

	if projected_hole_number <= 0:
		return false
	var hole = course_world.course.hole_by_number(projected_hole_number)
	if hole == null:
		return false

	var tee: Vector3 = hole.tee_position(str(group.tee_id))
	var pin: Vector3 = hole.pin_position
	var forward: Vector3 = pin - tee
	forward.y = 0.0
	if forward.length() < 0.001:
		forward = Vector3.FORWARD
	else:
		forward = forward.normalized()
	var lateral := Vector3(-forward.z, 0.0, forward.x)
	var staging_course_position: Vector3 = tee
	if projected_status == "WAITING" and traffic_hole <= 0:
		staging_course_position = tee - forward * waiting_backoff_yards

	var center_index: float = float(member_visuals.size() - 1) * 0.5
	for index in range(member_visuals.size()):
		var member_course_position: Vector3 = staging_course_position + lateral * ((float(index) - center_index) * member_spacing_yards)
		var member_world_position: Vector3 = course_world.world_position(projected_hole_number, member_course_position)
		var visual = member_visuals[index]
		visual.place_at_ball(member_world_position)
		visual.set_meta("projected_status", projected_status)
		visual.set_meta("projected_hole_number", projected_hole_number)
		visual.set_meta("traffic_hole_number", traffic_hole)

	set_meta("projected_status", projected_status)
	set_meta("projected_hole_number", projected_hole_number)
	set_meta("traffic_hole_number", traffic_hole)
	return true


func member_world_positions() -> Array:
	var positions: Array = []
	for visual in member_visuals:
		positions.append(visual.course_position)
	return positions


func snapshot() -> Dictionary:
	var members: Array = []
	for index in range(member_visuals.size()):
		var visual = member_visuals[index]
		members.append({
			"member_index": index,
			"golfer_name": str(visual.get_meta("golfer_name", "")),
			"world_position": visual.course_position
		})
	return {
		"group_id": str(group.group_id) if group != null else "",
		"status": projected_status,
		"projected_hole_number": projected_hole_number,
		"traffic_hole_number": int(traffic.group_hole(str(group.group_id))) if group != null and traffic != null else 0,
		"member_count": members.size(),
		"members": members
	}


func clear_visual() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	member_visuals.clear()
	group = null
	course_world = null
	traffic = null
	projected_status = ""
	projected_hole_number = 0
