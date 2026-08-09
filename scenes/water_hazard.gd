extends MeshInstance3D

const GolfBag = preload("res://simulation/golf_bag.gd")

@export_range(0.0, 100.0, 1.0) var base_hazard_risk: float = 40.0
@export_range(0.0, 100.0, 1.0) var required_carry: float = 45.0

var bag = GolfBag.new()

func calculate_hazard_risk(golfer: Node) -> float:
	var driver = bag.get_club("DRIVER")
	var effective_carry = bag.effective_carry(driver, golfer, "TEE", 1.0)
	var carry_margin = effective_carry - required_carry
	var carry_risk: float

	if carry_margin >= 15.0:
		carry_risk = 10.0
	elif carry_margin >= 5.0:
		carry_risk = 30.0
	elif carry_margin >= 0.0:
		carry_risk = 55.0
	elif carry_margin >= -10.0:
		carry_risk = 80.0
	else:
		carry_risk = 100.0

	var total_risk = clamp(base_hazard_risk * 0.4 + carry_risk * 0.6, 0.0, 100.0)
	print("------ HAZARD ANALYSIS ------")
	print("Effective Driver carry: ", effective_carry)
	print("Physical distance factor: ", golfer.physical_distance_factor(0) if golfer.has_method("physical_distance_factor") else 1.0)
	print("Required carry: ", required_carry)
	print("Carry margin: ", carry_margin)
	print("Carry risk: ", carry_risk)
	print("Calculated hazard risk: ", total_risk)
	return total_risk
