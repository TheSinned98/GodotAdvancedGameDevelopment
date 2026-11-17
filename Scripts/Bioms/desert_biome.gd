class_name DesertBiome
extends BiomeGenerator

const OASIS_GRID := 48           # Kantenlänge der Rasterzellen in Tiles
const OASIS_MIN_RADIUS := 3      # Wasserradius
const OASIS_MAX_RADIUS := 6
const OASIS_CHANCE := 0.30

enum Zone { NONE, WATER, SHORE, GRASS }

var _dunes := FastNoiseLite.new()
var _wobble := FastNoiseLite.new()
var _oasis_cache: Dictionary = {}   # Rasterzelle -> Vector3i(x, y, Radius), Radius 0 = keine Oase


func _setup() -> void:
	_dunes.seed = world_seed + 23
	_dunes.frequency = 0.04
	_wobble.seed = world_seed + 29
	_wobble.frequency = 0.15


func generate(ctx: ChunkContext) -> void:
	var water_cells: Array[Vector2i] = []
	var sand_cells: Array[Vector2i] = []
	var grass_cells: Array[Vector2i] = []
	var zones: Dictionary = {}

	for cell in ctx.all_cells():
		var zone := _oasis_zone(cell, ctx.world)
		zones[cell] = zone
		if zone == Zone.WATER:
			water_cells.append(cell)
		else:
			sand_cells.append(cell)
		if zone == Zone.GRASS:
			grass_cells.append(cell)

	ctx.ground.set_cells_terrain_connect(water_cells, TERRAIN_SET, T_WATER, false)
	ctx.ground.set_cells_terrain_connect(sand_cells, TERRAIN_SET, T_SAND, false)
	ctx.overlay.set_cells_terrain_connect(grass_cells, TERRAIN_SET, T_GRASS, false)

	for cell in ctx.all_cells():
		match zones[cell]:
			Zone.NONE:
				# Dünenkämme: schmale Bänder um den Noise-Wert 0
				if absf(_dunes.get_noise_2d(cell.x, cell.y)) < 0.06:
					ctx.overlay.set_cell(cell, SOURCE_ID, DUNE)
				elif ctx.rng.randf() < 0.004:
					ctx.decoration.set_cell(cell, SOURCE_ID, CACTUS)
			Zone.GRASS:
				if ctx.rng.randf() < 0.15:
					ctx.decoration.set_cell(cell, SOURCE_ID, PALM)


func _oasis_zone(cell: Vector2i, world: WorldData) -> int:
	var grid := Vector2i(
		floori(cell.x / float(OASIS_GRID)),
		floori(cell.y / float(OASIS_GRID)))
	var o := _oasis_for(grid, world)
	if o.z == 0:
		return Zone.NONE

	# Abstand zum Mittelpunkt, durch Noise verzerrt, damit der Rand unregelmäßig wird
	var d := Vector2(cell.x - o.x, cell.y - o.y).length()
	d += _wobble.get_noise_2d(cell.x, cell.y) * 2.0

	var r := float(o.z)
	if d < r:
		return Zone.WATER
	if d < r + 1.5:
		return Zone.SHORE    # Sandufer, bleibt frei von Deko
	if d < r + 4.0:
		return Zone.GRASS
	return Zone.NONE


func _oasis_for(grid: Vector2i, world: WorldData) -> Vector3i:
	if _oasis_cache.has(grid):
		return _oasis_cache[grid]

	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_seed, grid.x, grid.y, 77])

	# Rand lassen, damit die Oase komplett in der Rasterzelle liegt
	var margin := OASIS_MAX_RADIUS + 6
	var center := Vector2i(
		grid.x * OASIS_GRID + rng.randi_range(margin, OASIS_GRID - margin),
		grid.y * OASIS_GRID + rng.randi_range(margin, OASIS_GRID - margin))
	var radius := rng.randi_range(OASIS_MIN_RADIUS, OASIS_MAX_RADIUS)
	var roll := rng.randf()

	var result := Vector3i.ZERO
	# Nur, wenn der Mittelpunkt wirklich in der Wüste liegt
	if world.tile_in_bounds(center) \
			and world.biome_at_tile(center) == WorldData.Biome.DESERT:
		# Wüste hat Vegetation < 0.5, daher auf 0..1 strecken
		var veg := clampf(world.vegetation_at_tile(center) * 2.0, 0.0, 1.0)
		var chance := lerpf(OASIS_CHANCE * 0.5, OASIS_CHANCE * 1.5, veg)
		if roll < chance:
			result = Vector3i(center.x, center.y, radius)

	_oasis_cache[grid] = result
	return result
