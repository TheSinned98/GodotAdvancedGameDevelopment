class_name BiomeGenerator
extends RefCounted

const SOURCE_ID := 0

# Terrain-IDs (Terrain Set 0), an dein TileSet anpassen
const TERRAIN_SET := 0
const T_SAND := 0
const T_WATER := 1
const T_GRASS := 2
const T_ROCK := 3      # NEU: Terrain "Fels" im TileSet anlegen (für Gebirge)

# Normale Tiles (Atlas-Koordinaten), ohne Autotiling
const TREE := Vector2i(15, 30)
const PINE := Vector2i(16, 30)
const CACTUS := Vector2i(2, 0)
const PALM := Vector2i(3, 0)
const SHELL := Vector2i(4, 0)
const DUNE := Vector2i(24, 24)
const SNOW: Array[Vector2i] = [Vector2i(5, 0), Vector2i(6, 0)]   # weiß, am besten teiltransparent
const BOULDER: Array[Vector2i] = [Vector2i(5, 3), Vector2i(8, 4)]
const FLOWERS: Array[Vector2i] = [Vector2i(1, 4), Vector2i(4, 4)]

var world_seed := 0


func _init(p_seed: int) -> void:
	world_seed = p_seed
	_setup()


func _setup() -> void:
	pass


func generate(_ctx: ChunkContext) -> void:
	pass
