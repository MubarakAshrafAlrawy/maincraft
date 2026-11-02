extends Node3D

# ---------------------------------------------------------------------------
# Threaded chunk streamer.
#
#   * N worker threads generate chunk data and build the mesh/collision arrays.
#   * The main thread only uploads finished meshes, with a per-frame budget, so
#     moving the player never stalls the game.
#   * Chunk nodes are created/removed exclusively on the main thread.
# ---------------------------------------------------------------------------

const Registry = preload("res://BlockRegistry.gd")
const ChunkData = preload("res://ChunkData.gd")
const Chunk = preload("res://Chunk.gd")

# How many chunks around the player are kept loaded.
@export var load_radius: int = 5
# Chunks are only freed once they are this far outside load_radius.  The small
# hysteresis avoids load/unload thrashing when walking along a chunk border.
@export var unload_margin: int = 2
# Worker threads.  Clamped to CPU count - 1 in _ready().
@export var worker_count: int = 3
# Main-thread upload budget per frame.
@export var max_uploads_per_frame: int = 2
@export var upload_budget_ms: float = 4.0

# Terrain noise settings (one FastNoiseLite instance per worker).
var height_noise_seed: int = 0
var height_noise_frequency: float = 0.01

var _queue: Array[Vector2i] = []
var _pending: Dictionary = {}      # coord -> true (queued or in flight)
var _results: Array = []           # finished jobs waiting for the main thread
var _mutex := Mutex.new()
var _semaphore := Semaphore.new()
var _stop := false
var _threads: Array[Thread] = []

var _chunks: Dictionary = {}       # coord -> Chunk node (main thread only)
var _center := Vector2i(2147483647, 2147483647)
var _first_load := true

func _ready() -> void:
	Registry.ensure_tables()

	worker_count = clampi(worker_count, 1, maxi(1, OS.get_processor_count() - 1))
	for i in worker_count:
		var thread := Thread.new()
		thread.start(_worker.bind(i))
		_threads.append(thread)

func _exit_tree() -> void:
	shutdown()

# ---------------------------------------------------------------------------
# Public API (main thread)
# ---------------------------------------------------------------------------

func update_player_pos(new_pos) -> void:
	var coord := Vector2i(int(new_pos.x), int(new_pos.y))
	if coord == _center:
		return
	_center = coord

	# The first chunk is built immediately so the player always has ground
	# under their feet on spawn; everything else streams in on worker threads.
	if _first_load:
		_first_load = false
		_generate_chunk_now(coord)

	_refresh_requests()
	_unload_far_chunks()

# Synchronous build, used once for the spawn chunk.
func _generate_chunk_now(coord: Vector2i) -> void:
	if _chunks.has(coord):
		return

	var noise := FastNoiseLite.new()
	noise.seed = height_noise_seed
	noise.frequency = height_noise_frequency

	var data := ChunkData.new()
	data.generate(noise, coord.x, coord.y)
	var built: Dictionary = data.build_mesh()

	var chunk := Chunk.new()
	add_child(chunk)
	chunk.setup(coord, data, built)
	_chunks[coord] = chunk

func change_block(cx, cz, bx, by, bz, t) -> void:
	var coord := Vector2i(int(cx), int(cz))
	if not _chunks.has(coord):
		return
	var chunk = _chunks[coord]
	if chunk.chunk_data == null:
		return

	var x := int(bx)
	var y := int(by)
	var z := int(bz)
	if chunk.chunk_data.get_block(x, y, z) == Registry.id_of(t):
		return

	chunk.chunk_data.set_block(x, y, z, t)
	chunk.rebuild()

func get_loaded_chunk_count() -> int:
	return _chunks.size()

# Changes how far chunks stream in.  Safe to call at runtime from the settings
# menu: pending jobs outside the new radius are dropped and far chunks unload.
func set_load_radius(new_radius: int) -> void:
	var clamped := clampi(new_radius, 2, 16)
	if clamped == load_radius:
		return
	load_radius = clamped
	if _center.x == 2147483647:
		return
	_refresh_requests()
	_unload_far_chunks()

# World-space y of the terrain surface (the first empty cell above the ground)
# at a global column, or -1.0 when that chunk is not loaded.
func get_ground_y_global(x: int, z: int) -> float:
	var cx := int(floor(float(x) / float(Chunk.DIMENSION.x)))
	var cz := int(floor(float(z) / float(Chunk.DIMENSION.z)))
	var coord := Vector2i(cx, cz)
	if not _chunks.has(coord):
		return -1.0
	var chunk = _chunks[coord]
	if chunk.chunk_data == null:
		return -1.0
	var lx := x - cx * Chunk.DIMENSION.x
	var lz := z - cz * Chunk.DIMENSION.z
	return float(chunk.chunk_data.get_ground_height(lx, lz))

# Returns the numeric block id at a global block coordinate, or Air when the
# chunk is not loaded.
func get_block_id_global(x: int, y: int, z: int) -> int:
	var cx := int(floor(float(x) / float(Chunk.DIMENSION.x)))
	var cz := int(floor(float(z) / float(Chunk.DIMENSION.z)))
	var coord := Vector2i(cx, cz)
	if not _chunks.has(coord):
		return Registry.AIR
	var chunk = _chunks[coord]
	if chunk.chunk_data == null:
		return Registry.AIR
	var lx := x - cx * Chunk.DIMENSION.x
	var lz := z - cz * Chunk.DIMENSION.z
	return chunk.chunk_data.get_block(lx, y, lz)

func kill_thread() -> void:
	shutdown()

# ---------------------------------------------------------------------------
# Worker threads
# ---------------------------------------------------------------------------

func _worker(_index: int) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = height_noise_seed
	noise.frequency = height_noise_frequency

	while true:
		_semaphore.wait()

		_mutex.lock()
		if _stop:
			_mutex.unlock()
			return
		if _queue.is_empty():
			_mutex.unlock()
			continue
		var coord: Vector2i = _queue.pop_front()
		_mutex.unlock()

		var data := ChunkData.new()
		data.generate(noise, coord.x, coord.y)
		var built: Dictionary = data.build_mesh()

		_mutex.lock()
		_results.append({"coord": coord, "data": data, "built": built})
		_mutex.unlock()

# ---------------------------------------------------------------------------
# Main-thread scheduling
# ---------------------------------------------------------------------------

func _process(_delta: float) -> void:
	_drain_results()

func _drain_results() -> void:
	var start := Time.get_ticks_usec()
	var uploaded := 0

	while uploaded < max_uploads_per_frame:
		_mutex.lock()
		if _results.is_empty():
			_mutex.unlock()
			break
		var result: Dictionary = _results.pop_front()
		_mutex.unlock()

		_apply_result(result)
		uploaded += 1

		if float(Time.get_ticks_usec() - start) / 1000.0 >= upload_budget_ms:
			break

func _apply_result(result: Dictionary) -> void:
	var coord: Vector2i = result["coord"]
	_pending.erase(coord)

	if not _is_desired(coord):
		return
	if _chunks.has(coord):
		return

	var chunk := Chunk.new()
	add_child(chunk)
	chunk.setup(coord, result["data"], result["built"])
	_chunks[coord] = chunk

func _is_desired(coord: Vector2i) -> bool:
	var dx := coord.x - _center.x
	var dz := coord.y - _center.y
	return dx * dx + dz * dz <= load_radius * load_radius

# Rebuilds the request queue around the current center.  Runs on the main
# thread; the shared queue is only mutated while holding the mutex.
func _refresh_requests() -> void:
	var r := load_radius
	var r2 := r * r

	var desired := {}
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dz * dz <= r2:
				desired[_center + Vector2i(dx, dz)] = true

	var added := 0
	_mutex.lock()

	# Drop jobs that are no longer wanted.
	var kept: Array[Vector2i] = []
	for coord in _queue:
		if desired.has(coord):
			kept.append(coord)
		else:
			_pending.erase(coord)
	_queue = kept

	# Queue everything that is wanted but not loaded / already pending.
	for coord in desired:
		if not _pending.has(coord) and not _chunks.has(coord):
			_pending[coord] = true
			_queue.append(coord)
			added += 1

	# Closest chunks first.
	var center := _center
	_queue.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := (a.x - center.x) * (a.x - center.x) + (a.y - center.y) * (a.y - center.y)
		var db := (b.x - center.x) * (b.x - center.x) + (b.y - center.y) * (b.y - center.y)
		return da < db
	)

	_mutex.unlock()

	for i in added:
		_semaphore.post()

func _unload_far_chunks() -> void:
	var limit := load_radius + unload_margin
	var remove: Array[Vector2i] = []
	for coord in _chunks:
		if absi(coord.x - _center.x) > limit or absi(coord.y - _center.y) > limit:
			remove.append(coord)

	for coord in remove:
		var chunk = _chunks[coord]
		_chunks.erase(coord)
		chunk.queue_free()

# ---------------------------------------------------------------------------
# Shutdown
# ---------------------------------------------------------------------------

func shutdown() -> void:
	_mutex.lock()
	if _stop:
		_mutex.unlock()
		return
	_stop = true
	_mutex.unlock()

	for i in _threads.size():
		_semaphore.post()

	for thread in _threads:
		if thread.is_started():
			thread.wait_to_finish()
	_threads.clear()
