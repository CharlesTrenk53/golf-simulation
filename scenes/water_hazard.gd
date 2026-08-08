extends MeshInstance3D

@export_range(0.0, 100.0, 1.0) var base_hazard_risk: float = 40.0
@export_range(0.0, 100.0, 1.0) var required_carry: float = 45.0


func calculate_hazard_risk(golfer: Node) -> float:
	var carry_margin = golfer.driving_distance - required_carry

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

	var total_risk = (
		base_hazard_risk * 0.4
		+ carry_risk * 0.6
	)

	total_risk = clamp(total_risk, 0.0, 100.0)

	print("------ HAZARD ANALYSIS ------")
	print("Driving distance: ", golfer.driving_distance)
	print("Required carry: ", required_carry)
	print("Carry margin: ", carry_margin)
	print("Carry risk: ", carry_risk)
	print("Calculated hazard risk: ", total_risk)

	return total_risk
