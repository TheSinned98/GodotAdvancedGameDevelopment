class_name TundraBiome
extends ForestBiome

const SNOW_TEMP := 0.30         # entspricht der Tundra-Grenze in WorldData._classify()
const MAX_SNOW_CHANCE := 0.85   # Schneeanteil bei Temperatur 0


func _configure() -> void:
	super()
	water_level = -0.38          # kleine Seen
	grass_level = -0.28
	seed_offset = 61
	tree_tile = PINE
	tree_chance_min = 0.02
	tree_chance_max = 0.10


func _decorate(ctx: ChunkContext, kinds: Dictionary) -> void:
	super(ctx, kinds)   # Bäume wie im Wald

	for cell in ctx.all_cells():
		if kinds[cell] == Kind.WATER:
			continue
		if ctx.decoration.get_cell_source_id(cell) != -1:
			continue    # hier steht schon ein Baum

		# Je kälter das Tile, desto größer die Schneechance
		var t := ctx.world.temperature_at_tile(cell)
		var cold := clampf((SNOW_TEMP - t) / SNOW_TEMP, 0.0, 1.0)
		if ctx.rng.randf() < cold * MAX_SNOW_CHANCE:
			ctx.decoration.set_cell(cell, SOURCE_ID, ctx.pick(SNOW))
