class_name GrasslandBiome
extends BiomeGenerator

enum Kind { WATER, SAND, GRASS }

# Unterklassen setzen diese Werte in _configure()
var water_level := -0.40     # Noise darunter: Wasser
var grass_level := -0.30     # Noise darüber: Gras, dazwischen Sandufer
var lake_frequency := 0.05
var seed_offset := 31

var _lakes := FastNoiseLite.new()


func _setup() -> void:
	_configure()
	_lakes.seed = world_seed + seed_offset
	_lakes.frequency = lake_frequency


func _configure() -> void:
	pass


func generate(ctx: ChunkContext) -> void:
	var water_cells: Array[Vector2i] = []
	var sand_cells: Array[Vector2i] = []
	var grass_cells: Array[Vector2i] = []
	var kinds: Dictionary = {}   # Zelle -> Kind

	for cell in ctx.all_cells():
		var h := _lakes.get_noise_2d(cell.x, cell.y)   # globale Koordinaten
		if h <= water_level:
			water_cells.append(cell)
			kinds[cell] = Kind.WATER
		else:
			sand_cells.append(cell)
			if h > grass_level:
				grass_cells.append(cell)
				kinds[cell] = Kind.GRASS
			else:
				kinds[cell] = Kind.SAND

	ctx.ground.set_cells_terrain_connect(water_cells, TERRAIN_SET, T_WATER, false)
	ctx.ground.set_cells_terrain_connect(sand_cells, TERRAIN_SET, T_SAND, false)
	ctx.overlay.set_cells_terrain_connect(grass_cells, TERRAIN_SET, T_GRASS, false)

	_decorate(ctx, kinds)


# Überschreiben: Bäume, Blumen, Schnee usw. auf die Decoration-Ebene setzen
func _decorate(_ctx: ChunkContext, _kinds: Dictionary) -> void:
	pass
