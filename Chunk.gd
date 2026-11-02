extends StaticBody3D

# ---------------------------------------------------------------------------
# Scene node for a single chunk.
#
# The heavy work (terrain data + mesh arrays) happens in ChunkData on a worker
# thread.  This node only receives the finished mesh and collision shape on the
# main thread, which keeps frame times stable while the player moves.
# ---------------------------------------------------------------------------

const Registry = preload("res://BlockRegistry.gd")
const ChunkData = preload("res://ChunkData.gd")

const DIMENSION = Registry.DIMENSION

var chunk_coord := Vector2i.ZERO
var chunk_data = null  # ChunkData instance (shared with the worker result)

var _mesh_instance: MeshInstance3D = null
var _collision: CollisionShape3D = null

# Called on the main thread with an already generated ChunkData + built mesh.
func setup(coord: Vector2i, data, built: Dictionary) -> void:
	chunk_coord = coord
	chunk_data = data
	name = "Chunk_%d_%d" % [coord.x, coord.y]
	position = Vector3(float(coord.x * DIMENSION.x), 0.0, float(coord.y * DIMENSION.z))
	_apply(built)

func _apply(built: Dictionary) -> void:
	var mesh = built.get("mesh", null)
	if mesh != null:
		if _mesh_instance == null:
			_mesh_instance = MeshInstance3D.new()
			_mesh_instance.name = "Mesh"
			add_child(_mesh_instance)
		_mesh_instance.mesh = mesh
	elif _mesh_instance != null:
		_mesh_instance.mesh = null

	var shape = built.get("collision", null)
	if shape != null:
		if _collision == null:
			_collision = CollisionShape3D.new()
			_collision.name = "Collision"
			add_child(_collision)
		_collision.shape = shape
	elif _collision != null:
		_collision.shape = null

# Rebuilds the mesh after a block edit.  Called from the main thread; it is
# fast enough for a single chunk (the data is already in memory).
func rebuild() -> void:
	if chunk_data == null:
		return
	_apply(chunk_data.build_mesh())
