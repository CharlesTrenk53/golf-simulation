extends RefCounted

const HoleAuthoringModel = preload("res://simulation/hole_authoring_model.gd")
const CourseAuthoringModel = preload("res://simulation/course_authoring_model.gd")


func build_course():
	var course_author = CourseAuthoringModel.new()
	course_author.configure_identity("poc19_strategic_proving_ground", "POC-19 Strategic Proving Ground")
	var pars := [4, 4, 3, 5, 4, 4, 3, 5, 4, 4, 4, 3, 5, 4, 4, 3, 5, 4]
	var yardages := [425.0, 410.0, 185.0, 545.0, 440.0, 390.0, 165.0, 565.0, 420.0, 435.0, 405.0, 195.0, 535.0, 455.0, 400.0, 175.0, 555.0, 430.0]
	for index in range(18):
		var hole_number := index + 1
		var definition = _build_hole(hole_number, int(pars[index]), float(yardages[index]))
		if definition == null or not course_author.add_hole_definition(definition):
			return null
	return course_author.build_definition()


func strategic_hole_numbers() -> Array:
	return [2, 4, 6, 8, 10, 13, 15, 17, 18]


func water_hole_numbers() -> Array:
	return [2, 6, 10, 15, 18]


func bunker_hole_numbers() -> Array:
	return [4, 8, 13, 17]


func _build_hole(hole_number: int, par: int, yardage: float):
	var author = HoleAuthoringModel.new()
	author.configure_identity("poc19_strategic_proving_ground", hole_number, "Hole %d" % hole_number, par, yardage)
	author.add_tee("back", "Back", Vector3(0, 0, yardage), yardage)
	author.set_pin(Vector3(0, 0, 0))
	author.set_green(_rect(-20, -16, 20, 18))
	author.add_surface_region("tee_%d" % hole_number, "Tee", "TEE", _rect(-10, yardage - 10.0, 10, yardage + 10.0))

	match hole_number:
		2, 6, 10, 15, 18:
			_build_water_choice_hole(author, hole_number, yardage)
		4, 8, 13, 17:
			_build_bunker_bailout_hole(author, hole_number, yardage)
		_:
			_build_neutral_hole(author, hole_number, yardage)

	return author.build_definition()


func _build_neutral_hole(author, hole_number: int, yardage: float) -> void:
	author.add_surface_region("fairway_%d" % hole_number, "Fairway", "FAIRWAY", _rect(-34, 24, 34, yardage - 20.0))


func _build_water_choice_hole(author, hole_number: int, yardage: float) -> void:
	# Central attack corridor advances farther but runs beside water. A left-side
	# bailout fairway gives up position while materially reducing penalty exposure.
	var attack_far := yardage - 175.0
	var attack_near := maxf(205.0, attack_far - 48.0)
	var bailout_near := minf(yardage - 95.0, attack_near + 42.0)
	var bailout_far := minf(yardage - 35.0, bailout_near + 72.0)

	author.add_surface_region("approach_%d" % hole_number, "Approach Fairway", "FAIRWAY", _rect(-34, 24, 34, attack_near))
	author.add_surface_region("attack_%d" % hole_number, "Attack Fairway", "FAIRWAY", _rect(-10, attack_near, 10, attack_far))
	author.add_surface_region("bailout_%d" % hole_number, "Bailout Fairway", "FAIRWAY", PackedVector2Array([
		Vector2(-36, bailout_near), Vector2(-18, bailout_near), Vector2(-18, bailout_far), Vector2(-36, bailout_far)
	]))
	author.add_hazard("water_%d" % hole_number, "Water", "WATER", PackedVector2Array([
		Vector2(10, attack_near), Vector2(58, attack_near), Vector2(58, bailout_far + 8.0), Vector2(10, bailout_far + 8.0)
	]), 1, "lateral")


func _build_bunker_bailout_hole(author, hole_number: int, yardage: float) -> void:
	# The direct corridor is playable but tight. The left bailout is broad enough
	# to be a real alternative while a bunker beside it keeps the choice non-trivial.
	var decision_near := maxf(215.0, yardage - 205.0)
	var decision_far := minf(yardage - 45.0, decision_near + 72.0)

	author.add_surface_region("approach_%d" % hole_number, "Approach Fairway", "FAIRWAY", _rect(-34, 24, 34, decision_near))
	author.add_surface_region("direct_%d" % hole_number, "Direct Fairway", "FAIRWAY", _rect(-11, decision_near, 11, decision_far))
	author.add_surface_region("bailout_%d" % hole_number, "Bailout Fairway", "FAIRWAY", PackedVector2Array([
		Vector2(-38, decision_near + 20.0), Vector2(-18, decision_near + 20.0), Vector2(-18, decision_far + 18.0), Vector2(-38, decision_far + 18.0)
	]))
	author.add_hazard("bunker_%d" % hole_number, "Bailout Bunker", "BUNKER", PackedVector2Array([
		Vector2(-40, decision_near + 16.0), Vector2(-32, decision_near + 16.0), Vector2(-32, decision_far + 22.0), Vector2(-40, decision_far + 22.0)
	]), 1, "standard")


func _rect(left: float, near_z: float, right: float, far_z: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(left, near_z), Vector2(right, near_z), Vector2(right, far_z), Vector2(left, far_z)
	])
