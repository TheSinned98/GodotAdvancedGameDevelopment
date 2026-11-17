extends Node2D

signal generation_finished

@export var map_size := Vector2i(80, 60)
@export var map_seed := 0                          # 0 = zufällig

# NEU: Räume
@export var min_rooms := 5
@export var max_rooms := 9
@export var min_room_size := 40   # Zellen pro Raum
@export var max_room_size := 90
@export var steps_between_rooms := 40  # y: Schritte des Läufers zwischen zwei Räumen

# Gänge (wie bisher)
@export var min_width := 3
@export var max_width := 5
@export var width_change_interval := 4
@export_range(0.0, 1.0) var direction_change_chance := 0.25  # NEU: 1.0 = jeder Schritt neue Richtung

@export var generate_on_ready := true

@onready var layer: TileMapLayer = $Floor

const SOURCE_ID := 0
const TERRAIN_SET := 0
const TERRAIN_WALL := 3
const TERRAIN_FLOOR := 4

const DIRECTIONS: Array[Vector2i] = [
	Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT
]


# NEU: Datenstruktur für einen Raum
class Room:
	var id: int
	var center: Vector2i
	var cells: Array[Vector2i] = []


var current_seed := 0
var start_cell := Vector2i.ZERO

# NEU: ersetzt floor_cells
var rooms: Array[Room] = []
var room_of_cell: Dictionary = {}    # Vector2i -> Raum-ID
var corridor_cells: Dictionary = {}  # Vector2i -> true (Gänge außerhalb von Räumen)

var _rng := RandomNumberGenerator.new()
var _margin := 1


func _ready() -> void:
	if generate_on_ready:
		generate()


func generate() -> void:
	current_seed = map_seed if map_seed != 0 else randi()
	_rng.seed = current_seed

	rooms.clear()
	room_of_cell.clear()
	corridor_cells.clear()
	layer.clear()

	_margin = max_width / 2 + 1

	# 1. GEÄNDERT: Läufer erzeugt Räume und verbindet sie mit Gängen
	start_cell = map_size / 2
	var pos := start_cell
	var room_count := _rng.randi_range(min_rooms, max_rooms)

	_create_room(pos)  # erster Raum am Start
	for i in range(1, room_count):
		pos = _walk(pos, steps_between_rooms)
		_create_room(pos)

	# 2. Zuerst die ganze Karte als Wand
	var wall_array: Array[Vector2i] = []
	for x in map_size.x:
		for y in map_size.y:
			wall_array.append(Vector2i(x, y))
	layer.set_cells_terrain_connect(wall_array, TERRAIN_SET, TERRAIN_WALL)

	# 3. Dann Räume und Gänge als Boden darüber
	var floor_array: Array[Vector2i] = []
	floor_array.assign(room_of_cell.keys())
	floor_array.append_array(corridor_cells.keys())
	layer.set_cells_terrain_connect(floor_array, TERRAIN_SET, TERRAIN_FLOOR)

	generation_finished.emit()


# NEU: Läufer macht `steps` Schritte und hebt dabei einen Gang aus.
# Danach läuft er weiter, bis er außerhalb eines Raums steht. Gibt die Endposition zurück.
func _walk(from: Vector2i, steps: int) -> Vector2i:
	var pos := from
	var dir := DIRECTIONS[_rng.randi_range(0, DIRECTIONS.size() - 1)]
	var width := _rng.randi_range(min_width, max_width)
	var walked := 0
	var attempts := 0
	var max_attempts := steps * 50  # Sicherung gegen Endlosschleife

	# Phase 1: y Schritte laufen und Gang aushöhlen
	while walked < steps and attempts < max_attempts:
		attempts += 1
		if _rng.randf() < direction_change_chance:
			dir = DIRECTIONS[_rng.randi_range(0, DIRECTIONS.size() - 1)]
		var next := pos + dir
		if not _in_bounds(next):
			dir = DIRECTIONS[_rng.randi_range(0, DIRECTIONS.size() - 1)]
			continue
		pos = next
		walked += 1
		if walked % width_change_interval == 0:
			width = _rng.randi_range(min_width, max_width)
		_carve_corridor(pos, width)

	# Phase 2: weiterlaufen, bis die Position in keinem Raum liegt
	while room_of_cell.has(pos) and attempts < max_attempts:
		attempts += 1
		var next := pos + dir
		if not _in_bounds(next):
			dir = DIRECTIONS[_rng.randi_range(0, DIRECTIONS.size() - 1)]
			continue
		pos = next
		_carve_corridor(pos, width)

	return pos


# NEU: Gang-Stempel (Quadrat), Raumzellen bleiben dabei unverändert
func _carve_corridor(center: Vector2i, width: int) -> void:
	var from := -(width / 2)
	for x in range(from, from + width):
		for y in range(from, from + width):
			var c := center + Vector2i(x, y)
			if not room_of_cell.has(c):
				corridor_cells[c] = true


# NEU: Raum per Floodfill mit zufälliger Frontier (ergibt organische Blobs)
func _create_room(center: Vector2i) -> Room:
	var room := Room.new()
	room.id = rooms.size()
	room.center = center

	var target_size := _rng.randi_range(min_room_size, max_room_size)
	var frontier: Array[Vector2i] = [center]
	var visited: Dictionary = {center: true}

	while room.cells.size() < target_size and not frontier.is_empty():
		# zufällige Zelle aus der Frontier ziehen
		var idx := _rng.randi_range(0, frontier.size() - 1)
		var cell: Vector2i = frontier[idx]
		frontier[idx] = frontier.back()
		frontier.pop_back()

		if room_of_cell.has(cell):
			continue  # gehört schon zu einem anderen Raum

		room_of_cell[cell] = room.id
		corridor_cells.erase(cell)  # Raum überschreibt Gang
		room.cells.append(cell)

		for d in DIRECTIONS:
			var n: Vector2i = cell + d
			if visited.has(n) or not _in_bounds(n):
				continue
			visited[n] = true
			frontier.append(n)

	rooms.append(room)
	return room


func _in_bounds(cell: Vector2i) -> bool:
	return cell.x >= _margin and cell.y >= _margin \
		and cell.x < map_size.x - _margin and cell.y < map_size.y - _margin


# --- NEU: Abfragen für das Spiel ---

# Raum-ID einer Zelle, -1 wenn Gang oder Wand
func get_room_id_at(cell: Vector2i) -> int:
	return room_of_cell.get(cell, -1)


func get_room_at(cell: Vector2i) -> Room:
	var id := get_room_id_at(cell)
	return rooms[id] if id != -1 else null


func get_random_cell_in_room(room_id: int) -> Vector2i:
	var cells := rooms[room_id].cells
	return cells[_rng.randi_range(0, cells.size() - 1)]


func get_spawn_position() -> Vector2:
	return layer.map_to_local(start_cell)


func get_spawn_position_global() -> Vector2:
	return layer.to_global(get_spawn_position())
