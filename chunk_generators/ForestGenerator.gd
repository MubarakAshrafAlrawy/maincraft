extends ChunkGenerator

static func generate_surface(height, x, y, z):
	var type
	if y == height - 1:
		type = "Grass"
	elif y < height - 10 or y == 0:
		type = "Stone"
	elif y < height - 1:
		type = "Dirt"
	else:
		type = "Air"
	return type

static func generate_details(c, rng):
	# Now generate trees
	var tree_width = 2
	for n_tree in range(0, rng.randi_range(2, 8)):
		var pos_x = rng.randi_range(tree_width, c.DIMENSION.x - tree_width - 1)
		var pos_z = rng.randi_range(tree_width, c.DIMENSION.z - tree_width - 1)
		var base_y = c.get_ground_height(pos_x, pos_z)

		# Place a log at this position up to some height
		var tree_height = rng.randi_range(4, 8)
		for i in range(0, tree_height):
			c.set_block(pos_x, base_y + i, pos_z, "Log")
		# Place leaves
		var min_y = rng.randi_range(-2, -1)
		var max_y = rng.randi_range(2, 4)
		for dy in range(min_y, max_y):
			var leaf_width = tree_width
			if dy == min_y or dy == max_y - 1:
				leaf_width -= 1
			for dx in range(-leaf_width, leaf_width + 1):
				for dz in range(-leaf_width, leaf_width + 1):
					c.set_block(pos_x + dx, base_y + tree_height + dy, pos_z + dz, "Leaf", false)

	# Now some tufts of grass
	for n_shrub in range(0, rng.randi_range(6, 10)):
		var x = rng.randi_range(0, c.DIMENSION.x - 1)
		var z = rng.randi_range(0, c.DIMENSION.z - 1)
		c.set_block(x, c.get_ground_height(x, z), z, "Tall_Grass", false)

	for n_flower in range(0, rng.randi_range(4, 6)):
		var x = rng.randi_range(0, c.DIMENSION.x - 1)
		var z = rng.randi_range(0, c.DIMENSION.z - 1)
		c.set_block(x, c.get_ground_height(x, z), z, "Flower", false)
