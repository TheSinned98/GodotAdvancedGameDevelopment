class_name ChunkContext
extends RefCounted

# Adapter fuer bestehende Biome: puffert Atlas-Deko, beruehrt aber keine Nodes.
class TileWrites extends RefCounted:
	var cells: Dictionary[Vector2i, Vector4i] = {}
	var _record: bool

	func _init(record: bool) -> void:
		_record = record

	func set_cell(
		cell: Vector2i, source_id: int, atlas: Vector2i, alternative: int = 0
	) -> void:
		if _record:
			cells[cell] = Vector4i(source_id, atlas.x, atlas.y, alternative)

	# Die bisherigen Terrain-Aufrufe der Biome werden nicht mehr gemalt.
	func set_cells_terrain_connect(
		_cells: Array[Vector2i], _terrain_set: int, _terrain: int,
		_ignore_empty_terrains := true
	) -> void:
		pass

	func get_cell_source_id(cell: Vector2i) -> int:
		var placement: Vector4i = cells.get(cell, Vector4i(-1, 0, 0, 0))
		return placement.x

var chunk: Vector2i
var origin: Vector2i
var size: int
var rng: RandomNumberGenerator
var world: WorldData
var ground: TileWrites
var overlay: TileWrites
var decoration: TileWrites
var cells: Array[Vector2i]

func all_cells() -> Array[Vector2i]:
	return cells

func pick(variants: Array[Vector2i]) -> Vector2i:
	return variants[rng.randi_range(0, variants.size() - 1)]
