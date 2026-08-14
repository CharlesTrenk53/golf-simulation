extends RefCounted

# POC-27A: Eighteen-Hole Proving Course
# --------------------------------------
# Builds a full par-72 course through the existing HoleDefinition and
# CourseDefinition in-memory authoring path introduced in POC-17D. The old
# three-hole proving course remains untouched so all earlier regressions keep
# their exact fixture. This course exists to stress the same living-world
# architecture across a complete round, not to introduce an 18-hole mode.

const HoleDefinition = preload("res://simulation/hole_definition.gd")
const CourseDefinition = preload("res://simulation/course_definition.gd")

const COURSE_ID := "poc27_living_course"
const COURSE_NAME := "POC-27 Living Course"


static func build():
	var holes: Array = []
	for spec_value in _hole_specs():
		var spec: Dictionary = spec_value
		var hole = HoleDefinition.from_dictionary(_hole_dictionary(spec))
		if hole == null:
			return null
		holes.append(hole)
	return CourseDefinition.from_holes(COURSE_ID, COURSE_NAME, holes)


static func _hole_specs() -> Array:
	# A traditional par-72 mix: four par 3s, ten par 4s, four par 5s.
	# Yardages total 7,030 from the back tee and 6,310 from the forward tee.
	return [
		{"number":1, "name":"Opening Statement", "par":4, "yards":410.0, "dogleg":0.0, "pin_x":5.0, "water":false, "ob":"RIGHT", "elevation":0.0},
		{"number":2, "name":"Waterline", "par":3, "yards":170.0, "dogleg":0.0, "pin_x":3.0, "water":true, "ob":"", "elevation":-3.0},
		{"number":3, "name":"Long Bend", "par":5, "yards":535.0, "dogleg":18.0, "pin_x":-5.0, "water":false, "ob":"RIGHT", "elevation":4.0},
		{"number":4, "name":"Narrow Window", "par":4, "yards":390.0, "dogleg":-14.0, "pin_x":-2.0, "water":false, "ob":"LEFT", "elevation":2.0},
		{"number":5, "name":"Cape Choice", "par":4, "yards":430.0, "dogleg":20.0, "pin_x":6.0, "water":true, "ob":"", "elevation":-2.0},
		{"number":6, "name":"Short Temptation", "par":3, "yards":145.0, "dogleg":-8.0, "pin_x":-4.0, "water":false, "ob":"", "elevation":5.0},
		{"number":7, "name":"Split Decision", "par":5, "yards":560.0, "dogleg":-22.0, "pin_x":-6.0, "water":true, "ob":"LEFT", "elevation":-4.0},
		{"number":8, "name":"Corner Office", "par":4, "yards":405.0, "dogleg":16.0, "pin_x":3.0, "water":false, "ob":"RIGHT", "elevation":1.0},
		{"number":9, "name":"Turn Home", "par":4, "yards":445.0, "dogleg":-18.0, "pin_x":-5.0, "water":false, "ob":"LEFT", "elevation":3.0},
		{"number":10, "name":"Restart", "par":4, "yards":400.0, "dogleg":8.0, "pin_x":2.0, "water":false, "ob":"", "elevation":0.0},
		{"number":11, "name":"Carry Ridge", "par":3, "yards":185.0, "dogleg":0.0, "pin_x":4.0, "water":true, "ob":"RIGHT", "elevation":6.0},
		{"number":12, "name":"Risk Corridor", "par":4, "yards":420.0, "dogleg":-12.0, "pin_x":-3.0, "water":false, "ob":"LEFT", "elevation":-1.0},
		{"number":13, "name":"Long Reach", "par":5, "yards":545.0, "dogleg":24.0, "pin_x":5.0, "water":false, "ob":"RIGHT", "elevation":2.0},
		{"number":14, "name":"Side Door", "par":4, "yards":365.0, "dogleg":-20.0, "pin_x":-6.0, "water":false, "ob":"", "elevation":4.0},
		{"number":15, "name":"Water's Edge", "par":4, "yards":440.0, "dogleg":18.0, "pin_x":5.0, "water":true, "ob":"RIGHT", "elevation":-3.0},
		{"number":16, "name":"Short Fuse", "par":3, "yards":160.0, "dogleg":-6.0, "pin_x":-2.0, "water":true, "ob":"", "elevation":2.0},
		{"number":17, "name":"Three-Shot Question", "par":5, "yards":570.0, "dogleg":-24.0, "pin_x":-5.0, "water":true, "ob":"LEFT", "elevation":-5.0},
		{"number":18, "name":"Home Stretch", "par":4, "yards":455.0, "dogleg":10.0, "pin_x":4.0, "water":false, "ob":"RIGHT", "elevation":3.0}
	]


static func _hole_dictionary(spec: Dictionary) -> Dictionary:
	var number: int = int(spec["number"])
	var par: int = int(spec["par"])
	var yards: float = float(spec["yards"])
	var dogleg: float = float(spec["dogleg"])
	var pin_x: float = float(spec["pin_x"])
	var fairway_width: float = 26.0 if par == 3 else (24.0 if par == 4 else 22.0)
	var midpoint_z: float = yards * 0.52
	var forward_reduction: float = 25.0 if par == 3 else (40.0 if par == 4 else 55.0)

	var fairway: Array = [
		[-fairway_width, yards - 28.0],
		[-fairway_width - 4.0, yards * 0.72],
		[dogleg - fairway_width, midpoint_z + 35.0],
		[dogleg - fairway_width - 2.0, midpoint_z - 35.0],
		[pin_x - fairway_width + 3.0, 55.0],
		[pin_x - 12.0, 30.0],
		[pin_x + 12.0, 30.0],
		[pin_x + fairway_width - 3.0, 55.0],
		[dogleg + fairway_width + 2.0, midpoint_z - 35.0],
		[dogleg + fairway_width, midpoint_z + 35.0],
		[fairway_width + 4.0, yards * 0.72],
		[fairway_width, yards - 28.0]
	]

	var hazards: Array = []
	var bunker_side: float = 1.0 if number % 2 == 0 else -1.0
	var bunker_z: float = yards * (0.22 if par == 3 else 0.42)
	hazards.append({
		"id":"fairway_bunker",
		"name":"Approach Bunker" if par == 3 else "Fairway Bunker",
		"type":"BUNKER",
		"polygon":_rect_polygon(dogleg + bunker_side * (fairway_width + 5.0), bunker_z, 8.0, 10.0)
	})
	hazards.append({
		"id":"green_bunker",
		"name":"Greenside Bunker",
		"type":"BUNKER",
		"polygon":_rect_polygon(pin_x - bunker_side * 24.0, 18.0, 7.0, 10.0)
	})

	if bool(spec["water"]):
		var water_z: float = yards * 0.48
		if par == 3:
			hazards.append({
				"id":"water_carry",
				"name":"Fronting Water",
				"type":"WATER",
				"penalty_strokes":1,
				"relief_rule":"PENALTY_AREA",
				"polygon":[[-38.0, water_z + 18.0], [32.0, water_z + 15.0], [35.0, water_z - 12.0], [-35.0, water_z - 15.0]]
			})
		else:
			var water_side: float = -1.0 if number % 2 == 0 else 1.0
			hazards.append({
				"id":"water_side",
				"name":"Lateral Water",
				"type":"WATER",
				"penalty_strokes":1,
				"relief_rule":"PENALTY_AREA",
				"polygon":_rect_polygon(dogleg + water_side * 30.0, water_z, 18.0, 42.0)
			})

	var out_of_bounds: Array = []
	var ob_side: String = str(spec["ob"])
	if ob_side == "RIGHT":
		out_of_bounds.append({
			"id":"right_ob", "name":"Right Boundary", "type":"OUT_OF_BOUNDS",
			"penalty_strokes":1, "relief_rule":"STROKE_AND_DISTANCE",
			"polygon":[[62.0, yards + 20.0], [88.0, yards + 20.0], [88.0, -30.0], [58.0, -30.0]]
		})
	elif ob_side == "LEFT":
		out_of_bounds.append({
			"id":"left_ob", "name":"Left Boundary", "type":"OUT_OF_BOUNDS",
			"penalty_strokes":1, "relief_rule":"STROKE_AND_DISTANCE",
			"polygon":[[-88.0, yards + 20.0], [-62.0, yards + 20.0], [-58.0, -30.0], [-88.0, -30.0]]
		})

	return {
		"schema_version":1,
		"course_id":COURSE_ID,
		"hole_number":number,
		"hole_name":str(spec["name"]),
		"par":par,
		"nominal_yardage":yards,
		"coordinate_units":"yards",
		"tees":[
			{"id":"default", "name":"Back Tee", "position":[0.0, 0.0, yards], "yardage":yards},
			{"id":"forward", "name":"Forward Tee", "position":[0.0, 0.0, yards - forward_reduction], "yardage":yards - forward_reduction}
		],
		"pin_position":[pin_x, 0.0, 8.0],
		"green_polygon":[
			[pin_x - 18.0, -5.0], [pin_x - 16.0, 17.0], [pin_x - 4.0, 28.0],
			[pin_x + 15.0, 22.0], [pin_x + 20.0, 5.0], [pin_x + 11.0, -13.0], [pin_x - 6.0, -17.0]
		],
		"surface_regions":[
			{"id":"teeing_ground", "name":"Hole %d Teeing Ground" % number, "surface":"TEE", "polygon":_rect_polygon(0.0, yards, 10.0, 10.0)},
			{"id":"fairway_main", "name":"Main Fairway", "surface":"FAIRWAY", "polygon":fairway}
		],
		"hazards":hazards,
		"out_of_bounds_regions":out_of_bounds,
		"elevation_points":[
			{"position":[0.0, 0.0, yards], "elevation":0.0},
			{"position":[dogleg, 0.0, yards * 0.55], "elevation":float(spec["elevation"])},
			{"position":[pin_x, 0.0, 8.0], "elevation":float(spec["elevation"]) * 0.5}
		]
	}


static func _rect_polygon(center_x: float, center_z: float, half_x: float, half_z: float) -> Array:
	return [
		[center_x - half_x, center_z - half_z],
		[center_x + half_x, center_z - half_z],
		[center_x + half_x, center_z + half_z],
		[center_x - half_x, center_z + half_z]
	]
