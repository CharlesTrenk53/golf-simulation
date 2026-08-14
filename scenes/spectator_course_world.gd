extends Node3D

# POC-25A: Spectator Course World
# --------------------------------
# Renders every authored hole into one shared visual world while preserving the
# authoritative hole-local simulation coordinates. Each hole renderer is only a
# translated visual projection; golf decisions and outcomes stay in simulation.

const SpectatorCourseLayout = preload("res://simulation/spectator_course_layout.gd")
const AuthoredHoleRenderer = preload("res://scenes/authored_hole_renderer.gd")

var course = null
var tee_id: String = "default"
var layout = null
var renderers: Dictionary = {}


func configure(course_definition, selected_tee_id: String = "default", visual_gap_yards: float = 40.0) -> bool:
	clear_world()
	if course_definition == null or course_definition.hole_count() <= 0:
		return false

	course = course_definition
	tee_id = selected_tee_id
	layout = SpectatorCourseLayout.new()
	if not layout.configure(course_definition, visual_gap_yards):
		return false

	for hole_number in range(1, course.hole_count() + 1):
		var hole = course.hole_by_number(hole_number)
		if hole == null:
			clear_world()
			return false
		var renderer = AuthoredHoleRenderer.new()
		renderer.name = "Hole%dRenderer" % hole_number
		renderer.position = layout.hole_offset(hole_number)
		renderer.set_meta("hole_number", hole_number)
		add_child(renderer)
		if not renderer.render_hole(hole, tee_id):
			clear_world()
			return false
		renderers[hole_number] = renderer
	return true


func world_position(hole_number: int, course_position: Vector3) -> Vector3:
	if layout == null:
		return course_position
	return layout.world_position(hole_number, course_position)


func course_position(hole_number: int, spectator_position: Vector3) -> Vector3:
	if layout == null:
		return spectator_position
	return layout.course_position(hole_number, spectator_position)


func renderer_for_hole(hole_number: int):
	return renderers.get(hole_number, null)


func rendered_hole_numbers() -> Array:
	var numbers: Array = renderers.keys()
	numbers.sort()
	return numbers


func snapshot() -> Dictionary:
	var holes: Array = []
	for hole_number in rendered_hole_numbers():
		var renderer = renderers[hole_number]
		holes.append({
			"hole_number": int(hole_number),
			"offset": layout.hole_offset(int(hole_number)) if layout != null else Vector3.ZERO,
			"world_bounds": layout.world_bounds(int(hole_number)) if layout != null else Rect2(),
			"rendered_regions": renderer.rendered_regions.size() if renderer != null else 0
		})
	return {
		"course_id": str(course.course_id) if course != null else "",
		"tee_id": tee_id,
		"hole_count": holes.size(),
		"holes": holes,
		"layout": layout.snapshot() if layout != null else {}
	}


func clear_world() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	renderers.clear()
	layout = null
	course = null
