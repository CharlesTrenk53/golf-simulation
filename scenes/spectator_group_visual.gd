extends Node3D

# POC-25B/C: Spectator Group Visual
# ----------------------------------
# Visual-only projection of one authoritative GolferGroup. Group status, hole
# ownership, golfer identity, and tee choice are read from simulation. Waiting
# staging positions and member spacing are presentation details only and never
# feed back into traffic, shot choice, scoring, or golfer state.
#
# POC-25C adds a playback seam for already-resolved group hole histories. The
# visual layer translates authoritative hole-local coordinates into spectator
# world coordinates, but never chooses a shot or recalculates an outcome.

const RuntimeGolferVisual = preload("res://scenes/runtime_golfer_visual.gd")
const RuntimeBallVisual = preload("res://scenes/runtime_ball_visual.gd")

@export var member_spacing_yards: float = 2.25
@export var waiting_backoff_yards: float = 8.0

var group = null
var course_world = null
var traffic = null
var member_visuals: Array = []
var member_ball_visuals: Array = []
var projected_status: String = ""
var projected_hole_number: int = 0
var loaded_playback: Dictionary = {}
var active_member_shots: Dictionary = {}
var presented_shot_counts: Dictionary = {}


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

		var ball = RuntimeBallVisual.new()
		ball.name = "Member%dBall" % (index + 1)
		ball.set_meta("group_id", str(group.group_id))
		ball.set_meta("member_index", index)
		add_child(ball)
		member_ball_visuals.append(ball)

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
		if index < member_ball_visuals.size():
			member_ball_visuals[index].place_at(member_world_position)

	set_meta("projected_status", projected_status)
	set_meta("projected_hole_number", projected_hole_number)
	set_meta("traffic_hole_number", traffic_hole)
	return true


func load_authoritative_hole_result(play_result: Dictionary) -> Dictionary:
	if group == null or course_world == null:
		return {}
	if str(play_result.get("group_id", "")) != str(group.group_id):
		return {}
	var hole_number: int = int(play_result.get("hole_number", 0))
	if hole_number <= 0 or course_world.course.hole_by_number(hole_number) == null:
		return {}
	var member_results = play_result.get("member_results", [])
	if typeof(member_results) != TYPE_ARRAY or member_results.is_empty():
		return {}

	var members: Array = []
	for member_value in member_results:
		if typeof(member_value) != TYPE_DICTIONARY:
			return {}
		var member_result: Dictionary = member_value
		var member_index: int = int(member_result.get("member_index", members.size()))
		if member_index < 0 or member_index >= member_visuals.size():
			return {}
		var history = member_result.get("history", [])
		if typeof(history) != TYPE_ARRAY or history.is_empty():
			return {}
		var world_history: Array = []
		for shot_value in history:
			if typeof(shot_value) != TYPE_DICTIONARY:
				return {}
			var shot: Dictionary = shot_value
			if not shot.has("start_position") or not shot.has("landing_position"):
				return {}
			world_history.append(_world_shot(hole_number, shot))
		members.append({
			"member_index": member_index,
			"golfer_name": str(member_result.get("golfer_name", "")),
			"shots": world_history
		})

	loaded_playback = {
		"group_id": str(group.group_id),
		"hole_number": hole_number,
		"members": members
	}
	active_member_shots.clear()
	presented_shot_counts.clear()
	for member in members:
		presented_shot_counts[int(member.get("member_index", 0))] = 0
	set_meta("loaded_playback_hole_number", hole_number)
	return playback_snapshot()


func playback_shots(member_index: int) -> Array:
	for member_value in loaded_playback.get("members", []):
		var member: Dictionary = member_value
		if int(member.get("member_index", -1)) == member_index:
			return member.get("shots", []).duplicate(true)
	return []


func present_member_shot(member_index: int, shot_index: int, animate: bool = false) -> Dictionary:
	if member_index < 0 or member_index >= member_visuals.size() or member_index >= member_ball_visuals.size():
		return {}
	if active_member_shots.has(member_index):
		return {}
	var shots: Array = playback_shots(member_index)
	if shot_index < 0 or shot_index >= shots.size():
		return {}
	var shot: Dictionary = shots[shot_index]
	var golfer_visual = member_visuals[member_index]
	var ball_visual = member_ball_visuals[member_index]
	golfer_visual.place_at_ball(shot.get("start_position", golfer_visual.course_position))
	if not golfer_visual.observe_shot_result(shot):
		return {}
	if not ball_visual.present_shot(shot, animate):
		return {}
	active_member_shots[member_index] = {
		"shot_index": shot_index,
		"shot": shot.duplicate(true),
		"animate": animate
	}
	if not animate:
		complete_member_shot(member_index)
	return {
		"member_index": member_index,
		"shot_index": shot_index,
		"shot_number": int(shot.get("shot_number", shot_index + 1)),
		"outcome": str(shot.get("outcome", "")),
		"club_id": str(shot.get("club_id", "")),
		"animated": animate,
		"start_position": shot.get("start_position", Vector3.ZERO),
		"landing_position": shot.get("landing_position", Vector3.ZERO)
	}


func complete_member_shot(member_index: int) -> bool:
	if not active_member_shots.has(member_index):
		return false
	if member_index < 0 or member_index >= member_visuals.size() or member_index >= member_ball_visuals.size():
		return false
	var active: Dictionary = active_member_shots[member_index]
	var shot: Dictionary = active.get("shot", {})
	var ball_visual = member_ball_visuals[member_index]
	if ball_visual.is_flying:
		ball_visual.set_flight_progress(1.0)
	if ball_visual.has_relief:
		ball_visual.apply_simulation_relief()
	member_visuals[member_index].move_to_resolved_ball(shot)
	active_member_shots.erase(member_index)
	presented_shot_counts[member_index] = int(presented_shot_counts.get(member_index, 0)) + 1
	return true


func present_all_loaded_shots_immediate() -> int:
	var presented: int = 0
	for member_value in loaded_playback.get("members", []):
		var member: Dictionary = member_value
		var member_index: int = int(member.get("member_index", -1))
		var shots: Array = member.get("shots", [])
		for shot_index in range(shots.size()):
			if not present_member_shot(member_index, shot_index, false).is_empty():
				presented += 1
	return presented


func member_world_positions() -> Array:
	var positions: Array = []
	for visual in member_visuals:
		positions.append(visual.course_position)
	return positions


func member_ball_world_positions() -> Array:
	var positions: Array = []
	for visual in member_ball_visuals:
		positions.append(visual.course_position)
	return positions


func playback_snapshot() -> Dictionary:
	var members: Array = []
	for member_value in loaded_playback.get("members", []):
		var member: Dictionary = member_value
		var member_index: int = int(member.get("member_index", -1))
		members.append({
			"member_index": member_index,
			"golfer_name": str(member.get("golfer_name", "")),
			"shot_count": int(member.get("shots", []).size()),
			"presented_shots": int(presented_shot_counts.get(member_index, 0)),
			"active_shot": active_member_shots.get(member_index, {}).duplicate(true)
		})
	return {
		"group_id": str(loaded_playback.get("group_id", "")),
		"hole_number": int(loaded_playback.get("hole_number", 0)),
		"member_count": members.size(),
		"members": members
	}


func snapshot() -> Dictionary:
	var members: Array = []
	for index in range(member_visuals.size()):
		var visual = member_visuals[index]
		members.append({
			"member_index": index,
			"golfer_name": str(visual.get_meta("golfer_name", "")),
			"world_position": visual.course_position,
			"ball_world_position": member_ball_visuals[index].course_position if index < member_ball_visuals.size() else Vector3.ZERO
		})
	return {
		"group_id": str(group.group_id) if group != null else "",
		"status": projected_status,
		"projected_hole_number": projected_hole_number,
		"traffic_hole_number": int(traffic.group_hole(str(group.group_id))) if group != null and traffic != null else 0,
		"member_count": members.size(),
		"members": members,
		"playback": playback_snapshot()
	}


func clear_visual() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	member_visuals.clear()
	member_ball_visuals.clear()
	loaded_playback.clear()
	active_member_shots.clear()
	presented_shot_counts.clear()
	group = null
	course_world = null
	traffic = null
	projected_status = ""
	projected_hole_number = 0


func _world_shot(hole_number: int, shot: Dictionary) -> Dictionary:
	var world_shot: Dictionary = shot.duplicate(true)
	for key in ["start_position", "target_position", "landing_position", "relief_position"]:
		if world_shot.has(key) and typeof(world_shot[key]) == TYPE_VECTOR3:
			world_shot[key] = course_world.world_position(hole_number, world_shot[key])
	world_shot["spectator_hole_number"] = hole_number
	return world_shot
