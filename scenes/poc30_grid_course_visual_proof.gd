extends Node3D

# POC-30F: Build-and-Play Visual Proof
# ------------------------------------
# One reusable proof hole built from the authoritative construction grid, then
# rendered through the POC-30 contoured terrain, organic surface overlay, and
# deterministic course-dressing layers. The demo never owns golf-rule state.
# A focused test plays the same HoleDefinition through the existing autonomous
# runtime to prove that visual improvement did not create a second course truth.

const CourseConstructionGrid = preload("res://simulation/course_construction_grid.gd")
const CourseConstructionEconomy = preload("res://simulation/course_construction_economy.gd")
const ConstructionGridHoleBuilder = preload("res://simulation/construction_grid_hole_builder.gd")
const ContouredTerrain = preload("res://scenes/construction_grid_contoured_terrain.gd")
const ContouredSurfaceRenderer = preload("res://scenes/construction_grid_contoured_surface_renderer.gd")
const CourseDressing = preload("res://scenes/construction_grid_course_dressing.gd")

var grid = null
var economy = null
var hole = null
var terrain = null
var surfaces = null
var dressing = null
var review_camera: Camera3D = null
var initialized: bool = false
var initialization_reason: String = ""


func _ready() -> void:
	initialized = initialize_proof()
	if not initialized:
		push_error("POC-30F visual proof failed to initialize: %s" % initialization_reason)
		return
	_add_course_markers()
	_add_review_camera()
	_add_hud()
	print("POC30F_VISUAL_PROOF_READY yardage=%.1f par=%d spend=%d fairway=%d fringe=%d green=%d bunker=%d water=%d dressing=%d" % [
		float(hole.nominal_yardage),
		int(hole.par),
		int(economy.lifetime_construction_spend),
		int(grid.count_surface("FAIRWAY")),
		int(grid.count_surface("FRINGE")),
		int(grid.count_surface("GREEN")),
		int(grid.count_surface("BUNKER")),
		int(grid.count_surface("WATER")),
		int(dressing.dressing_count())
	])


func initialize_proof() -> bool:
	if initialized and grid != null and hole != null:
		return true

	grid = CourseConstructionGrid.new()
	if not grid.configure(15, 48, 10.0, Vector2(-75.0, -15.0)):
		initialization_reason = "GRID_CONFIGURE_FAILED"
		return false
	_author_landform()

	economy = CourseConstructionEconomy.new()
	if not economy.configure(grid, 30000):
		initialization_reason = "ECONOMY_CONFIGURE_FAILED"
		return false
	if not _build_player_hole():
		initialization_reason = "CONSTRUCTION_FAILED"
		return false

	var builder = ConstructionGridHoleBuilder.new()
	hole = builder.build_hole(
		grid,
		"poc30_visual_proof_course",
		1,
		"Contour Creek",
		4,
		Vector2i(7, 44),
		Vector2i(7, 3),
		"back",
		"Back Tee"
	)
	if hole == null:
		initialization_reason = "HOLE_BUILD_FAILED"
		return false

	terrain = ContouredTerrain.new()
	terrain.name = "ContouredTerrainLayer"
	add_child(terrain)
	if not terrain.render_grid(grid):
		initialization_reason = "TERRAIN_RENDER_FAILED"
		return false

	surfaces = ContouredSurfaceRenderer.new()
	surfaces.name = "ContouredSurfaceLayer"
	add_child(surfaces)
	if not surfaces.render_grid(grid):
		initialization_reason = "SURFACE_RENDER_FAILED"
		return false

	dressing = CourseDressing.new()
	dressing.name = "CourseDressingLayer"
	add_child(dressing)
	if not dressing.render_dressing(grid):
		initialization_reason = "DRESSING_RENDER_FAILED"
		return false

	initialized = true
	initialization_reason = "READY"
	return true


func _author_landform() -> void:
	# Broad, low-amplitude rolls across the entire property. These values are
	# stored in the authoritative grid before rendering; the renderer does not
	# create hidden visual hills of its own.
	for y in range(int(grid.height)):
		for x in range(int(grid.width)):
			var elevation: float = (
				1.35 * sin(float(y) * 0.23)
				+ 0.55 * cos(float(x - 7) * 0.42)
				+ 0.35 * sin(float(x + y) * 0.17)
			)
			grid.set_elevation(x, y, elevation)


func _build_player_hole() -> bool:
	# Back tee.
	for y in range(44, 46):
		for x in range(6, 9):
			if not _purchase(x, y, "TEE"):
				return false

	# Three-cell-wide fairway with two gentle authored bends.
	for y in range(8, 44):
		var center_x: int = 7
		if y >= 18 and y < 29:
			center_x = 8
		elif y >= 29 and y < 37:
			center_x = 6
		for x in range(center_x - 1, center_x + 2):
			if not _purchase(x, y, "FAIRWAY"):
				return false

	# A real buildable fringe collar surrounds the nine-cell putting surface.
	for y in range(1, 6):
		for x in range(5, 10):
			if x >= 6 and x <= 8 and y >= 2 and y <= 4:
				continue
			if not _purchase(x, y, "FRINGE"):
				return false
	for y in range(2, 5):
		for x in range(6, 9):
			if not _purchase(x, y, "GREEN"):
				return false

	# Greenside sand and a landing-zone water feature.
	for cell in [Vector2i(4, 4), Vector2i(4, 5), Vector2i(4, 6), Vector2i(5, 6)]:
		if not _purchase(cell.x, cell.y, "BUNKER"):
			return false
	for cell in [
		Vector2i(10, 24), Vector2i(11, 24),
		Vector2i(10, 25), Vector2i(11, 25),
		Vector2i(10, 26), Vector2i(11, 26),
		Vector2i(10, 27), Vector2i(11, 27)
	]:
		if not _purchase(cell.x, cell.y, "WATER"):
			return false
	return true


func _purchase(x: int, y: int, surface: String) -> bool:
	var result: Dictionary = economy.build_surface(x, y, surface)
	return bool(result.get("built", false))


func _add_review_camera() -> void:
	review_camera = Camera3D.new()
	review_camera.name = "ReviewCamera"
	review_camera.fov = 58.0
	review_camera.near = 0.2
	review_camera.far = 1400.0
	add_child(review_camera)
	review_camera.current = true
	switch_review_camera(1)


func switch_review_camera(view_index: int) -> void:
	if review_camera == null:
		return
	match view_index:
		1:
			review_camera.position = Vector3(0.0, 24.0, 468.0)
			review_camera.look_at(Vector3(0.0, 0.0, 245.0), Vector3.UP)
		2:
			review_camera.position = Vector3(0.0, 175.0, 235.0)
			review_camera.look_at(Vector3(0.0, 0.0, 235.0), Vector3.FORWARD)
		3:
			review_camera.position = Vector3(44.0, 30.0, -2.0)
			review_camera.look_at(Vector3(0.0, 0.0, 22.0), Vector3.UP)
		_:
			switch_review_camera(1)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed or event.echo:
		return
	if event.keycode == KEY_1:
		switch_review_camera(1)
	elif event.keycode == KEY_2:
		switch_review_camera(2)
	elif event.keycode == KEY_3:
		switch_review_camera(3)


func _add_course_markers() -> void:
	var pin: Vector3 = grid.tile_center_world(7, 3)
	var stem := MeshInstance3D.new()
	stem.name = "PinStem"
	var stem_mesh := CylinderMesh.new()
	stem_mesh.top_radius = 0.07
	stem_mesh.bottom_radius = 0.07
	stem_mesh.height = 5.0
	stem_mesh.radial_segments = 8
	stem_mesh.material = _material(Color(0.92, 0.92, 0.88))
	stem.mesh = stem_mesh
	stem.position = pin + Vector3(0.0, 2.5, 0.0)
	stem.set_meta("classification", "PRESENTATION_MARKER")
	add_child(stem)

	var flag := MeshInstance3D.new()
	flag.name = "PinFlag"
	var flag_mesh := BoxMesh.new()
	flag_mesh.size = Vector3(1.8, 0.95, 0.05)
	flag_mesh.material = _material(Color(0.82, 0.12, 0.10))
	flag.mesh = flag_mesh
	flag.position = pin + Vector3(0.95, 4.4, 0.0)
	flag.set_meta("classification", "PRESENTATION_MARKER")
	add_child(flag)

	var tee_center: Vector3 = grid.tile_center_world(7, 44)
	for offset_x in [-2.0, 2.0]:
		var marker := MeshInstance3D.new()
		marker.name = "TeeMarker"
		var marker_mesh := SphereMesh.new()
		marker_mesh.radius = 0.28
		marker_mesh.height = 0.42
		marker_mesh.radial_segments = 8
		marker_mesh.rings = 4
		marker_mesh.material = _material(Color(0.92, 0.92, 0.88))
		marker.mesh = marker_mesh
		marker.position = tee_center + Vector3(offset_x, 0.22, 0.0)
		marker.set_meta("classification", "PRESENTATION_MARKER")
		add_child(marker)


func _add_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "ReviewHUD"
	add_child(layer)

	var panel := ColorRect.new()
	panel.color = Color(0.02, 0.04, 0.02, 0.82)
	panel.position = Vector2(18.0, 18.0)
	panel.size = Vector2(460.0, 112.0)
	layer.add_child(panel)

	var label := Label.new()
	label.position = Vector2(34.0, 30.0)
	label.text = "POC-30F  •  CONTOUR CREEK\n410 yd  •  Par 4  •  Authoritative construction grid\n1 Tee view    2 Aerial view    3 Green view\nGrid = truth  •  Renderer = presentation"
	label.add_theme_font_size_override("font_size", 16)
	layer.add_child(label)


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.92
	return material
