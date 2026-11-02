extends Node3D

var pw
@onready var player = $Player
@onready var block_outline = $BlockOutline

var Chunk = load("res://Chunk.gd")
var ProcWorld = load("res://ProcWorld.gd")
const Registry = preload("res://BlockRegistry.gd")
const ToolDefs = preload("res://ToolDefs.gd")

var chunk_pos := Vector2i(2147483647, 2147483647)

# Reused for the "would this block overlap the player?" test.
var _place_shape := BoxShape3D.new()
var _place_query := PhysicsShapeQueryParameters3D.new()

# Mining state.  The player emits mine_block every physics frame while the
# button is held; progress is accumulated here so it is frame-rate independent.
var _mining := false
var _mine_cell := Vector3i(0, -9999, 0)
var _mine_id := 0
var _mine_tool := ToolDefs.Tool.HAND
var _mine_tier := ToolDefs.Tier.ANY
var _mine_progress := 0.0
var _mine_total := 0.0

func _ready():
	print("CREATING WORLD")
	pw = ProcWorld.new()
	pw.load_radius = Settings.render_distance
	add_child(pw)

	Settings.changed.connect(_apply_settings)

	player.connect("place_block", Callable(self, "_on_Player_place_block"))
	player.connect("mine_block", Callable(self, "_on_Player_mine_block"))
	player.connect("mine_stop", Callable(self, "_on_Player_mine_stop"))
	player.connect("highlight_block", Callable(self, "_on_Player_highlight_block"))
	player.connect("unhighlight_block", Callable(self, "_on_Player_unhighlight_block"))

	_update_chunk_tracking()
	_snap_player_to_ground()

func _process(delta):
	_update_chunk_tracking()

	if not _mining:
		return

	_mine_progress += delta
	var fraction := 0.0
	if _mine_total > 0.0:
		fraction = clampf(_mine_progress / _mine_total, 0.0, 1.0)
	if player != null:
		player.set_mining_progress(fraction)

	if _mine_progress >= _mine_total:
		_finish_mining()

# Live settings changes: only the render distance needs to reach the streamer.
func _apply_settings() -> void:
	if pw != null and pw.load_radius != Settings.render_distance:
		pw.set_load_radius(Settings.render_distance)

# Tells the streamer which chunk the player is in.  Only called when the chunk
# actually changes, so there is no per-frame work here.
func _update_chunk_tracking():
	if player == null or pw == null:
		return

	var cx := int(floor(player.position.x / Chunk.DIMENSION.x))
	var cz := int(floor(player.position.z / Chunk.DIMENSION.z))
	var new_chunk_pos := Vector2i(cx, cz)

	if new_chunk_pos != chunk_pos:
		chunk_pos = new_chunk_pos
		pw.update_player_pos(chunk_pos)

# The scene has a fixed spawn height, so drop the player onto whatever terrain
# was generated instead of letting them fall for two seconds at startup.  Free
# columns (no trunk in the feet/head cells) are preferred.
func _snap_player_to_ground():
	if player == null or pw == null:
		return

	var bx := int(floor(player.position.x))
	var bz := int(floor(player.position.z))

	for radius in 5:
		for dz in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if radius > 0 and maxi(absi(dx), absi(dz)) != radius:
					continue

				var gx := bx + dx
				var gz := bz + dz
				var top: float = pw.get_ground_y_global(gx, gz)
				if top < 0.0:
					continue

				var feet: int = pw.get_block_id_global(gx, int(top), gz)
				var head: int = pw.get_block_id_global(gx, int(top) + 1, gz)
				if Registry.has_collision(feet) or Registry.has_collision(head):
					continue

				player.position = Vector3(float(gx) + 0.5, top + 1.0, float(gz) + 0.5)
				player.velocity = Vector3.ZERO
				return

# ---------------------------------------------------------------------------
# Mining (hold left mouse button)
# ---------------------------------------------------------------------------

func _on_Player_mine_block(pos, norm):
	var cell := _cell_from_hit(pos, norm, true)
	if cell.y < 0 or cell.y >= Chunk.DIMENSION.y:
		_cancel_mining()
		return

	var id: int = pw.get_block_id_global(cell.x, cell.y, cell.z)
	if id == Registry.AIR:
		_cancel_mining()
		return

	var tool: int = player.get_held_tool()
	var tier: int = player.get_held_tier()

	# A new target restarts the progress; moving the crosshair while holding
	# must not carry progress over to another block.
	if cell != _mine_cell:
		_mine_cell = cell
		_mine_progress = 0.0

	_mine_id = id
	_mine_tool = tool
	_mine_tier = tier
	_mine_total = Registry.break_time(id, tool, tier)
	_mining = true

	# Zero-hardness blocks (plants) break on the first tick.
	if _mine_total <= 0.0:
		_finish_mining()

func _on_Player_mine_stop():
	_cancel_mining()

func _cancel_mining():
	_mining = false
	_mine_progress = 0.0
	_mine_cell = Vector3i(0, -9999, 0)
	if player != null:
		player.set_mining_progress(0.0)

func _finish_mining():
	var cell := _mine_cell
	var id := _mine_id
	var tool := _mine_tool
	var tier := _mine_tier

	_mining = false
	_mine_progress = 0.0
	_mine_cell = Vector3i(0, -9999, 0)
	if player != null:
		player.set_mining_progress(0.0)

	if id == Registry.AIR:
		return

	# Drops follow the tool rules: a wrong tool or too low a tier means the
	# block breaks but drops nothing.
	if Registry.can_harvest_with(id, tool, tier):
		var drop := Registry.drop_of(id)
		if drop != "Air" and player != null:
			player.inventory.add_block(drop, 1)

	_change_global_block(cell, "Air")

# ---------------------------------------------------------------------------
# Placement / tool use (right mouse button)
# ---------------------------------------------------------------------------

func _on_Player_place_block(pos, norm):
	var cell := _cell_from_hit(pos, norm, false)
	if cell.y < 0 or cell.y >= Chunk.DIMENSION.y:
		return

	var tool: int = player.get_held_tool()

	# Tools act on the block that was clicked, and only on its top face:
	# shovel -> dirt path, hoe -> farmland.
	if norm.is_equal_approx(Vector3.UP):
		var hit_cell := _cell_from_hit(pos, norm, true)
		var hit_id: int = pw.get_block_id_global(hit_cell.x, hit_cell.y, hit_cell.z)
		if _apply_tool_transform(hit_cell, hit_id, tool):
			return

	var block_name: String = player.get_held_block()
	if block_name.is_empty():
		return

	var existing: int = pw.get_block_id_global(cell.x, cell.y, cell.z)
	if not Registry.is_replaceable(existing):
		return

	# Never allow a solid block to be placed inside the player; that used to
	# trap the character with no way to break free.
	if Registry.has_collision(Registry.id_of(block_name)) and _overlaps_player(cell):
		return

	if player.inventory.consume_selected(1):
		_change_global_block(cell, block_name)

func _apply_tool_transform(cell: Vector3i, id: int, tool: int) -> bool:
	if id == Registry.AIR:
		return false

	var grass := Registry.id_of("Grass")
	var dirt := Registry.id_of("Dirt")
	var path := Registry.id_of("Dirt_Path")
	var farm := Registry.id_of("Farmland")

	if tool == ToolDefs.Tool.HOE:
		if id == grass or id == dirt or id == path:
			_change_global_block(cell, "Farmland")
			return true
	elif tool == ToolDefs.Tool.SHOVEL:
		if id == grass or id == dirt or id == farm:
			_change_global_block(cell, "Dirt_Path")
			return true

	return false

# ---------------------------------------------------------------------------
# Block hit resolution / edits
# ---------------------------------------------------------------------------

# Resolves the block cell touched by a ray hit.
#
# The hit point usually sits exactly on a face, so floor() can land on either
# side of it.  "inward" means we want the block that was hit (destroy); the
# other case wants the empty cell in front of the face (place).
func _cell_from_hit(pos: Vector3, norm: Vector3, inward: bool) -> Vector3i:
	var cell := Vector3i(floor(pos.x), floor(pos.y), floor(pos.z))
	var current: int = pw.get_block_id_global(cell.x, cell.y, cell.z)

	if inward:
		# Ray started inside a block (player trapped): the hit point is already
		# inside it, so keep the cell instead of stepping away.
		if current == Registry.AIR:
			# hit_from_inside reports a zero normal at the ray origin.  If the
			# origin sits in the air pocket right above a block (a block was
			# placed at the player's feet) check the cell below so the player
			# can always dig free.
			if norm.is_zero_approx():
				var below := _floor_cell(pos - Vector3(0.0, 0.5, 0.0))
				if pw.get_block_id_global(below.x, below.y, below.z) != Registry.AIR:
					return below
			return _floor_cell(pos - norm * 0.5)
		return cell

	if current != Registry.AIR:
		return _floor_cell(pos + norm * 0.5)
	return cell

func _floor_cell(p: Vector3) -> Vector3i:
	return Vector3i(floor(p.x), floor(p.y), floor(p.z))

# True when a full block at this cell would intersect the player's collider.
func _overlaps_player(cell: Vector3i) -> bool:
	if player == null or not is_inside_tree():
		return false

	var space := get_world_3d().direct_space_state
	if space == null:
		return false

	# Slightly smaller than a block so touching a face is still allowed.
	_place_shape.size = Vector3(0.96, 0.96, 0.96)
	_place_query.shape = _place_shape
	_place_query.transform = Transform3D(Basis(), Vector3(cell) + Vector3(0.5, 0.5, 0.5))
	_place_query.collision_mask = 0xFFFFFFFF
	_place_query.collide_with_bodies = true
	_place_query.collide_with_areas = false

	var hits := space.intersect_shape(_place_query, 16)
	for hit in hits:
		if hit.get("collider") == player:
			return true
	return false

func _change_global_block(cell: Vector3i, block_name: String) -> void:
	pw.change_block(
		int(floor(cell.x / float(Chunk.DIMENSION.x))),
		int(floor(cell.z / float(Chunk.DIMENSION.z))),
		cell.x - int(floor(cell.x / float(Chunk.DIMENSION.x))) * Chunk.DIMENSION.x,
		cell.y,
		cell.z - int(floor(cell.z / float(Chunk.DIMENSION.z))) * Chunk.DIMENSION.z,
		block_name
	)

func _on_Player_highlight_block(pos, norm):
	block_outline.visible = true

	var cell := _cell_from_hit(pos, norm, true)
	block_outline.position = Vector3(cell) + Vector3(0.5, 0.5, 0.5)

func _on_Player_unhighlight_block():
	block_outline.visible = false
