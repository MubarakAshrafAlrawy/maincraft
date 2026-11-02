extends RefCounted

# ---------------------------------------------------------------------------
# Command registry.
#
# This is deliberately a plain object owned by the world (not an autoload), so
# a future LAN server can give every hosted world its own command host and call
# execute() from an RPC instead of from the local console.
#
#   var registry = CommandRegistry.new(world, player, caller_permission)
#   registry.execute("/give Stone 8")
#
# Permission levels: 0 = normal player, 2 = host / operator.
# ---------------------------------------------------------------------------

const Registry = preload("res://BlockRegistry.gd")

const PERMISSION_PLAYER := 0
const PERMISSION_ADMIN := 2

const COMMANDS := {
	"help": {
		"usage": "/help [command]",
		"description": "List every command, or explain one.",
		"permission": PERMISSION_PLAYER,
	},
	"pos": {
		"usage": "/pos",
		"description": "Print your world position and chunk.",
		"permission": PERMISSION_PLAYER,
	},
	"chunks": {
		"usage": "/chunks",
		"description": "Print streamer / loaded chunk stats.",
		"permission": PERMISSION_PLAYER,
	},
	"give": {
		"usage": "/give <block> [count]",
		"description": "Add blocks to the inventory.",
		"permission": PERMISSION_ADMIN,
	},
	"clear": {
		"usage": "/clear",
		"description": "Empty the whole inventory.",
		"permission": PERMISSION_ADMIN,
	},
	"tp": {
		"usage": "/tp <x> <y> <z>",
		"description": "Teleport to world coordinates.",
		"permission": PERMISSION_ADMIN,
	},
	"spawn": {
		"usage": "/spawn",
		"description": "Teleport back to the world spawn.",
		"permission": PERMISSION_ADMIN,
	},
	"renderdistance": {
		"usage": "/renderdistance [2-10]",
		"description": "Read or change the render distance.",
		"permission": PERMISSION_ADMIN,
	},
	"fov": {
		"usage": "/fov [50-110]",
		"description": "Read or change the field of view.",
		"permission": PERMISSION_ADMIN,
	},
}

var world = null
var player = null
var caller_permission := PERMISSION_ADMIN

func _init(world_ref = null, player_ref = null, permission := PERMISSION_ADMIN) -> void:
	world = world_ref
	player = player_ref
	caller_permission = permission

# ---------------------------------------------------------------------------
# Execution
# ---------------------------------------------------------------------------

# Returns an array of { "text": String, "error": bool } lines.
func execute(line: String) -> Array:
	var text := String(line).strip_edges()
	if text.begins_with("/"):
		text = text.substr(1).strip_edges()
	if text.is_empty():
		return []

	var tokens := _tokenize(text)
	if tokens.is_empty():
		return []

	var command := String(tokens[0]).to_lower()
	if not COMMANDS.has(command):
		return [_error("Unknown command '%s'. Type /help." % command)]

	if int(COMMANDS[command].get("permission", PERMISSION_PLAYER)) > caller_permission:
		return [_error("You do not have permission to use /%s." % command)]

	var args := tokens.slice(1)
	match command:
		"help":
			return _cmd_help(args)
		"pos":
			return _cmd_pos(args)
		"chunks":
			return _cmd_chunks(args)
		"give":
			return _cmd_give(args)
		"clear":
			return _cmd_clear(args)
		"tp":
			return _cmd_tp(args)
		"spawn":
			return _cmd_spawn(args)
		"renderdistance":
			return _cmd_render_distance(args)
		"fov":
			return _cmd_fov(args)

	return [_error("Command '%s' has no handler." % command)]

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

func _cmd_help(args: Array) -> Array:
	if not args.is_empty():
		var name := String(args[0]).to_lower().trim_prefix("/")
		if not COMMANDS.has(name):
			return [_error("Unknown command '%s'." % name)]
		var entry: Dictionary = COMMANDS[name]
		return [_ok("%s\n%s" % [entry["usage"], entry["description"]])]

	var lines: Array[String] = []
	lines.append("Commands (%d):" % COMMANDS.size())
	var names := COMMANDS.keys()
	names.sort()
	for name in names:
		var entry: Dictionary = COMMANDS[name]
		lines.append(String(entry["usage"]).rpad(30) + String(entry["description"]))
	return [_ok("\n".join(lines))]

func _cmd_pos(_args: Array) -> Array:
	if player == null:
		return [_error("No player is loaded.")]
	var dim := Registry.DIMENSION
	var cx := int(floor(player.position.x / dim.x))
	var cz := int(floor(player.position.z / dim.z))
	return [_ok("Position: %.2f %.2f %.2f  (chunk %d, %d)"
		% [player.position.x, player.position.y, player.position.z, cx, cz])]

func _cmd_chunks(_args: Array) -> Array:
	if world == null or world.pw == null:
		return [_error("The world is not ready yet.")]
	var center: Vector2i = world.chunk_pos
	return [_ok("Loaded chunks: %d  ·  center (%d, %d)  ·  radius %d"
		% [world.pw.get_loaded_chunk_count(), center.x, center.y, world.pw.load_radius])]

func _cmd_give(args: Array) -> Array:
	if player == null:
		return [_error("No player is loaded.")]
	if args.is_empty():
		return [_error("Usage: /give <block> [count]")]

	var block_name := _find_block(String(args[0]))
	if block_name.is_empty():
		var matches := _block_matches(String(args[0]), 6)
		if matches.is_empty():
			return [_error("Unknown block '%s'." % args[0])]
		return [_error("Unknown block '%s'. Did you mean: %s?" % [args[0], ", ".join(matches)])]

	var count := 1
	if args.size() >= 2:
		if not String(args[1]).is_valid_int():
			return [_error("Count must be a whole number.")]
		count = clampi(int(args[1]), 1, 4096)

	player.inventory.add_block(block_name, count)
	return [_ok("Gave %d x %s." % [count, block_name])]

func _cmd_clear(_args: Array) -> Array:
	if player == null:
		return [_error("No player is loaded.")]
	player.inventory.clear()
	return [_ok("Inventory cleared.")]

func _cmd_tp(args: Array) -> Array:
	if player == null:
		return [_error("No player is loaded.")]
	if args.size() != 3:
		return [_error("Usage: /tp <x> <y> <z>")]

	for value in args:
		if not String(value).is_valid_float():
			return [_error("Coordinates must be numbers.")]

	player.position = Vector3(float(args[0]), float(args[1]), float(args[2]))
	player.velocity = Vector3.ZERO
	return [_ok("Teleported to %.2f %.2f %.2f" % [player.position.x, player.position.y, player.position.z])]

func _cmd_spawn(_args: Array) -> Array:
	if player == null or world == null:
		return [_error("No player is loaded.")]
	player.position = world.get_spawn_position()
	player.velocity = Vector3.ZERO
	return [_ok("Returned to spawn at %.2f %.2f %.2f"
		% [player.position.x, player.position.y, player.position.z])]

func _cmd_render_distance(args: Array) -> Array:
	if args.is_empty():
		return [_ok("Render distance: %d (range %d-%d)."
			% [Settings.render_distance, Settings.MIN_RENDER_DISTANCE, Settings.MAX_RENDER_DISTANCE])]
	if not String(args[0]).is_valid_int():
		return [_error("Usage: /renderdistance <2-10>")]
	var value := int(args[0])
	if value < Settings.MIN_RENDER_DISTANCE or value > Settings.MAX_RENDER_DISTANCE:
		return [_error("Render distance must be between %d and %d."
			% [Settings.MIN_RENDER_DISTANCE, Settings.MAX_RENDER_DISTANCE])]
	Settings.set_render_distance(value)
	return [_ok("Render distance set to %d." % Settings.render_distance)]

func _cmd_fov(args: Array) -> Array:
	if args.is_empty():
		return [_ok("Field of view: %d (range %d-%d)." % [Settings.fov, Settings.MIN_FOV, Settings.MAX_FOV])]
	if not String(args[0]).is_valid_int():
		return [_error("Usage: /fov <50-110>")]
	var value := int(args[0])
	if value < Settings.MIN_FOV or value > Settings.MAX_FOV:
		return [_error("Field of view must be between %d and %d." % [Settings.MIN_FOV, Settings.MAX_FOV])]
	Settings.set_fov(value)
	return [_ok("Field of view set to %d." % Settings.fov)]

# ---------------------------------------------------------------------------
# Autocomplete
# ---------------------------------------------------------------------------

# Returns full replacement strings, e.g. "/give Stone".
func get_completions(text: String) -> Array:
	var raw := String(text).strip_edges()
	if raw.begins_with("/"):
		raw = raw.substr(1)
	if raw.is_empty():
		return _command_completions("")

	if not raw.contains(" "):
		return _command_completions(raw.to_lower())

	var tokens := raw.split(" ", false)
	var command := String(tokens[0]).to_lower()
	if command == "give":
		var prefix := String(tokens[1]) if tokens.size() >= 2 else ""
		var out: Array = []
		for block_name in Registry.get_placeable_block_names():
			if String(block_name).to_lower().begins_with(prefix.to_lower()):
				out.append("/give " + String(block_name))
		return out
	return []

func _command_completions(prefix: String) -> Array:
	var out: Array = []
	var names := COMMANDS.keys()
	names.sort()
	for name in names:
		if String(name).begins_with(prefix):
			out.append("/" + String(name))
	return out

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _find_block(query: String) -> String:
	var lower := query.to_lower()
	for block_name in Registry.get_placeable_block_names():
		if String(block_name).to_lower() == lower:
			return String(block_name)

	var matches := _block_matches(query, 2)
	if matches.size() == 1:
		return matches[0]
	return ""

func _block_matches(prefix: String, limit: int) -> Array:
	var lower := prefix.to_lower()
	var out: Array = []
	for block_name in Registry.get_placeable_block_names():
		if String(block_name).to_lower().begins_with(lower):
			out.append(String(block_name))
			if out.size() >= limit:
				break
	return out

func _tokenize(text: String) -> Array:
	var tokens: Array = []
	var current := ""
	var in_quotes := false

	for i in text.length():
		var character := text[i]
		if character == '"':
			in_quotes = not in_quotes
			continue
		if character == " " and not in_quotes:
			if not current.is_empty():
				tokens.append(current)
				current = ""
			continue
		current += character

	if not current.is_empty():
		tokens.append(current)
	return tokens

func _ok(text: String) -> Dictionary:
	return {"text": text, "error": false}

func _error(text: String) -> Dictionary:
	return {"text": text, "error": true}
