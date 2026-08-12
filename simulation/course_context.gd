extends RefCounted

enum Surface {
	TEE,
	FAIRWAY,
	ROUGH,
	BUNKER,
	GREEN,
	WATER
}

var zones: Array = []
var explicit_hole_out_required: bool = false


func add_zone(
	name: String,
	surface: Surface,
	center: Vector3,
	half_size: Vector2
) -> void:
	zones.append({
		"name": name,
		"surface": surface,
		"center": center,
		"half_size": half_size
	})


func surface_at(position: Vector3) -> Surface:
	for i in range(zones.size() - 1, -1, -1):
		var zone: Dictionary = zones[i]
		var center: Vector3 = zone["center"]
		var half_size: Vector2 = zone["half_size"]
		if abs(position.x - center.x) <= half_size.x and abs(position.z - center.z) <= half_size.y:
			return zone["surface"]
	return Surface.ROUGH


func surface_name(surface: Surface) -> String:
	return Surface.keys()[surface]


func lie_quality(surface: Surface) -> float:
	match surface:
		Surface.TEE:
			return 1.00
		Surface.FAIRWAY:
			return 0.95
		Surface.ROUGH:
			return 0.72
		Surface.BUNKER:
			return 0.58
		Surface.GREEN:
			return 1.00
		Surface.WATER:
			return 0.00
	return 0.70


func risk_modifier(surface: Surface) -> float:
	match surface:
		Surface.TEE:
			return 0.0
		Surface.FAIRWAY:
			return 0.0
		Surface.ROUGH:
			return 15.0
		Surface.BUNKER:
			return 28.0
		Surface.GREEN:
			return -5.0
		Surface.WATER:
			return 100.0
	return 10.0
