extends SceneTree

const DevelopmentPotential = preload("res://simulation/development_potential.gd")

var failures := 0

func _init() -> void:
	_test_resistance_increases_toward_potential()
	_test_potential_is_soft_not_hard()
	_test_potential_is_skill_specific()
	_test_maximum_potential_is_legacy_neutral()

	if failures == 0:
		print("POC-09 DEVELOPMENT POTENTIAL TESTS PASSED")
		quit(0)
	else:
		push_error("POC-09 DEVELOPMENT POTENTIAL TESTS FAILED: %d" % failures)
		quit(1)

func _test_resistance_increases_toward_potential() -> void:
	var model = DevelopmentPotential.new()
	model.initialize(85.0)

	var far_below = model.resistance_for(0, 55.0)
	var near = model.resistance_for(0, 80.0)
	var at_potential = model.resistance_for(0, 85.0)

	_expect(far_below > near, "potential barely constrains development far below the latent level")
	_expect(near > at_potential, "development resistance rises smoothly near potential")
	_expect(abs(at_potential - DevelopmentPotential.AT_POTENTIAL_RESISTANCE) < 0.000001, "configured at-potential resistance is honored")

func _test_potential_is_soft_not_hard() -> void:
	var model = DevelopmentPotential.new()
	model.initialize(75.0)

	var just_above = model.resistance_for(0, 78.0)
	var well_above = model.resistance_for(0, 92.0)

	_expect(just_above > well_above, "continued development becomes harder above latent potential")
	_expect(well_above > 0.0, "latent potential never becomes a hard development cap")
	_expect(well_above >= DevelopmentPotential.MIN_RESISTANCE, "above-potential development preserves the configured positive floor")

func _test_potential_is_skill_specific() -> void:
	var model = DevelopmentPotential.new()
	model.initialize(85.0)
	model.set_potential(0, 72.0)
	model.set_potential(1, 94.0)

	var drive_resistance = model.resistance_for(0, 75.0)
	var approach_resistance = model.resistance_for(1, 75.0)

	_expect(model.potential_for(0) == 72.0, "drive potential can differ from other skills")
	_expect(model.potential_for(1) == 94.0, "approach potential can differ from other skills")
	_expect(approach_resistance > drive_resistance, "same current skill develops more freely when latent potential is higher")

func _test_maximum_potential_is_legacy_neutral() -> void:
	var model = DevelopmentPotential.new()
	model.initialize(DevelopmentPotential.NEUTRAL_POTENTIAL)

	_expect(model.resistance_for(0, 50.0) == 1.0, "maximum potential leaves mid-skill legacy acquisition unchanged")
	_expect(model.resistance_for(0, 85.0) == 1.0, "maximum potential leaves high-skill legacy acquisition unchanged")
	_expect(model.resistance_for(0, 99.5) == 1.0, "maximum potential remains neutral at the model boundary")

func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)
