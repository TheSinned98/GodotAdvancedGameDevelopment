class_name PlainsBiome
extends GrasslandBiome

const TREE_CHANCE := 0.004


func _configure() -> void:
	water_level = -0.40      # kleine Teiche
	grass_level = -0.30
	lake_frequency = 0.05
	seed_offset = 31


func _decorate(ctx: ChunkContext, kinds: Dictionary) -> void:
	for cell in ctx.all_cells():
		if kinds[cell] != Kind.GRASS:
			continue
		var flower_chance := lerpf(0.01, 0.05, ctx.world.vegetation_at_tile(cell))
		var r := ctx.rng.randf()
		if r < TREE_CHANCE:
			ctx.decoration.set_cell(cell, SOURCE_ID, TREE)
		elif r < TREE_CHANCE + flower_chance:
			ctx.decoration.set_cell(cell, SOURCE_ID, ctx.pick(FLOWERS))
