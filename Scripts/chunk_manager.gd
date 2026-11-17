extends Node2D

signal world_ready

@export var world_seed := 0                  # 0 = zufällig
@export var world_size := Vector2i(64, 64)   # in Chunks
@export var chunk_size := 32                 # Tiles pro Chunk-Seite
@export var load_radius := 2                 # Chunks um den Spieler
@export var chunks_per_frame := 2
@export var player: Node2D

@onready var ground: TileMapLayer = $Ground
@onready var decoration: TileMapLayer = $Decoration
@onready var overlay: TileMapLayer = $Overlay

var world := WorldData.new()
var generators: Dictionary = {}   # Biome -> BiomeGenerator
var loaded: Dictionary = {}       # Vector2i -> true
var _queue: Array[Vector2i] = []
var _player_chunk := Vector2i(-9999, -9999)


func _ready() -> void:
	if world_seed == 0:
		world_seed = randi()
	world.generate(world_seed, world_size, chunk_size)

	generators = {
	WorldData.Biome.OCEAN: OceanBiome.new(world_seed),
	WorldData.Biome.BEACH: BeachBiome.new(world_seed),
	WorldData.Biome.MOUNTAIN: MountainBiome.new(world_seed),
	WorldData.Biome.TUNDRA: TundraBiome.new(world_seed),
	WorldData.Biome.DESERT: DesertBiome.new(world_seed),
	WorldData.Biome.PLAINS: PlainsBiome.new(world_seed),
	WorldData.Biome.FOREST: ForestBiome.new(world_seed),
}
	world_ready.emit()


func _process(_delta: float) -> void:
	if player == null:
		return

	var chunk := _world_to_chunk(player.global_position)
	if chunk != _player_chunk:
		_player_chunk = chunk
		_refresh(chunk)

	# Chunks verteilt über mehrere Frames erzeugen, damit nichts ruckelt
	for i in chunks_per_frame:
		if _queue.is_empty():
			break
		_generate_chunk(_queue.pop_front())


# Für den Spielstart: alles um den Spieler sofort und synchron laden
func load_around_now() -> void:
	_player_chunk = _world_to_chunk(player.global_position)
	_refresh(_player_chunk)
	while not _queue.is_empty():
		_generate_chunk(_queue.pop_front())


func get_spawn_position_global() -> Vector2:
	var c := world.find_spawn_chunk()
	var tile := c * chunk_size + Vector2i(chunk_size, chunk_size) / 2
	return ground.to_global(ground.map_to_local(tile))


func _refresh(center: Vector2i) -> void:
	# Fehlende Chunks in die Warteschlange
	for dx in range(-load_radius, load_radius + 1):
		for dy in range(-load_radius, load_radius + 1):
			var c := center + Vector2i(dx, dy)
			if world.in_bounds(c) and not loaded.has(c) and not _queue.has(c):
				_queue.append(c)

	# Veraltete Einträge entfernen, nächste Chunks zuerst
	_queue.assign(_queue.filter(func(c: Vector2i) -> bool: return _dist(c, center) <= load_radius))
	_queue.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return Vector2(a - center).length_squared() < Vector2(b - center).length_squared())

	# Weit entfernte Chunks entladen (1 Chunk Puffer gegen Flackern)
	for c in loaded.keys():
		if _dist(c, center) > load_radius + 1:
			_unload_chunk(c)


func _generate_chunk(c: Vector2i) -> void:
	loaded[c] = true
	var origin := c * chunk_size

	# Zellen des Chunks nach Biom gruppieren
	var cells_by_biome: Dictionary = {}   # Biome -> Array[Vector2i]
	for x in chunk_size:
		for y in chunk_size:
			var cell := origin + Vector2i(x, y)
			if not world.tile_in_bounds(cell):
				continue
			var biome := world.biome_at_tile(cell)
			if not cells_by_biome.has(biome):
				var arr: Array[Vector2i] = []
				cells_by_biome[biome] = arr
			cells_by_biome[biome].append(cell)

	# Jedes Biom im Chunk mit seinem Generator und nur seinen Zellen
	for biome in cells_by_biome:
		var gen: BiomeGenerator = generators.get(biome)
		if gen == null:
			push_warning("Kein Generator für Biom %d (Chunk %s)" % [biome, c])
			continue

		var ctx := ChunkContext.new()
		ctx.chunk = c
		ctx.origin = origin
		ctx.size = chunk_size
		ctx.rng = RandomNumberGenerator.new()
		ctx.rng.seed = hash([world_seed, c.x, c.y, biome])
		ctx.cells = cells_by_biome[biome]
		ctx.world = world
		ctx.ground = ground
		ctx.overlay = overlay
		ctx.decoration = decoration
		gen.generate(ctx)
	



func _unload_chunk(c: Vector2i) -> void:
	var origin := c * chunk_size
	for x in chunk_size:
		for y in chunk_size:
			var cell := origin + Vector2i(x, y)
			ground.erase_cell(cell)
			overlay.erase_cell(cell)  
			decoration.erase_cell(cell)
	loaded.erase(c)


func _world_to_chunk(world_pos: Vector2) -> Vector2i:
	var tile := ground.local_to_map(ground.to_local(world_pos))
	return Vector2i(floori(tile.x / float(chunk_size)), floori(tile.y / float(chunk_size)))


func _dist(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))
