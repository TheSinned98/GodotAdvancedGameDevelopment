class_name ChunkContext
extends RefCounted

var chunk: Vector2i
var origin: Vector2i          # Tile-Koordinate der linken oberen Chunk-Ecke
var size: int                 # Tiles pro Chunk-Seite
var rng: RandomNumberGenerator
var world: WorldData
var vegetation: float         # Vegetationswert 0..1 dieses Chunks

var ground: TileMapLayer
var overlay: TileMapLayer
var decoration: TileMapLayer


var cells: Array[Vector2i]     # NEU: nur die Zellen dieses Bioms im Chunk
# var vegetation entfällt, stattdessen ctx.world.vegetation_at_tile(cell)

func all_cells() -> Array[Vector2i]:
	return cells 


func pick(variants: Array[Vector2i]) -> Vector2i:
	return variants[rng.randi_range(0, variants.size() - 1)]
