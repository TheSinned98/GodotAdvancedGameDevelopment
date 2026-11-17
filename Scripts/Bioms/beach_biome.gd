class_name BeachBiome
extends BiomeGenerator

var _coast := FastNoiseLite.new()


func _setup() -> void:
	_coast.seed = world_seed + 41
	_coast.frequency = 0.08


func generate(ctx: ChunkContext) -> void:
	var sea := ctx.world.sea_level
	var water_cells: Array[Vector2i] = []
	var sand_cells: Array[Vector2i] = []

	for cell in ctx.all_cells():
		var h := ctx.world.height_at_tile(cell)
		var wobble := _coast.get_noise_2d(cell.x, cell.y) * 0.012
		if h + wobble < sea + 0.012:
			water_cells.append(cell)
		else:
			sand_cells.append(cell)

	ctx.ground.set_cells_terrain_connect(water_cells, TERRAIN_SET, T_WATER, false)
	ctx.ground.set_cells_terrain_connect(sand_cells, TERRAIN_SET, T_SAND, false)

	for cell in sand_cells:
		var r := ctx.rng.randf()
		if r < 0.004:
			ctx.decoration.set_cell(cell, SOURCE_ID, PALM)
		elif r < 0.012:
			ctx.decoration.set_cell(cell, SOURCE_ID, SHELL)
