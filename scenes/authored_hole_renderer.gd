extends Node3D

# POC-21A: Authored Hole -> 3D World
# -----------------------------------
# Renders authoritative HoleDefinition polygons directly into lightweight 3D
# meshes. This is a visual projection only: simulation geometry remains owned by
# HoleDefinition / HoleCourseContext and is never reconstructed from the meshes.

const SURFACE_HEIGHT_STEP := 0.02

var hole_definition = null
var tee_id: String = "default"
var rendered_regions: Array = []


func render_hole(definition, selected_tee_id: String = "default") -> bool:
	clear_hole()
	if definition == null or not definition.is_valid():
		return false

	hole_definition = definition
	tee_id = selected_tee_id

	# Order from broad/base surfaces to more specific overlays. Small Y offsets
	# prevent z-fighting while preserving course-space X/Z coordinates exactly.
	for region_value in definition.surface_regions:
		var region: Dictionary = region_value
		_add_region_mesh(
			str(region.get("id", "surface")),
			str(region.get("surface", "ROUGH")).to_upper(),
			region.get("polygon", PackedVector2Array()),
			_surface_color(str(region.get("surface", "ROUGH"))),
			SURFACE_HEIGHT_STEP
		)

	_add_region_mesh(
		"green",
		"GREEN",
		definition.green_polygon,
		_surface_color("GREEN"),
		SURFACE_HEIGHT_STEP * 2.0
	)

	for hazard_value in definition.hazards:
		var hazard: Dictionary = hazard_value
		var hazard_type: String = str(hazard.get("type", "HAZARD")).to_upper()
		_add_region_mesh(
			str(hazard.get("id", "hazard")),
			hazard_type,
			hazard.get("polygon", PackedVector2Array()),
			_surface_color(hazard_type),
			SURFACE_HEIGHT_STEP * 3.0
		)

	for ob_value in definition.out_of_bounds_regions:
		var ob_region: Dictionary = ob_value
		_add_region_outline(
			str(ob_region.get("id", "out_of_bounds")),
			"OUT_OF_BOUNDS",
			ob_region.get("polygon", PackedVector2Array()),
			Color(0.95, 0.95, 0.95),
			SURFACE_HEIGHT_STEP * 4.0
		)

	_add_tee_marker(definition.tee_position(tee_id))
	_add_pin_marker(definition.pin_position)
	return true


func clear_hole() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	rendered_regions.clear()
	hole_definition = null


func region_visual(region_id: String) -> Node3D:
	for child in get_children():
		if child is Node3D and str(child.get_meta("region_id", "")) == region_id:
			return child
	return null


func _add_region_mesh(region_id: String, classification: String, polygon_value, color: Color, height: float) -> void:
	var polygon: PackedVector2Array = polygon_value
	if polygon.size() < 3:
		return
	var indices: PackedInt32Array = Geometry2D.triangulate_polygon(polygon)
	if indices.size() < 3:
		return

	var vertices := PackedVector3Array()
	for index in indices:
		var point: Vector2 = polygon[index]
		vertices.append(Vector3(point.x, height, point.y))

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _material(color))

	var visual := MeshInstance3D.new()
	visual.name = _safe_node_name(region_id)
	visual.mesh = mesh
	_tag_visual(visual, region_id, classification, polygon)
	add_child(visual)


func _add_region_outline(region_id: String, classification: String, polygon_value, color: Color, height: float) -> void:
	var polygon: PackedVector2Array = polygon_value
	if polygon.size() < 2:
		return

	var immediate := ImmediateMesh.new()
	immediate.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, _material(color))
	for point in polygon:
		immediate.surface_add_vertex(Vector3(point.x, height, point.y))
	var first: Vector2 = polygon[0]
	immediate.surface_add_vertex(Vector3(first.x, height, first.y))
	immediate.surface_end()

	var visual := MeshInstance3D.new()
	visual.name = _safe_node_name(region_id)
	visual.mesh = immediate
	_tag_visual(visual, region_id, classification, polygon)
	add_child(visual)


func _add_tee_marker(position: Vector3) -> void:
	var marker := MeshInstance3D.new()
	marker.name = "TeeMarker"
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.75
	mesh.bottom_radius = 0.75
	mesh.height = 0.20
	mesh.material = _material(Color(0.15, 0.35, 0.95))
	marker.mesh = mesh
	marker.position = Vector3(position.x, 0.12, position.z)
	marker.set_meta("marker_type", "TEE")
	marker.set_meta("course_position", position)
	add_child(marker)


func _add_pin_marker(position: Vector3) -> void:
	var marker := MeshInstance3D.new()
	marker.name = "PinMarker"
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.08
	mesh.bottom_radius = 0.08
	mesh.height = 4.0
	mesh.material = _material(Color(0.95, 0.20, 0.15))
	marker.mesh = mesh
	marker.position = Vector3(position.x, 2.0, position.z)
	marker.set_meta("marker_type", "PIN")
	marker.set_meta("course_position", position)
	add_child(marker)


func _tag_visual(visual: MeshInstance3D, region_id: String, classification: String, polygon: PackedVector2Array) -> void:
	visual.set_meta("region_id", region_id)
	visual.set_meta("classification", classification)
	visual.set_meta("source_polygon", polygon)
	rendered_regions.append({
		"region_id": region_id,
		"classification": classification,
		"source_polygon": polygon,
		"node": visual
	})


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


func _surface_color(classification_value: String) -> Color:
	var classification: String = classification_value.to_upper()
	match classification:
		"TEE":
			return Color(0.28, 0.62, 0.28)
		"FAIRWAY":
			return Color(0.24, 0.66, 0.30)
		"GREEN":
			return Color(0.38, 0.82, 0.38)
		"ROUGH":
			return Color(0.16, 0.45, 0.20)
		"BUNKER", "SAND":
			return Color(0.82, 0.72, 0.46)
		"WATER":
			return Color(0.12, 0.42, 0.82)
		_:
			return Color(0.20, 0.50, 0.22)


func _safe_node_name(value: String) -> String:
	var result: String = value.strip_edges()
	if result.is_empty():
		result = "Region"
	return result.replace("/", "_").replace(":", "_")
