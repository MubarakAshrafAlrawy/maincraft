extends Node
class_name ChunkGenerator

static func generate_surface(height, x, y, z):
	if y == 0:
		return "Stone"
	else:
		return "Air"

static func generate_details(c, rng):
	return
