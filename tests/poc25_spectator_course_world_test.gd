extends SceneTree

const CourseDefinition = preload("res://simulation/course_definition.gd")
const SpectatorCourseWorld = preload("res://scenes/spectator_course_world.gd")


func _init() -> void:
	var course = CourseDefinition.load_json("res://data/courses/poc12_proving_course.json")
	assert(course != null)
	assert(course.hole_count() == 3)

	var original_tees: Dictionary = {}
	for hole_number in range(1, course.hole_count() + 1):
		original_tees[hole_number] = course.hole_by_number(hole_number).tee_position("default")

	var world = SpectatorCourseWorld.new()
	get_root().add_child(world)
	assert(world.configure(course, "default", 40.0))
	assert(world.rendered_hole_numbers() == [1, 2, 3])

	for hole_number in range(1, 4):
		var renderer = world.renderer_for_hole(hole_number)
		assert(renderer != null)
		assert(renderer.rendered_regions.size() > 0)
		var hole = course.hole_by_number(hole_number)
		var tee: Vector3 = hole.tee_position("default")
		var pin: Vector3 = hole.pin_position
		var world_tee: Vector3 = world.world_position(hole_number, tee)
		var world_pin: Vector3 = world.world_position(hole_number, pin)
		assert(is_equal_approx(tee.distance_to(pin), world_tee.distance_to(world_pin)))
		assert(world.course_position(hole_number, world_tee).distance_to(tee) < 0.001)
		assert(hole.tee_position("default").distance_to(original_tees[hole_number]) < 0.001)

	for first in range(1, 4):
		for second in range(first + 1, 4):
			assert(not world.layout.world_bounds(first).intersects(world.layout.world_bounds(second)))

	var snapshot: Dictionary = world.snapshot()
	assert(int(snapshot.get("hole_count", 0)) == 3)
	var offsets: Array = []
	for hole_value in snapshot.get("holes", []):
		var hole_snapshot: Dictionary = hole_value
		offsets.append(hole_snapshot.get("offset", Vector3.ZERO))
	assert(offsets[0] != offsets[1] and offsets[1] != offsets[2])

	print("POC25_WORLD_SUMMARY holes=%d offsets=%s" % [int(snapshot.get("hole_count", 0)), str(offsets)])
	print("POC-25A SHARED THREE-HOLE SPECTATOR WORLD PASSED")
	world.queue_free()
	quit(0)
