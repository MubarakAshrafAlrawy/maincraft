extends RefCounted

# ---------------------------------------------------------------------------
# Content pack loader.
#
# A pack is any folder that contains a blocks.json and/or a textures/ folder:
#
#   res://content/<pack_name>/blocks.json
#   res://content/<pack_name>/pack.json          (optional manifest)
#   res://content/<pack_name>/textures/**.png
#
#   user://packs/<pack_name>/...                 (same layout, installed later)
#
# Packs are merged in order.  Later packs can:
#   * add new blocks (with an explicit free id or an automatic one),
#   * override a block with the same name,
#   * override a texture by dropping a file with the same texture name.
#
# Nothing here touches the scene tree or BlockRegistry, so it is safe to call
# from the main thread before the chunk workers start.
# ---------------------------------------------------------------------------

const ToolDefs = preload("res://ToolDefs.gd")

const CONTENT_DIR := "res://content"
const USER_PACKS_DIR := "user://packs"

const FLAG_TRANSPARENT := 1
const FLAG_PASSABLE := 2
const FLAG_FLAT := 4
const FLAG_LIQUID := 8
const FLAG_REPLACEABLE := 16

const FLAG_NAMES := {
	"transparent": FLAG_TRANSPARENT,
	"passable": FLAG_PASSABLE,
	"no_collision": FLAG_PASSABLE,
	"flat": FLAG_FLAT,
	"liquid": FLAG_LIQUID,
	"replaceable": FLAG_REPLACEABLE,
}

const TOOL_IDS := {
	"hand": ToolDefs.Tool.HAND,
	"pickaxe": ToolDefs.Tool.PICKAXE,
	"axe": ToolDefs.Tool.AXE,
	"shovel": ToolDefs.Tool.SHOVEL,
	"sword": ToolDefs.Tool.SWORD,
	"shears": ToolDefs.Tool.SHEARS,
	"hoe": ToolDefs.Tool.HOE,
}

const TIER_IDS := {
	"any": ToolDefs.Tier.ANY,
	"wood": ToolDefs.Tier.WOOD,
	"stone": ToolDefs.Tier.STONE,
	"iron": ToolDefs.Tier.IRON,
	"gold": ToolDefs.Tier.GOLD,
	"diamond": ToolDefs.Tier.DIAMOND,
	"netherite": ToolDefs.Tier.NETHERITE,
}

const TEXTURE_EXTENSIONS := ["png", "webp", "jpg", "jpeg", "tga"]

# Used only when no pack provides any block at all, so the game still boots
# with a readable error instead of crashing on an empty registry.
const FALLBACK_BLOCKS := [
	{"name": "Air", "flags": FLAG_TRANSPARENT | FLAG_PASSABLE | FLAG_REPLACEABLE, "hardness": 0.0},
	{"name": "Dirt", "flags": 0, "hardness": 0.5, "tool": "shovel"},
	{"name": "Grass", "flags": 0, "hardness": 0.6, "tool": "shovel", "drops": "Dirt"},
	{"name": "Stone", "flags": 0, "hardness": 1.5, "tool": "pickaxe", "tier": "wood"},
	{"name": "Log", "flags": 0, "hardness": 2.0, "tool": "axe"},
	{"name": "Leaf", "flags": FLAG_TRANSPARENT, "hardness": 0.2},
	{"name": "Tall_Grass", "flags": FLAG_TRANSPARENT | FLAG_PASSABLE | FLAG_FLAT | FLAG_REPLACEABLE, "hardness": 0.0},
	{"name": "Flower", "flags": FLAG_TRANSPARENT | FLAG_PASSABLE | FLAG_FLAT | FLAG_REPLACEABLE, "hardness": 0.0},
]

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

# Returns:
#   {
#     "blocks":   [canonical block dictionaries, index == id],
#     "textures": {texture_name: absolute_path_or_empty},
#     "tile_size": int,
#     "packs":    [pack folder paths],
#   }
static func build() -> Dictionary:
	var packs := _find_packs()
	var texture_paths := {}
	var entries: Array = []
	var tile_size := 16

	for pack in packs:
		var dir: String = pack["dir"]
		var manifest: Dictionary = pack["manifest"]

		if int(manifest.get("order", 0)) == 0 and manifest.has("tile_size"):
			tile_size = maxi(4, int(manifest["tile_size"]))

		_scan_textures(dir.path_join("textures"), texture_paths)
		_collect_blocks(dir, manifest, entries)

	var blocks := _merge_blocks(entries)
	if blocks.is_empty():
		push_error("ContentLoader: no blocks found in any pack, using the built-in fallback.")
		blocks = _fallback_blocks()

	var textures := _resolve_textures(blocks, texture_paths)

	return {
		"blocks": blocks,
		"textures": textures,
		"tile_size": tile_size,
		"packs": packs.map(func(p): return p["dir"]),
	}

# ---------------------------------------------------------------------------
# Pack discovery
# ---------------------------------------------------------------------------

static func _find_packs() -> Array:
	var packs: Array = []
	_make_user_packs_dir()

	for root in [CONTENT_DIR, USER_PACKS_DIR]:
		var dir_access := DirAccess.open(root)
		if dir_access == null:
			continue

		var is_user: bool = root == USER_PACKS_DIR
		var subdirs := dir_access.get_directories()
		subdirs.sort()
		for subdir in subdirs:
			var dir: String = root.path_join(subdir)
			var manifest = _read_json(dir.path_join("pack.json"))
			if not manifest is Dictionary:
				manifest = {}
			var has_blocks := FileAccess.file_exists(dir.path_join("blocks.json"))
			var has_textures := DirAccess.dir_exists_absolute(dir.path_join("textures"))
			if not has_blocks and not has_textures:
				continue
			packs.append({
				"dir": dir,
				"manifest": manifest,
				"is_user": is_user,
			})

	packs.sort_custom(func(a, b) -> bool:
		var order_a := int(a["manifest"].get("order", 1000 if a["is_user"] else 0))
		var order_b := int(b["manifest"].get("order", 1000 if b["is_user"] else 0))
		if order_a == order_b:
			return String(a["dir"]) < String(b["dir"])
		return order_a < order_b
	)

	return packs

static func _make_user_packs_dir() -> void:
	if not DirAccess.dir_exists_absolute(USER_PACKS_DIR):
		DirAccess.make_dir_recursive_absolute(USER_PACKS_DIR)

	var readme := USER_PACKS_DIR.path_join("README.txt")
	if not FileAccess.file_exists(readme):
		var file := FileAccess.open(readme, FileAccess.WRITE)
		if file != null:
			file.store_string(
				"maincraft content packs\n"
				+ "============================\n\n"
				+ "Put each pack in its own folder here:\n"
				+ "  user://packs/my_pack/blocks.json\n"
				+ "  user://packs/my_pack/pack.json\n"
				+ "  user://packs/my_pack/textures/stone.png\n\n"
				+ "Packs in res://content are loaded first; these user packs load after them,\n"
				+ "so they can add blocks or override textures/blocks with the same name.\n"
			)
			file.close()

# ---------------------------------------------------------------------------
# Textures
# ---------------------------------------------------------------------------

static func _scan_textures(dir: String, out: Dictionary) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	_scan_texture_dir(dir, "", out)

static func _scan_texture_dir(dir: String, prefix: String, out: Dictionary) -> void:
	var dir_access := DirAccess.open(dir)
	if dir_access == null:
		return

	var files := dir_access.get_files()
	files.sort()
	for file in files:
		var ext := file.get_extension().to_lower()
		if not TEXTURE_EXTENSIONS.has(ext):
			continue
		var relative := file if prefix.is_empty() else prefix + "/" + file
		var texture_name := relative.get_basename()
		var path := dir.path_join(file)
		out[texture_name] = path
		# A short alias lets JSON say "stone" even when the file lives in a
		# subfolder.  Later packs override earlier ones on purpose.
		out[file.get_basename()] = path

	var subdirs := dir_access.get_directories()
	subdirs.sort()
	for subdir in subdirs:
		var next_prefix := subdir if prefix.is_empty() else prefix + "/" + subdir
		_scan_texture_dir(dir.path_join(subdir), next_prefix, out)

# Keeps only the textures actually referenced by blocks, and flags missing ones
# with an empty path so the atlas builder can draw a checker tile.
static func _resolve_textures(blocks: Array, texture_paths: Dictionary) -> Dictionary:
	var used := {}
	var missing := false

	for block in blocks:
		var textures: Dictionary = block["textures"]
		for key in textures:
			var name := String(textures[key])
			if name.is_empty():
				continue
			if used.has(name):
				continue
			if texture_paths.has(name):
				used[name] = String(texture_paths[name])
			else:
				push_warning("ContentLoader: missing texture '%s' (used by block '%s')." % [name, block["name"]])
				missing = true

	if missing or used.is_empty():
		used["__missing"] = ""
	return used

# ---------------------------------------------------------------------------
# Block collection
# ---------------------------------------------------------------------------

static func _collect_blocks(dir: String, manifest: Dictionary, entries: Array) -> void:
	var blocks_file := String(manifest.get("blocks", "blocks.json"))
	var path := dir.path_join(blocks_file)
	if not FileAccess.file_exists(path):
		return

	var data = _read_json(path)
	if data == null:
		return

	var list: Array
	if data is Array:
		list = data
	elif data is Dictionary:
		list = data.get("blocks", [])
	else:
		push_error("ContentLoader: %s must contain an array or a 'blocks' array." % path)
		return

	for index in list.size():
		var raw = list[index]
		if not raw is Dictionary:
			push_error("ContentLoader: %s block #%d is not an object." % [path, index])
			continue
		var name := String(raw.get("name", "")).strip_edges()
		if name.is_empty():
			push_error("ContentLoader: %s block #%d has no name." % [path, index])
			continue

		var fixed_id = raw.get("id", null)
		entries.append({
			"name": name,
			"id": null if fixed_id == null else int(fixed_id),
			"raw": raw,
			"pack": dir,
		})

# ---------------------------------------------------------------------------
# Merge / id assignment
# ---------------------------------------------------------------------------

static func _merge_blocks(entries: Array) -> Array:
	var by_id := {}
	var id_by_name := {}
	var reserved := {}

	# Reserve explicit ids first so auto ids never steal a slot another pack
	# already declared.
	for entry in entries:
		if entry["id"] != null and int(entry["id"]) >= 0:
			reserved[int(entry["id"])] = true

	var next_auto := 1

	for entry in entries:
		var name: String = entry["name"]
		var fixed: int = -1 if entry["id"] == null else int(entry["id"])

		if fixed >= 0:
			if by_id.has(fixed) and String(by_id[fixed]["name"]) != name:
				push_error("ContentLoader: block id %d is already used by '%s'; '%s' was skipped."
					% [fixed, by_id[fixed]["name"], name])
				continue
			if id_by_name.has(name) and int(id_by_name[name]) != fixed:
				push_error("ContentLoader: '%s' already has id %d; the new id %d was ignored."
					% [name, id_by_name[name], fixed])
				fixed = int(id_by_name[name])
		elif id_by_name.has(name):
			fixed = int(id_by_name[name])
		else:
			while by_id.has(next_auto) or reserved.has(next_auto):
				next_auto += 1
			fixed = next_auto
			next_auto += 1

		by_id[fixed] = _canonical_block(entry["raw"], fixed, name, entry["pack"])
		id_by_name[name] = fixed

	# Air must always be id 0: the chunk data is cleared to 0.
	if by_id.has(0) and String(by_id[0]["name"]) != "Air":
		push_error("ContentLoader: id 0 must be Air; '%s' was replaced." % by_id[0]["name"])
		by_id.erase(0)
	if not by_id.has(0):
		by_id[0] = _canonical_block({"name": "Air"}, 0, "Air", "")

	# Fill gaps so array index == block id.
	var max_id := 0
	for id in by_id:
		max_id = maxi(max_id, int(id))

	var blocks: Array = []
	for id in range(max_id + 1):
		if by_id.has(id):
			blocks.append(by_id[id])
		else:
			blocks.append(_reserved_block(id))
	return blocks

static func _canonical_block(raw: Dictionary, id: int, name: String, pack: String) -> Dictionary:
	var flags := _parse_flags(raw)
	var tool := _parse_enum(raw.get("tool", "hand"), TOOL_IDS, ToolDefs.Tool.HAND, "tool", name)
	var tier := _parse_enum(raw.get("tier", "any"), TIER_IDS, ToolDefs.Tier.ANY, "tier", name)

	var drops := ""
	if raw.has("drops") and raw["drops"] != null:
		drops = String(raw["drops"])

	var textures := _parse_textures(raw.get("textures", {}), name)
	# Convenience for quick packs: a block with no textures entry looks for
	# textures/<lower-case name>.png.
	if textures.is_empty() and name != "Air":
		textures = {"all": name.to_lower()}

	return {
		"id": id,
		"name": name,
		"flags": flags,
		"hardness": maxf(0.0, float(raw.get("hardness", 0.0))),
		"tool": tool,
		"tier": tier,
		"drops": drops,
		"light": clampi(int(raw.get("light", 0)), 0, 15),
		"textures": textures,
		"source": pack,
	}

static func _parse_flags(raw: Dictionary) -> int:
	var flags := 0

	for key in FLAG_NAMES:
		if bool(raw.get(key, false)):
			flags |= int(FLAG_NAMES[key])

	var extra = raw.get("flags", null)
	if extra is int or extra is float:
		flags |= int(extra)
	elif extra is Array:
		for flag_name in extra:
			var key := String(flag_name).to_lower()
			if FLAG_NAMES.has(key):
				flags |= int(FLAG_NAMES[key])
			else:
				push_warning("ContentLoader: unknown flag '%s'." % flag_name)
	elif extra != null:
		push_warning("ContentLoader: 'flags' must be an array of names or a numeric mask.")

	return flags

static func _parse_enum(value, table: Dictionary, fallback: int, kind: String, block_name: String) -> int:
	var key := String(value).to_lower()
	if table.has(key):
		return int(table[key])
	push_warning("ContentLoader: unknown %s '%s' on block '%s'; using the default." % [kind, value, block_name])
	return fallback

static func _parse_textures(value, block_name: String) -> Dictionary:
	if value is String:
		return {"all": String(value)}
	if not value is Dictionary:
		return {}

	var out := {}
	for key in value:
		out[String(key).to_lower()] = String(value[key])

	# Convenience: a block with no explicit "all" falls back to its lower-case
	# name, so textures/stone.png + "name": "Stone" just works.
	var has_face := false
	for key in ["all", "only", "top", "bottom", "side", "left", "right", "front", "back"]:
		if out.has(key):
			has_face = true
			break
	if not has_face and not out.is_empty():
		push_warning("ContentLoader: block '%s' has unknown texture keys; expected all/top/bottom/side/..." % block_name)
	return out

static func _reserved_block(id: int) -> Dictionary:
	return {
		"id": id,
		"name": "Reserved_%d" % id,
		"flags": FLAG_TRANSPARENT | FLAG_PASSABLE | FLAG_REPLACEABLE,
		"hardness": 0.0,
		"tool": ToolDefs.Tool.HAND,
		"tier": ToolDefs.Tier.ANY,
		"drops": "",
		"light": 0,
		"textures": {},
		"source": "",
	}

static func _fallback_blocks() -> Array:
	var out: Array = []
	for i in FALLBACK_BLOCKS.size():
		out.append(_canonical_block(FALLBACK_BLOCKS[i], i, String(FALLBACK_BLOCKS[i]["name"]), ""))
	return out

# ---------------------------------------------------------------------------
# JSON helper
# ---------------------------------------------------------------------------

static func _read_json(path: String):
	if not FileAccess.file_exists(path):
		return null

	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		push_error("ContentLoader: %s:%d %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data
