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
#
# POC-25 spectator polish adds a presentation-only inter-hole walk. Authority may
# enter the next hole instantly at an event boundary, but the visible golfers
# interpolate from their current positions to the next tee. No simulation state
# or traffic timing is changed by this animation.

const RuntimeGolferVisual = preload("res://scenes/runtime_golfer_visual.gd")
const RuntimeBallVisual = preload("res://scenes/runtime_ball_visual.gd")

@export var member_spacing_yards: float = 2.25
@export var waiting_backoff_yards: float = 8.0
@export var inter_hole_walk_duration_seconds: float = 1.75

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
var inter_hole_transition: Dictionary = {}


func _process(delta: float) -> void:
	if has_active_inter_hole_transition():
		advance_inter_hole_transition(delta)


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

	var previous_hole: int = projected_hole_number
	var previous_positions: Array = member_world_positions()
	projected_status = str(group.status)
	var traffic_hole: int = int(traffic.group_hole(str(group.group_id)))
	var authoritative_hole: int = traffic_hole
	if authoritative_hole <= 0 and projected_status == "WAITING":
		authoritative_hole = 1
	elif authoritative_hole <= 0:
		authoritative_hole = int(group.current_hole_number())

	if authoritative_hole <= 0:
		return false

	# Attaching the next-hole playback performs another authority sync. If a walk
	# to that same hole is already active, preserve the interpolation instead of
	# snapping to the destination formation.
	if has_active_inter_hole_transition() and int(inter_hole_transition.get("to_hole_number", 0)) == authoritative_hole:
		projected_hole_number = authoritative_hole
		_update_projection_meta(traffic_hole)
		return true

	var destinations: Array = _staging_world_positions(authoritative_hole, projected_status, traffic_hole)
	if destinations.size() != member_visuals.size():
		return false

	projected_hole_number = authoritative_hole
	if (
		previous_hole > 0
		and authoritative_hole == previous_hole + 1
		and previous_positions.size() == member_visuals.size()
		and _positions_materially_different(previous_positions, destinations)
	):
		_begin_inter_hole_transition(previous_hole, authoritative_hole, previous_positions, destinations)
	else:
		inter_hole_transition.clear()
		_apply_member_positions(destinations, true)

	_update_projection_meta(traffic_hole)
	return true


func has_active_inter_hole_transition() -> bool:
	return not inter_hole_transition.is_empty()


func advance_inter_hole_transition(delta_seconds: float) -> bool:
	if inter_hole_transition.is_empty():
		return false
	var duration: float = maxf(float(inter_hole_transition.get("duration_seconds", inter_hole_walk_duration_seconds)), 0.001)
	var elapsed: float = float(inter_hole_transition.get("elapsed_seconds", 0.0)) + maxf(delta_seconds, 0.0)
	inter_hole_transition["elapsed_seconds"] = elapsed
	var t: float = clampf(elapsed / duration, 0.0, 1.0)
	var eased: float = t * t * (3.0 - 2.0 * t)
	var starts: Array = inter_hole_transition.get("start_positions", [])
	var destinations: Array = inter_hole_transition.get("destination_positions", [])
	for index in range(mini(member_visuals.size(), mini(starts.size(), destinations.size()))):
		var start_value = starts[index]
		var destination_value = destinations[index]
		if typeof(start_value) != TYPE_VECTOR3 or typeof(destination_value) != TYPE_VECTOR3:
			continue
		member_visuals[index].place_at_ball(start_value.lerp(destination_value, eased))

	if t >= 1.0:
		_apply_member_positions(destinations, true)
		inter_hole_transition.clear()
		set_meta("inter_hole_transition_active", false)
		return false
	return true


func transition_snapshot() -> Dictionary:
	return inter_hole_transition.duplicate(true)


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
	if has_active_inter_hole_transition():
		return {}
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
	ball_visual.visible = true
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
		"inter_hole_transition": transition_snapshot(),
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
	inter_hole_transition.clear()
	group = null
	course_world = null
	traffic = null
	projected_status = ""
	projected_hole_number = 0


func _staging_world_positions(hole_number: int, status: String, traffic_hole: int) -> Array:
	var hole = course_world.course.hole_by_number(hole_number)
	if hole == null:
		return []
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
	if status == "WAITING" and traffic_hole <= 0:
		staging_course_position = tee - forward * waiting_backoff_yards

	var destinations: Array = []
	var center_index: float = float(member_visuals.size() - 1) * 0.5
	for index in range(member_visuals.size()):
		var member_course_position: Vector3 = staging_course_position + lateral * ((float(index) - center_index) * member_spacing_yards)
		destinations.append(course_world.world_position(hole_number, member_course_position))
	return destinations


func _begin_inter_hole_transition(from_hole: int, to_hole: int, starts: Array, destinations: Array) -> void:
	inter_hole_transition = {
		"from_hole_number": from_hole,
		"to_hole_number": to_hole,
		"elapsed_seconds": 0.0,
		"duration_seconds": maxf(inter_hole_walk_duration_seconds, 0.001),
		"start_positions": starts.duplicate(true),
		"destination_positions": destinations.duplicate(true)
	}
	for index in range(member_visuals.size()):
		if index < starts.size() and typeof(starts[index]) == TYPE_VECTOR3:
			member_visuals[index].place_at_ball(starts[index])
		if index < member_ball_visuals.size():
			member_ball_visuals[index].visible = false
	set_meta("inter_hole_transition_active", true)
	set_meta("inter_hole_transition_from_hole", from_hole)
	set_meta("inter_hole_transition_to_hole", to_hole)


func _apply_member_positions(destinations: Array, show_balls: bool) -> void:
	for index in range(mini(member_visuals.size(), destinations.size())):
		var destination_value = destinations[index]
		if typeof(destination_value) != TYPE_VECTOR3:
			continue
		member_visuals[index].place_at_ball(destination_value)
		if index < member_ball_visuals.size():
			member_ball_visuals[index].place_at(destination_value)
			member_ball_visuals[index].visible = show_balls


func _positions_materially_different(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for index in range(a.size()):
		if typeof(a[index]) == TYPE_VECTOR3 and typeof(b[index]) == TYPE_VECTOR3:
			if a[index].distance_to(b[index]) > 0.5:
				return true
	return false


func _update_projection_meta(traffic_hole: int) -> void:
	for visual in member_visuals:
		visual.set_meta("projected_status", projected_status)
		visual.set_meta("projected_hole_number", projected_hole_number)
		visual.set_meta("traffic_hole_number", traffic_hole)
	set_meta("projected_status", projected_status)
	set_meta("projected_hole_number", projected_hole_number)
	set_meta("traffic_hole_number", traffic_hole)


func _world_shot(hole_number: int, shot: Dictionary) -> Dictionary:
	var world_shot: Dictionary = shot.duplicate(true)
	for key in ["start_position", "target_position", "landing_position", "relief_position"]:
		if world_shot.has(key) and typeof(world_shot[key]) == TYPE_VECTOR3:
			world_shot[key] = course_world.world_position(hole_number, world_shot[key])
	world_shot["spectator_hole_number"] = hole_number
	return world_shot
