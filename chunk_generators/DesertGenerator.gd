extends ChunkGenerator

static func generate_surface(height, x, y, z):
	var type
	if y < height - 10 or y == 0:
		type = "Stone"
	elif y <= height - 1:
		type = "Sand"
	else:
		type = "Air"
	return type

static func generate_details(c, rng):
	# Now generate cactus
	var cactus_width = 2
	for n_cactus in range(0, rng.randi_range(0, 3)):
		var x = rng.randi_range(cactus_width, c.DIMENSION.x - cactus_width - 1)
		var z = rng.randi_range(cactus_width, c.DIMENSION.z - cactus_width - 1)
		var base_y = c.get_ground_height(x, z)

		# Place a cactus at this position up to some height
		var cactus_height = rng.randi_range(5, 7)
		for i in range(0, cactus_height):
			c.set_block(x, base_y + i, z, "Cactus")

		# Place 1 branch per side
		var dir = Vector2(1, 0)
		if rng.randi() % 2:
			dir = Vector2(0, 1)
		for side in [dir, -dir]:
			var branch_height = rng.randi_range(3, cactus_height - 2)
			if rng.randi() % 2:
				# Just a nub
				c.set_block(x + int(side.x), base_y + branch_height, z + int(side.y), "Cactus")
			else:
				# Full branch
				for offset in [
					Vector3(side.x, 0, side.y),
					Vector3(2 * side.x, 0, 2 * side.y),
					Vector3(2 * side.x, 1, 2 * side.y)]:
						c.set_block(
							x + int(offset.x),
							base_y + branch_height + int(offset.y),
							z + int(offset.z),
							"Cactus",
							false
						)

	# Now some tufts of grass
	for n_shrub in range(0, rng.randi_range(0, 5)):
		var x = rng.randi_range(0, c.DIMENSION.x - 1)
		var z = rng.randi_range(0, c.DIMENSION.z - 1)
		c.set_block(x, c.get_ground_height(x, z), z, "Shrub", false)
