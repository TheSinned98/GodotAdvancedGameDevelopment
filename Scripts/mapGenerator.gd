extends Node2D

signal generation_finished

@export var map_size := Vector2i(128, 128)
@export var map_seed := 0                       # 0 = zufällig
@export var noise_frequency := 0.03
@export_range(-1.0, 1.0) var water_level := -0.1  # darunter: Wasser
@export_range(-1.0, 1.0) var grass_level := 0.15  # darüber: Gras
@export var generate_on_ready := true

# Wird nach der Generierung gesetzt, damit du den Seed speichern kannst
var current_seed := 0

@onready var ground: TileMapLayer = $Ground
@onready var grass_layer: TileMapLayer = $Grass

const SOURCE_ID := 0
const TERRAIN_SET := 0
const TERRAIN_WATER := 1
const TERRAIN_SAND := 0
const TERRAIN_GRASS := 2

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	if generate_on_ready:
		generate()


func generate() -> void:
	current_seed = map_seed if map_seed != 0 else randi()
	_rng.seed = current_seed

	var noise := FastNoiseLite.new()
	noise.seed = current_seed
	noise.frequency = noise_frequency

	var water_cells: Array[Vector2i] = []
	var sand_cells: Array[Vector2i] = []
	var grass_cells: Array[Vector2i] = []

	for x in map_size.x:
		for y in map_size.y:
			var cell := Vector2i(x-1, y-1)
			var h := noise.get_noise_2d(x, y)  # -1 .. 1

			# Schritt 1: Basis, jede Zelle ist Wasser ODER Sand
			
			water_cells.append(cell)
			if h > water_level:
				sand_cells.append(cell)

			# Schritt 2: Gras zusätzlich über Sand
			if h > grass_level:
				grass_cells.append(cell)

	ground.clear()
	grass_layer.clear()

	# Basis mit automatischen Strand-Übergängen
	ground.set_cells_terrain_connect(water_cells, TERRAIN_SET, TERRAIN_WATER)
	ground.set_cells_terrain_connect(sand_cells, TERRAIN_SET, TERRAIN_SAND)
	grass_layer.set_cells_terrain_connect(grass_cells, TERRAIN_SET, TERRAIN_GRASS)

	generation_finished.emit()


# --- Hilfsfunktionen für das Spiel ---

func is_walkable(cell: Vector2i) -> bool:
	if grass_layer.get_cell_source_id(cell) != -1:
		return true
	var data := ground.get_cell_tile_data(cell)
	return data != null and data.terrain != TERRAIN_WATER


func get_spawn_position() -> Vector2:
	# Grasfläche, die der Kartenmitte am nächsten liegt
	var center := map_size / 2
	var best := center
	var best_dist := INF
	for cell in grass_layer.get_used_cells():
		var d := Vector2(cell - center).length_squared()
		if d < best_dist:
			best_dist = d
			best = cell
	return ground.map_to_local(best)

func get_spawn_position_global() -> Vector2:
	return ground.to_global(get_spawn_position())
