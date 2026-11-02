extends RefCounted

# ---------------------------------------------------------------------------
# Runtime texture atlas builder.
#
# Packs ship individual PNGs; this packs every referenced texture into one
# image so chunk meshes can keep using a single material and one draw call per
# chunk.  The grid is square-ish and UVs are returned as normalised top-left
# corners, which is what BlockRegistry stores per block face.
#
# Missing textures get a magenta/black checker tile instead of crashing or
# silently showing another block.
# ---------------------------------------------------------------------------

const MISSING_TEXTURE := "__missing"

# Returns:
#   {
#     "image": Image,
#     "uv": {texture_name: Vector2 top-left},
#     "cols": int, "rows": int,
#     "tile_size": int,
#     "size": Vector2i,
#   }
static func build(texture_paths: Dictionary, tile_size: int) -> Dictionary:
	tile_size = maxi(4, tile_size)

	var names: Array = texture_paths.keys()
	names.sort()
	if not names.has(MISSING_TEXTURE):
		names.append(MISSING_TEXTURE)

	var count := names.size()
	var cols := maxi(1, ceili(sqrt(float(count))))
	var rows := maxi(1, ceili(float(count) / float(cols)))
	var size := Vector2i(cols * tile_size, rows * tile_size)

	var atlas := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	atlas.fill(Color(0, 0, 0, 0))

	var uv := {}
	for i in count:
		var texture_name: String = names[i]
		var cell := Vector2i(i % cols, i / cols)
		var pixel_origin := cell * tile_size

		var image: Image
		if texture_name == MISSING_TEXTURE:
			image = _make_missing_tile(tile_size)
		else:
			image = _load_image(String(texture_paths.get(texture_name, "")), tile_size)

		if image == null:
			image = _make_missing_tile(tile_size)

		atlas.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), pixel_origin)
		uv[texture_name] = Vector2(float(pixel_origin.x), float(pixel_origin.y)) / Vector2(size)

	return {
		"image": atlas,
		"uv": uv,
		"cols": cols,
		"rows": rows,
		"tile_size": tile_size,
		"size": size,
	}

static func _load_image(path: String, tile_size: int) -> Image:
	if path.is_empty():
		return null

	var image: Image = Image.load_from_file(path)
	if image == null or image.is_empty():
		# Exported builds may only contain the imported resource, not the raw
		# file; fall back to the resource loader in that case.
		var resource = load(path)
		if resource is Texture2D:
			image = resource.get_image()
		else:
			push_warning("AtlasBuilder: could not load texture '%s'." % path)
			return null

	if image == null or image.is_empty():
		push_warning("AtlasBuilder: texture '%s' is empty." % path)
		return null

	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)

	if image.get_width() != tile_size or image.get_height() != tile_size:
		image.resize(tile_size, tile_size, Image.INTERPOLATE_NEAREST)

	return image

static func _make_missing_tile(tile_size: int) -> Image:
	var image := Image.create(tile_size, tile_size, false, Image.FORMAT_RGBA8)
	var square := maxi(1, tile_size / 4)
	for y in tile_size:
		for x in tile_size:
			var checker := ((x / square) + (y / square)) % 2 == 0
			image.set_pixel(x, y, Color(1, 0, 1) if checker else Color(0, 0, 0))
	return image
