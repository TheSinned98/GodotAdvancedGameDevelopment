class_name OceanBiome
extends BiomeGenerator

func generate(ctx: ChunkContext) -> void:
	ctx.ground.set_cells_terrain_connect(ctx.all_cells(), TERRAIN_SET, T_WATER, false)
