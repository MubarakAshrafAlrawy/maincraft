extends RefCounted

# ---------------------------------------------------------------------------
# Pure data + mesh builder for one chunk.
#
# This class never touches the scene tree, so every method here can be called
# from a worker thread.  ProcWorld builds the actual Chunk node on the main
# thread once the mesh is ready.
#
# The visual mesh is built face by face (textures need per-block UVs), while the
# collision mesh is greedily merged.  A concave collision shape is expensive to
# build, so merging coplanar faces keeps that cost tiny.
# ---------------------------------------------------------------------------

const Registry = preload("res://BlockRegistry.gd")
const ForestGenerator = preload("res://chunk_generators/ForestGenerator.gd")

const SX := 16
const SY := 50
const SZ := 16
const BLOCK_COUNT := SX * SY * SZ
const DIMENSION := Vector3i(SX, SY, SZ)

# Unit cube corners.
const V := [
	Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0),
	Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(0, 1, 1), Vector3(1, 1, 1)
]

# Face vertex order, matching the original project (winding preserved).
const TOP := [2, 3, 7, 6]
const BOTTOM := [0, 4, 5, 1]
const LEFT := [6, 4, 0, 2]
const RIGHT := [3, 1, 5, 7]
const FRONT := [7, 5, 4, 6]
const BACK := [2, 0, 1, 3]
const CROSS_1 := [3, 1, 4, 6]
const CROSS_2 := [7, 5, 0, 2]
const CROSS_3 := [6, 4, 1, 3]
const CROSS_4 := [2, 0, 5, 7]

const AXES := [Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)]

var chunk_coord := Vector2i.ZERO
var data := PackedByteArray()
var height_map := PackedInt32Array()
var generator: Script = ForestGenerator

# Scratch buffers reused by build_mesh().
var _verts := PackedVector3Array()
var _normals := PackedVector3Array()
var _uvs := PackedVector2Array()
var _indices := PackedInt32Array()
var _collision_faces := PackedVector3Array()
var _mask := PackedByteArray()

# Atlas metrics for the current build (normalised tile size + half texel).
var _tile := Vector2.ONE
var _half_texel := Vector2.ZERO

static func _index(x: int, y: int, z: int) -> int:
	return (y * SZ + z) * SX + x

# ---------------------------------------------------------------------------
# World generation (worker thread)
# ---------------------------------------------------------------------------

func generate(noise: FastNoiseLite, cx: int, cz: int) -> void:
	Registry.ensure_tables()
	chunk_coord = Vector2i(cx, cz)

	data.resize(BLOCK_COUNT)
	data.fill(Registry.AIR)
	height_map.resize(SX * SZ)

	var rng := RandomNumberGenerator.new()
	rng.set_seed(cx * 1000 + cz)

	var base_x := cx * SX
	var base_z := cz * SZ
	var plane := SX * SZ
	var air := Registry.AIR

	# The surface generators only depend on the column height, so the block
	# type for a given (height, y) is computed once per chunk and reused.
	# 255 means "not computed yet".
	var cache := PackedByteArray()
	cache.resize((Registry.GEN_HEIGHT + 4) * SY)
	cache.fill(255)

	# Height is only a function of (x, z); sampling the noise once per column
	# instead of once per block removes 50x the noise work.
	for x in SX:
		for z in SZ:
			var h_noise: float = (noise.get_noise_2d(float(base_x + x), float(base_z + z)) + 1.0) * 0.5
			var h := int(h_noise * (Registry.GEN_HEIGHT - 1) + 1.0) + Registry.BLOCK_OFFSET
			height_map[x + z * SX] = h

			var cache_base := h * SY
			var index := z * SX + x
			for y in SY:
				var block_id := cache[cache_base + y]
				if block_id == 255:
					var type_name: String = generator.generate_surface(h, x, y, z)
					block_id = air if type_name == "Air" else Registry.id_of(type_name)
					cache[cache_base + y] = block_id
				if block_id != air:
					data[index] = block_id
				index += plane

	generator.generate_details(self, rng)

# ---------------------------------------------------------------------------
# Data access (worker thread)
# ---------------------------------------------------------------------------

func get_ground_height(x: int, z: int) -> int:
	if x < 0 or x >= SX or z < 0 or z >= SZ:
		return 0
	return height_map[x + z * SX]

func get_block(x: int, y: int, z: int) -> int:
	if x < 0 or x >= SX or y < 0 or y >= SY or z < 0 or z >= SZ:
		return Registry.AIR
	return data[_index(x, y, z)]

func set_block(x: int, y: int, z: int, type_name: String, overwrite := true) -> void:
	x = int(x)
	y = int(y)
	z = int(z)
	if x < 0 or x >= SX or y < 0 or y >= SY or z < 0 or z >= SZ:
		return
	var i := _index(x, y, z)
	if overwrite or data[i] == Registry.AIR:
		data[i] = Registry.id_of(type_name)

# ---------------------------------------------------------------------------
# Meshing (worker thread)
# ---------------------------------------------------------------------------

# Returns { "mesh": ArrayMesh or null, "collision": Shape3D or null }.
func build_mesh() -> Dictionary:
	Registry.ensure_tables()

	# Local aliases remove a lot of per-block property / function lookups.
	var blocks := data
	var flags := Registry.get_flags()
	var uv_table := Registry.get_side_uv_table()
	var f_trans: int = Registry.FLAG_TRANSPARENT
	var f_flat: int = Registry.FLAG_FLAT
	_tile = Registry.get_atlas_tile()
	_half_texel = Registry.get_atlas_half_texel()

	_verts.clear()
	_normals.clear()
	_uvs.clear()
	_indices.clear()

	var sx := SX
	var sy := SY
	var sz := SZ
	var plane := sx * sz  # index step between two block layers

	for y in sy:
		for z in sz:
			var col := (y * sz + z) * sx
			for x in sx:
				var id := blocks[col + x]
				if id == 0:
					continue

				var f := flags[id]

				if (f & f_flat) != 0:
					var flat_uv := uv_table[id * 7 + 6]
					_add_face(CROSS_1, x, y, z, flat_uv)
					_add_face(CROSS_2, x, y, z, flat_uv)
					_add_face(CROSS_3, x, y, z, flat_uv)
					_add_face(CROSS_4, x, y, z, flat_uv)
					continue

				var uv_base := id * 7

				# Out-of-bounds neighbours count as transparent, exactly like
				# the original is_block_transparent() helper.
				if y + 1 >= sy or (flags[blocks[col + x + plane]] & f_trans) != 0:
					_add_face(TOP, x, y, z, uv_table[uv_base])
				if y == 0 or (flags[blocks[col + x - plane]] & f_trans) != 0:
					_add_face(BOTTOM, x, y, z, uv_table[uv_base + 1])
				if x == 0 or (flags[blocks[col + x - 1]] & f_trans) != 0:
					_add_face(LEFT, x, y, z, uv_table[uv_base + 2])
				if x + 1 >= sx or (flags[blocks[col + x + 1]] & f_trans) != 0:
					_add_face(RIGHT, x, y, z, uv_table[uv_base + 3])
				if z == 0 or (flags[blocks[col + x - sx]] & f_trans) != 0:
					_add_face(BACK, x, y, z, uv_table[uv_base + 5])
				if z + 1 >= sz or (flags[blocks[col + x + sx]] & f_trans) != 0:
					_add_face(FRONT, x, y, z, uv_table[uv_base + 4])

	_build_collision()

	var result := {"mesh": null, "collision": null}
	if not _verts.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = _verts
		arrays[Mesh.ARRAY_NORMAL] = _normals
		arrays[Mesh.ARRAY_TEX_UV] = _uvs
		arrays[Mesh.ARRAY_INDEX] = _indices

		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, Registry.get_material())
		result["mesh"] = mesh

	if not _collision_faces.is_empty():
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(_collision_faces)
		result["collision"] = shape

	return result

func _add_face(face: Array, x: int, y: int, z: int, uv_offset: Vector2) -> void:
	var offset := Vector3(x, y, z)
	var a: Vector3 = V[face[0]] + offset
	var b: Vector3 = V[face[1]] + offset
	var c: Vector3 = V[face[2]] + offset
	var d: Vector3 = V[face[3]] + offset

	# Godot uses clockwise winding for front faces, so the outward normal is
	# (c - a) x (b - a).
	var normal := (c - a).cross(b - a).normalized()

	# UVs are normalised top-left corners from the runtime atlas.  Inset by
	# half a texel so nearest/linear sampling never touches the next tile.
	var uv_start := uv_offset + _half_texel
	var uv_end := uv_start + _tile - _half_texel * 2.0
	var uv_a := uv_start
	var uv_b := Vector2(uv_start.x, uv_end.y)
	var uv_c := uv_end
	var uv_d := Vector2(uv_end.x, uv_start.y)

	var base := _verts.size()

	_verts.append(a)
	_verts.append(b)
	_verts.append(c)
	_verts.append(d)

	_normals.append(normal)
	_normals.append(normal)
	_normals.append(normal)
	_normals.append(normal)

	_uvs.append(uv_a)
	_uvs.append(uv_b)
	_uvs.append(uv_c)
	_uvs.append(uv_d)

	_indices.append(base)
	_indices.append(base + 1)
	_indices.append(base + 2)
	_indices.append(base)
	_indices.append(base + 2)
	_indices.append(base + 3)

# ---------------------------------------------------------------------------
# Collision mesh: greedy merged quads (worker thread)
# ---------------------------------------------------------------------------

func _build_collision() -> void:
	_collision_faces.clear()

	var blocks := data
	var flags := Registry.get_flags()
	var f_trans: int = Registry.FLAG_TRANSPARENT
	var solid_mask: int = Registry.FLAG_TRANSPARENT | Registry.FLAG_NO_COLLISION

	var dim := [SX, SY, SZ]
	var step := [1, SX * SZ, SX]

	for d in 3:
		var u := (d + 1) % 3
		var v := (d + 2) % 3
		var dim_d: int = dim[d]
		var dim_u: int = dim[u]
		var dim_v: int = dim[v]
		var step_d: int = step[d]
		var step_u: int = step[u]
		var step_v: int = step[v]

		for dir in [1, -1]:
			_mask.resize(dim_u * dim_v)

			for s in dim_d:
				_mask.fill(0)

				# Build the 2D face mask for this slice.
				for j in dim_v:
					var row := s * step_d + j * step_v
					var mask_row := j * dim_u
					for i in dim_u:
						var index := row + i * step_u
						var id := blocks[index]
						if id == 0 or (flags[id] & solid_mask) != 0:
							continue
						var ns: int = s + dir
						if ns < 0 or ns >= dim_d or (flags[blocks[index + dir * step_d]] & f_trans) != 0:
							_mask[mask_row + i] = 1

				# Greedy rectangle merge.
				var j := 0
				while j < dim_v:
					var i := 0
					while i < dim_u:
						if _mask[i + j * dim_u] == 0:
							i += 1
							continue

						var w := 1
						while i + w < dim_u and _mask[i + w + j * dim_u] != 0:
							w += 1

						var h := 1
						var stop := false
						while j + h < dim_v and not stop:
							for k in w:
								if _mask[i + k + (j + h) * dim_u] == 0:
									stop = true
									break
							if not stop:
								h += 1

						for jj in h:
							var clear_row := (j + jj) * dim_u
							for ii in w:
								_mask[i + ii + clear_row] = 0

						_emit_collision_quad(d, dir, s, i, j, w, h)
						i += w
					j += 1

func _emit_collision_quad(d: int, dir: int, s: int, i: int, j: int, w: int, h: int) -> void:
	var d_axis: Vector3 = AXES[d]
	var u_axis: Vector3 = AXES[(d + 1) % 3]
	var v_axis: Vector3 = AXES[(d + 2) % 3]

	var plane := float(s + (1 if dir > 0 else 0))
	var p0 := d_axis * plane + u_axis * float(i) + v_axis * float(j)
	var p1 := p0 + u_axis * float(w)
	var p2 := p1 + v_axis * float(h)
	var p3 := p0 + v_axis * float(h)

	var outward := d_axis * float(dir)
	var normal := (p2 - p0).cross(p1 - p0)

	if normal.dot(outward) < 0.0:
		_collision_faces.append(p0)
		_collision_faces.append(p2)
		_collision_faces.append(p1)
		_collision_faces.append(p0)
		_collision_faces.append(p3)
		_collision_faces.append(p2)
	else:
		_collision_faces.append(p0)
		_collision_faces.append(p1)
		_collision_faces.append(p2)
		_collision_faces.append(p0)
		_collision_faces.append(p2)
		_collision_faces.append(p3)
