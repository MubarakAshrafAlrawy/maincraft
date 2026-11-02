extends RefCounted

# ---------------------------------------------------------------------------
# Shared block definitions for the whole project.
#
# ContentLoader.gd reads content/<pack>/blocks.json (and user://packs), then
# AtlasBuilder.gd packs the referenced PNGs into one runtime atlas.  This
# script turns both into flat Packed*Arrays once at startup.  Everything here
# is read-only after ensure_tables(), so it is safe to read from chunk workers.
# ---------------------------------------------------------------------------

const ContentLoader = preload("res://ContentLoader.gd")
const AtlasBuilder = preload("res://AtlasBuilder.gd")
const ToolDefs = preload("res://ToolDefs.gd")

enum Side { top, bottom, left, right, front, back, only }
enum Tags { Transparent, No_Collision, Flat, Liquid, Replaceable }

enum Flags {
	TRANSPARENT = 1,
	PASSABLE = 2,
	FLAT = 4,
	LIQUID = 8,
	REPLACEABLE = 16,
}

# Chunk size in blocks.
const DIMENSION := Vector3i(16, 50, 16)
const GEN_HEIGHT := 50
const BLOCK_OFFSET := 1

# Numeric id of the empty block.  Must stay 0 so a freshly cleared
# PackedByteArray is already filled with air.
const AIR := 0

# Numeric flags stored per block id in the hot lookup table.
const FLAG_TRANSPARENT := Flags.TRANSPARENT
const FLAG_NO_COLLISION := Flags.PASSABLE
const FLAG_FLAT := Flags.FLAT
const FLAG_LIQUID := Flags.LIQUID
const FLAG_REPLACEABLE := Flags.REPLACEABLE
# Readable alias: passable blocks can be walked through.
const FLAG_PASSABLE := Flags.PASSABLE

# Populated by ensure_tables(), in id order.
static var BLOCK_NAMES: Array = []
# Legacy readable dictionary kept for editor / older code.  Mirrors the old
# { Side -> uv, "Tags" -> [...] } layout.
static var block_types: Dictionary = {}

static var _tables_ready := false
static var _defs: Array = []
static var _packs: Array = []
static var _id_by_name: Dictionary = {}
static var _flags: PackedByteArray = PackedByteArray()
static var _side_uv: PackedVector2Array = PackedVector2Array()
static var _hardness: PackedFloat32Array = PackedFloat32Array()
static var _tool: PackedByteArray = PackedByteArray()
static var _tier: PackedByteArray = PackedByteArray()
static var _light: PackedByteArray = PackedByteArray()
static var _drops: Array[String] = []

# Runtime atlas, built from the content pack textures.
static var _atlas_texture: Texture2D = null
static var _atlas_material: StandardMaterial3D = null
static var _atlas_tile := Vector2.ONE
static var _atlas_half_texel := Vector2.ZERO
static var _atlas_size := Vector2i.ZERO
static var _atlas_uv: Dictionary = {}

# Builds the block tables and the runtime atlas.  Call this once on the main
# thread before any worker starts; later calls are cheap early-outs.
static func ensure_tables() -> void:
	if _tables_ready:
		return

	var content := ContentLoader.build()
	_defs = content.get("blocks", [])
	_packs = content.get("packs", [])
	_build_atlas(content)

	var count := _defs.size()
	BLOCK_NAMES.clear()
	block_types.clear()
	_id_by_name.clear()
	_flags.resize(count)
	_side_uv.resize(count * 7)
	_hardness.resize(count)
	_tool.resize(count)
	_tier.resize(count)
	_light.resize(count)
	_drops.clear()
	_drops.resize(count)

	for i in count:
		var def: Dictionary = _defs[i]
		var block_name := String(def.get("name", "Air"))
		BLOCK_NAMES.append(block_name)
		_id_by_name[block_name] = i

		var flags := int(def.get("flags", 0))
		_flags[i] = flags
		_hardness[i] = float(def.get("hardness", 0.0))
		_tool[i] = int(def.get("tool", ToolDefs.Tool.HAND))
		_tier[i] = int(def.get("tier", ToolDefs.Tier.ANY))
		_light[i] = int(def.get("light", 0))
		_drops[i] = String(def.get("drops", ""))

		_fill_side_uvs(i, def.get("textures", {}))
		_build_legacy_info(i, block_name, flags)

	_tables_ready = true

# ---------------------------------------------------------------------------
# Runtime atlas
# ---------------------------------------------------------------------------

static func _build_atlas(content: Dictionary) -> void:
	var textures: Dictionary = content.get("textures", {})
	var tile_size := int(content.get("tile_size", 16))
	var built := AtlasBuilder.build(textures, tile_size)

	_atlas_size = built["size"]
	_atlas_uv = built["uv"]
	var cols := int(built["cols"])
	var rows := int(built["rows"])
	_atlas_tile = Vector2(1.0 / float(cols), 1.0 / float(rows))
	_atlas_half_texel = Vector2(0.5 / float(_atlas_size.x), 0.5 / float(_atlas_size.y))

	var image: Image = built["image"]
	_atlas_texture = ImageTexture.create_from_image(image)

	_atlas_material = StandardMaterial3D.new()
	_atlas_material.albedo_texture = _atlas_texture
	_atlas_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	_atlas_material.alpha_scissor_threshold = 0.5
	_atlas_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_atlas_material.texture_repeat = false

static func get_atlas_texture() -> Texture2D:
	ensure_tables()
	return _atlas_texture

static func get_material() -> Material:
	ensure_tables()
	return _atlas_material

static func get_atlas_tile() -> Vector2:
	ensure_tables()
	return _atlas_tile

static func get_atlas_half_texel() -> Vector2:
	ensure_tables()
	return _atlas_half_texel

static func get_atlas_size() -> Vector2i:
	ensure_tables()
	return _atlas_size

static func get_loaded_packs() -> Array:
	ensure_tables()
	return _packs.duplicate()

# ---------------------------------------------------------------------------
# Face textures
# ---------------------------------------------------------------------------

static func _fill_side_uvs(id: int, textures: Dictionary) -> void:
	var all := String(textures.get("all", textures.get("only", "")))
	var only := String(textures.get("only", all))
	var top := String(textures.get("top", only))
	var bottom := String(textures.get("bottom", only))
	var side := String(textures.get("side", only))
	var base := id * 7

	_side_uv[base + Side.top] = _uv_for(top)
	_side_uv[base + Side.bottom] = _uv_for(bottom)
	_side_uv[base + Side.left] = _uv_for(String(textures.get("left", side)))
	_side_uv[base + Side.right] = _uv_for(String(textures.get("right", side)))
	_side_uv[base + Side.front] = _uv_for(String(textures.get("front", side)))
	_side_uv[base + Side.back] = _uv_for(String(textures.get("back", side)))
	_side_uv[base + Side.only] = _uv_for(only)

static func _uv_for(texture_name: String) -> Vector2:
	if _atlas_uv.has(texture_name):
		return _atlas_uv[texture_name]
	return _atlas_uv.get(AtlasBuilder.MISSING_TEXTURE, Vector2.ZERO)

static func _build_legacy_info(id: int, block_name: String, flags: int) -> void:
	var info := {}
	var base := id * 7
	for side in 7:
		info[side] = _side_uv[base + side]

	var tags: Array = []
	if (flags & FLAG_TRANSPARENT) != 0:
		tags.append(Tags.Transparent)
	if (flags & FLAG_NO_COLLISION) != 0:
		tags.append(Tags.No_Collision)
	if (flags & FLAG_FLAT) != 0:
		tags.append(Tags.Flat)
	if (flags & FLAG_LIQUID) != 0:
		tags.append(Tags.Liquid)
	if (flags & FLAG_REPLACEABLE) != 0:
		tags.append(Tags.Replaceable)
	info["Tags"] = tags
	block_types[block_name] = info

# ---------------------------------------------------------------------------
# Lookups
# ---------------------------------------------------------------------------

static func id_of(block_name: String) -> int:
	ensure_tables()
	return int(_id_by_name.get(block_name, AIR))

static func name_of(id: int) -> String:
	ensure_tables()
	if id < 0 or id >= BLOCK_NAMES.size():
		return "Air"
	return BLOCK_NAMES[id]

static func flags_of(id: int) -> int:
	ensure_tables()
	if id < 0 or id >= _flags.size():
		return 0
	return _flags[id]

static func hardness_of(id: int) -> float:
	ensure_tables()
	if id < 0 or id >= _hardness.size():
		return 0.0
	return _hardness[id]

static func tool_of(id: int) -> int:
	ensure_tables()
	if id < 0 or id >= _tool.size():
		return ToolDefs.Tool.HAND
	return _tool[id]

static func tier_of(id: int) -> int:
	ensure_tables()
	if id < 0 or id >= _tier.size():
		return ToolDefs.Tier.ANY
	return _tier[id]

static func light_of(id: int) -> int:
	ensure_tables()
	if id < 0 or id >= _light.size():
		return 0
	return _light[id]

# Name of the block dropped when this block is harvested.  Blocks that drop
# themselves have an empty "drops" field in blocks.json.
static func drop_of(id: int) -> String:
	ensure_tables()
	if id < 0 or id >= _drops.size():
		return "Air"
	var drop: String = _drops[id]
	if drop.is_empty():
		return name_of(id)
	return drop

static func get_block_def(id: int) -> Dictionary:
	ensure_tables()
	if id < 0 or id >= _defs.size():
		return {}
	return _defs[id].duplicate(true)

static func get_block_types() -> Dictionary:
	ensure_tables()
	return block_types

static func get_block_names() -> Array:
	ensure_tables()
	return BLOCK_NAMES.duplicate()

# Blocks the player can select in the hotbar (everything except Air and the
# placeholder ids used to fill gaps).
static func get_placeable_block_names() -> Array:
	ensure_tables()
	var out: Array = []
	for i in BLOCK_NAMES.size():
		var block_name := String(BLOCK_NAMES[i])
		if i != AIR and not block_name.begins_with("Reserved_"):
			out.append(block_name)
	return out

static func get_flags() -> PackedByteArray:
	ensure_tables()
	return _flags

# Normalised top-left UV of every block face (see Side).
static func get_side_uv_table() -> PackedVector2Array:
	ensure_tables()
	return _side_uv

# ---------------------------------------------------------------------------
# Property helpers
# ---------------------------------------------------------------------------

static func is_transparent(id: int) -> bool:
	return (flags_of(id) & FLAG_TRANSPARENT) != 0

static func is_flat(id: int) -> bool:
	return (flags_of(id) & FLAG_FLAT) != 0

static func has_collision(id: int) -> bool:
	return id != AIR and (flags_of(id) & FLAG_NO_COLLISION) == 0

# True when the player can walk through the block (air, plants, liquids).
static func is_passable(id: int) -> bool:
	return id == AIR or (flags_of(id) & FLAG_NO_COLLISION) != 0

static func is_walkable_through(id: int) -> bool:
	return is_passable(id)

static func is_solid(id: int) -> bool:
	return has_collision(id)

static func is_liquid(id: int) -> bool:
	return (flags_of(id) & FLAG_LIQUID) != 0

static func is_replaceable(id: int) -> bool:
	return id == AIR or (flags_of(id) & FLAG_REPLACEABLE) != 0

# Seconds needed to mine the block with the given tool / tier.
static func break_time(id: int, tool: int, tool_tier: int) -> float:
	return ToolDefs.break_time(hardness_of(id), tool_of(id), tier_of(id), tool, tool_tier)

# True when the tool tier is high enough for the block to drop anything.
static func can_harvest(id: int, tool_tier: int) -> bool:
	return ToolDefs.can_harvest(tier_of(id), tool_tier)

# True when both the tool kind and its tier allow a drop.
#
# Blocks whose minimum tier is ANY (wood, dirt, plants...) drop with any tool,
# including the hand.  Blocks that need a real tool tier (stone = wood pickaxe)
# also require the matching tool kind.
static func can_harvest_with(id: int, tool: int, tool_tier: int) -> bool:
	if id == AIR:
		return false
	if not can_harvest(id, tool_tier):
		return false
	if tier_of(id) == ToolDefs.Tier.ANY:
		return true
	return ToolDefs.is_correct_tool(tool_of(id), tool)

# Normalised top-left UV of one face inside the runtime atlas.
static func side_uv(id: int, side: int) -> Vector2:
	get_side_uv_table()
	var slot := id * 7 + side
	if slot < 0 or slot >= _side_uv.size():
		return Vector2.ZERO
	return _side_uv[slot]
