class_name MountainBiome
extends BiomeGenerator

var _rocks := FastNoiseLite.new()


func _setup() -> void:
	_rocks.seed = world_seed + 53
	_rocks.frequency = 0.12


func generate(ctx: ChunkContext) -> void:
	var cells := ctx.all_cells()
	ctx.ground.set_cells_terrain_connect(cells, TERRAIN_SET, T_ROCK, false)

	for cell in cells:
		# Felsbrocken in Gruppen
		if _rocks.get_noise_2d(cell.x, cell.y) > 0.25 and ctx.rng.randf() < 0.12:
			ctx.decoration.set_cell(cell, SOURCE_ID, ctx.pick(BOULDER))
			continue

		# Schnee: oberhalb der Gebirgsgrenze, je höher, desto dichter
		var h := ctx.world.height_at_tile(cell)
		var snow := clampf((h - ctx.world.mountain_level) / 0.12, 0.0, 1.0)
		if ctx.rng.randf() < snow * 0.8:
			ctx.decoration.set_cell(cell, SOURCE_ID, ctx.pick(SNOW))
