class_name ForestBiome
extends GrasslandBiome

# Als Variablen, damit die Tundra sie anpassen kann
var tree_tile := TREE
var tree_chance_min := 0.06
var tree_chance_max := 0.28
var cluster_threshold := -0.10   # Noise darüber: Baumgruppe möglich

var _clusters := FastNoiseLite.new()


func _configure() -> void:
	water_level = -0.30      # größere Seen als in der Ebene
	grass_level = -0.20
	lake_frequency = 0.04
	seed_offset = 11


func _setup() -> void:
	super()
	_clusters.seed = world_seed + 12
	_clusters.frequency = 0.07


func _decorate(ctx: ChunkContext, kinds: Dictionary) -> void:
	for cell in ctx.all_cells():
		if kinds[cell] != Kind.GRASS:
			continue
		# Dichte hängt von der Vegetation an genau diesem Tile ab
		var veg := ctx.world.vegetation_at_tile(cell)
		var chance := lerpf(tree_chance_min, tree_chance_max, veg)
		if _clusters.get_noise_2d(cell.x, cell.y) > cluster_threshold \
				and ctx.rng.randf() < chance:
			ctx.decoration.set_cell(cell, SOURCE_ID, tree_tile)
