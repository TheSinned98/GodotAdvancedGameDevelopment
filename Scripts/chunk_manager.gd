extends Node2D
## Verwaltet die Chunks der Spielwelt: Der Boden wird per Shader gezeichnet, die
## Dekoration per TileMapLayer. Die Berechnung eines Chunks läuft in einem
## Worker-Thread, das Einfügen in die Szene im Hauptthread.
##
## Aufbau:
##   1. Variablen
##   2. Lebenszyklus (Godot-Callbacks, Initialisierung)
##   3. Chunk-Verwaltung (Warteschlangen, Jobs, Einfügen, Entladen)
##   4. Biom-Generierung (Worker-Thread: ChunkBuilder und Datenklassen)
##   5. Hilfsfunktionen (Koordinaten, Abstände, Spawn)


#region Signale
## Wird gesendet, sobald WorldData und ChunkBuilder bereit sind.
signal world_ready

## Wird gesendet, nachdem ein Chunk fertig in die Szene eingefügt wurde.
## `coords` ist die Chunk-Koordinate.
signal chunk_loaded(coords: Vector2i)
#endregion


#region Konstanten
## Shader, der den Boden eines Chunks aus der Höhen-/Vegetationsmaske zeichnet.
const TERRAIN_SHADER: Shader = preload("res://Scripts/terrain_surface.gdshader")

## Wie weit (in Höhenwert-Einheiten) ein Tile unter dem Meeresspiegel liegen muss,
## damit es als tiefes Wasser mit Kollision gilt.
const WATER_COLLISION_DEPTH := 0.025
#endregion


#region Variablen – Einstellungen (im Inspector änderbar)
## Seed der Welt. Bei 0 wird beim Start ein zufälliger Seed gewürfelt.
@export var world_seed := 0

## Größe der Welt in Chunks (Breite x Höhe).
@export var world_size := Vector2i(64, 64)

## Kantenlänge eines Chunks in Tiles.
@export_range(1, 128) var chunk_size := 32

## Radius (in Chunks) um den Spieler, in dem Chunks geladen sein sollen.
@export_range(0, 16) var load_radius := 2

## Budget an Arbeitsschritten pro Frame (Einfügen und Entladen von Chunks).
@export_range(1, 8) var chunks_per_frame := 2

## Der Spieler, um den herum geladen wird. Wird z. B. von game.gd gesetzt.
@export var player: Node2D

# --- Gruppe „Boden“ ---
@export_group("Boden")
## Größe eines Tiles in Pixeln, falls das TileSet nicht verwendet wird.
@export var tile_world_size := Vector2i(16, 16)

## Wenn aktiv, wird die Tile-Größe aus dem TileSet des Ground-Knotens übernommen.
@export var use_tileset_tile_size := true

## Wenn aktiv, wird Deko (Bäume, Blumen ...) als Atlas-Tiles auf die Decoration-Ebene gemalt.
@export var use_atlas_decoration := true

## Stärke des Detail-Rauschens im Boden-Shader.
@export_range(0.0, 0.20) var terrain_detail_strength := 0.045

# --- Gruppe „Wasserkollision“ ---
@export_group("Wasserkollision")
## Wenn aktiv, wird tiefes Wasser mit Kollisionsrechtecken für den Spieler gesperrt.
@export var block_deep_water := true

## Physik-Ebene der Wasserkollision. 0 = keine Kollision.
@export_flags_2d_physics var water_collision_layer := 1
#endregion


#region Variablen – Knoten und Laufzeitdaten
## Elternknoten für den Shader-Boden. Kann zusätzlich ein TileMapLayer sein (für Raster-Infos).
@onready var ground: Node2D = $Ground

## TileMapLayer für Atlas-Dekoration. Null, wenn kein Knoten „Decoration“ existiert.
@onready var decoration: TileMapLayer = get_node_or_null("Decoration") as TileMapLayer

## Weltdaten: grobe Biomkarte und Noise-Abfragen pro Tile. Nach `_ready()` read-only.
var world := WorldData.new()

## Menge aller vollständig geladenen Chunks (Chunk-Koordinate -> true).
var loaded: Dictionary[Vector2i, bool] = {}

## Boden-Polygone der geladenen Chunks (Chunk-Koordinate -> Polygon2D).
var _surfaces: Dictionary[Vector2i, Polygon2D] = {}

## Pro Chunk die Zellen, auf die Deko gemalt wurde (zum späteren Löschen beim Entladen).
var _painted_decoration: Dictionary = {}

## Zu erzeugende Chunks, nächste zum Spieler zuerst.
var _queue: Array[Vector2i] = []

## Zu entladende Chunks (werden von hinten abgearbeitet).
var _unload_queue: Array[Vector2i] = []

## Chunk, in dem der Spieler zuletzt war. Der Startwert liegt weit außerhalb der Welt,
## damit der erste Vergleich immer anschlägt.
var _player_chunk := Vector2i(-9999, -9999)

## ID des laufenden Worker-Tasks, -1 wenn gerade keiner läuft.
var _task_id := -1

## Chunk, den der laufende Worker-Task gerade berechnet.
var _building_chunk: Vector2i

## Wurde im letzten Frame ein Chunk eingefügt? Dann wird im nächsten Frame zuerst entladen,
## damit sich Einfügen nicht über mehrere Frames aufstaut.
var _applied_last_frame := false

## Tatsächliche Tile-Größe in Pixeln (aus Einstellung oder TileSet).
var _tile_pixels := Vector2(16.0, 16.0)

## Pixelposition der linken oberen Ecke von Tile (0, 0) im Ground-Koordinatensystem.
var _grid_origin := Vector2.ZERO

## Container-Knoten unter `ground`, der alle Boden-Polygone der Chunks enthält.
var _terrain_root: Node2D

## Erzeugt die Chunk-Daten im Worker-Thread. Wird in `_ready()` angelegt.
var _builder: ChunkBuilder
#endregion


#region Lebenszyklus
## Initialisiert Raster, Boden-Container, Seed, Weltdaten und den ChunkBuilder.
func _ready() -> void:
	chunk_size = maxi(1, chunk_size)
	world_size = world_size.max(Vector2i.ONE)
	_configure_grid()

	_terrain_root = Node2D.new()
	_terrain_root.name = "ShaderTerrain"
	ground.add_child(_terrain_root)

	if world_seed == 0:
		world_seed = randi()
	world.generate(world_seed, world_size, chunk_size)
	# Ab hier wird WorldData nicht mehr verändert (der Worker liest es parallel).
	var with_decor := use_atlas_decoration and decoration != null and decoration.tile_set != null
	_builder = ChunkBuilder.new(world, with_decor, block_deep_water)
	world_ready.emit()


## Bestimmt Tile-Größe und Rasterursprung. Liest sie aus dem TileSet, falls `ground`
## ein TileMapLayer mit quadratischem Raster ist, sonst gelten die Einstellungen.
func _configure_grid() -> void:
	_tile_pixels = Vector2(tile_world_size.max(Vector2i.ONE))
	var tile_ground := ground as TileMapLayer
	if tile_ground == null or tile_ground.tile_set == null:
		return
	if tile_ground.tile_set.tile_shape != TileSet.TILE_SHAPE_SQUARE:
		push_warning("ShaderTerrain erwartet ein orthogonales Tile-Raster.")
		return
	var original_tile_pixels := Vector2(tile_ground.tile_set.tile_size)
	_grid_origin = tile_ground.map_to_local(Vector2i.ZERO) - original_tile_pixels * 0.5
	if use_tileset_tile_size:
		_tile_pixels = original_tile_pixels


## Beobachtet den Spieler: Bei Chunk-Wechsel wird neu geplant, danach wird das
## Frame-Budget für Einfügen und Entladen verbraucht.
func _process(_delta: float) -> void:
	if not is_instance_valid(player):
		return
	var center := _world_to_chunk(player.global_position)
	if center != _player_chunk:
		_player_chunk = center
		_refresh(center)
	_work_on_chunks()


## Wartet beim Beenden auf einen noch laufenden Worker-Task, damit er nicht
## auf freigegebene Daten zugreift.
func _exit_tree() -> void:
	if _task_id != -1:
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1
#endregion


#region Chunk-Verwaltung
## Verteilt das Frame-Budget (`chunks_per_frame`): zuerst ggf. ein Entladen,
## dann den fertigen Worker-Job einsammeln, den nächsten Job starten und
## übrige Budgetpunkte zum Entladen verwenden.
func _work_on_chunks() -> void:
	var budget := maxi(1, chunks_per_frame)
	if _applied_last_frame and not _unload_queue.is_empty():
		_unload_chunk(_unload_queue.pop_back())
		budget -= 1
	_applied_last_frame = budget > 0 and _collect_job()
	if _applied_last_frame:
		budget -= 1
	_start_next_job()
	while budget > 0 and not _unload_queue.is_empty():
		_unload_chunk(_unload_queue.pop_back())
		budget -= 1


## Aktualisiert die Planung rund um `center`: Lade- und Entlade-Warteschlange neu aufbauen.
func _refresh(center: Vector2i) -> void:
	_rebuild_load_queue(center)
	_rebuild_unload_queue(center)


## Baut die Lade-Warteschlange neu: alle fehlenden Chunks im Radius um `center`
## (außer dem, der gerade berechnet wird), nächste zuerst.
func _rebuild_load_queue(center: Vector2i) -> void:
	_queue.clear()
	for dx in range(-load_radius, load_radius + 1):
		for dy in range(-load_radius, load_radius + 1):
			var c := center + Vector2i(dx, dy)
			if _task_id != -1 and c == _building_chunk:
				continue
			if world.in_bounds(c) and not loaded.has(c):
				_queue.append(c)
	_queue.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (a - center).length_squared() < (b - center).length_squared()
	)


## Baut die Entlade-Warteschlange neu: alle geladenen Chunks, die weiter als
## `load_radius + 1` von `center` entfernt sind (ein Chunk Puffer gegen Flackern).
func _rebuild_unload_queue(center: Vector2i) -> void:
	_unload_queue.clear()
	for c in loaded:
		if _dist(c, center) > load_radius + 1:
			_unload_queue.append(c)


## Startet den nächsten Chunk aus der Warteschlange im Worker-Thread,
## sofern gerade keiner läuft.
func _start_next_job() -> void:
	if _task_id != -1 or _queue.is_empty():
		return
	_building_chunk = _queue.pop_front()
	_task_id = WorkerThreadPool.add_task(_builder.build.bind(_building_chunk))


## Prüft, ob der Worker fertig ist, und fügt das Ergebnis ein. Verwirft es, wenn der
## Spieler inzwischen zu weit weg ist. Gibt true zurück, wenn ein Chunk eingefügt wurde.
func _collect_job() -> bool:
	if _task_id == -1 or not WorkerThreadPool.is_task_completed(_task_id):
		return false
	WorkerThreadPool.wait_for_task_completion(_task_id)
	_task_id = -1
	if _dist(_building_chunk, _player_chunk) > load_radius:
		return false

	_install_chunk(_building_chunk, _builder.result)
	loaded[_building_chunk] = true
	chunk_loaded.emit(_building_chunk)
	return true


## Fügt einen fertig berechneten Chunk in die Szene ein: Boden-Polygon,
## optionale Wasserkollision und Dekoration.
func _install_chunk(c: Vector2i, data: ChunkResult) -> void:
	var surface := _create_surface(c, data)
	if not data.water_rects.is_empty() and water_collision_layer != 0:
		_add_water_collision(surface, data.water_rects)
	_terrain_root.add_child(surface)
	_surfaces[c] = surface
	_paint_decoration(c, data)


## Erzeugt das Boden-Polygon eines Chunks mit Shader-Material. Die Maske aus dem
## Worker wird dabei zur Textur. Das Polygon wird an der Chunk-Position platziert.
func _create_surface(c: Vector2i, data: ChunkResult) -> Polygon2D:
	var stride := chunk_size + 2
	var img := Image.create_from_data(stride, stride, false, Image.FORMAT_RG8, data.mask)
	var tex := ImageTexture.create_from_image(img)
	var extent := _tile_pixels * float(chunk_size)

	var surface := Polygon2D.new()
	surface.position = _grid_origin + Vector2(c) * extent
	surface.polygon = PackedVector2Array([
		Vector2.ZERO, Vector2(extent.x, 0.0), extent, Vector2(0.0, extent.y),
	])

	var mat := ShaderMaterial.new()
	mat.shader = TERRAIN_SHADER
	mat.set_shader_parameter("terrain_data", tex)
	mat.set_shader_parameter("chunk_cells", float(chunk_size))
	mat.set_shader_parameter("chunk_pixels", extent)
	mat.set_shader_parameter("sea_level", world.sea_level)
	mat.set_shader_parameter("mountain_level", world.mountain_level)
	mat.set_shader_parameter("detail_strength", terrain_detail_strength)
	surface.material = mat
	return surface


## Hängt an `surface` einen StaticBody2D mit je einem Kollisionsrechteck pro
## zusammengefasstem Wasserbereich (in Tile-Koordinaten relativ zum Chunk).
func _add_water_collision(surface: Polygon2D, rectangles: Array[Rect2i]) -> void:
	var body := StaticBody2D.new()
	body.name = "DeepWater"
	body.collision_layer = water_collision_layer
	body.collision_mask = 0
	for r in rectangles:
		var box := RectangleShape2D.new()
		box.size = Vector2(r.size) * _tile_pixels
		var shape := CollisionShape2D.new()
		shape.position = (Vector2(r.position) + Vector2(r.size) * 0.5) * _tile_pixels
		shape.shape = box
		body.add_child(shape)
	surface.add_child(body)


## Malt die Deko-Tiles des Chunks auf die Decoration-Ebene und merkt sich die
## Zellen, damit sie beim Entladen wieder gelöscht werden können.
## Ein Eintrag in `tile_decor` ist Vector4i(source_id, atlas_x, atlas_y, alternative).
func _paint_decoration(c: Vector2i, data: ChunkResult) -> void:
	if decoration == null or data.tile_decor.is_empty():
		return
	var painted: Array[Vector2i] = []
	for cell in data.tile_decor:
		var tile: Vector4i = data.tile_decor[cell]
		decoration.set_cell(cell, tile.x, Vector2i(tile.y, tile.z), tile.w)
		painted.append(cell)
	_painted_decoration[c] = painted


## Entfernt Boden-Polygon und Deko des Chunks `c` und markiert ihn als nicht geladen.
func _unload_chunk(c: Vector2i) -> void:
	var surface: Polygon2D = _surfaces[c]
	_terrain_root.remove_child(surface)
	surface.queue_free()
	_surfaces.erase(c)
	if _painted_decoration.has(c):
		if is_instance_valid(decoration):
			for cell in _painted_decoration[c]:
				decoration.erase_cell(cell)
		_painted_decoration.erase(c)
	loaded.erase(c)
#endregion


#region Biom-Generierung (läuft im Worker-Thread)
## Ergebnis der Berechnung eines Chunks. Wird vom Worker gefüllt und im
## Hauptthread gelesen.
class ChunkResult extends RefCounted:
	## Maske für den Shader: pro Zelle (inkl. 1 Tile Rand) zwei Bytes,
	## Höhe und Vegetation (je 0..255).
	var mask := PackedByteArray()

	## Dekoration pro Zelle als Vector4i(source_id, atlas_x, atlas_y, alternative).
	var tile_decor: Dictionary[Vector2i, Vector4i] = {}

	## Zu Rechtecken zusammengefasste Bereiche tiefen Wassers (Tile-Koordinaten im Chunk).
	var water_rects: Array[Rect2i] = []


## Sicht auf WorldData, die schon berechnete Höhe/Klima/Vegetation eines Chunks
## liefert, damit die Biom-Skripte nicht erneut samplen müssen.
## Abfragen außerhalb des Chunk-Randes (z. B. ein Oasenzentrum) gehen an die echte Welt.
class ChunkSamples extends WorldData:
	## Die echte Welt, an die Abfragen außerhalb des Chunks weitergereicht werden.
	var source: WorldData

	## Tile-Koordinate der linken oberen Ecke des vorberechneten Bereichs.
	var origin: Vector2i

	## Kantenlänge des vorberechneten Bereichs in Tiles.
	var stride: int

	## Vorberechnete Werte Vector3(Höhe, Klima, Vegetation), zeilenweise abgelegt.
	var samples: PackedVector3Array

	## Übernimmt die Welteinstellungen aus `data` und merkt sich den vorberechneten Bereich.
	func _init(data: WorldData, start: Vector2i, width: int, values: PackedVector3Array) -> void:
		source = data
		origin = start
		stride = width
		samples = values
		world_seed = data.world_seed
		size = data.size
		chunk_size = data.chunk_size
		sea_level = data.sea_level
		mountain_level = data.mountain_level

	## Liefert den Sample-Wert eines Tiles: aus dem Cache, falls es im Bereich liegt,
	## sonst direkt aus der echten Welt.
	func sample_tile(tile: Vector2i) -> Vector3:
		var p := tile - origin
		if p.x >= 0 and p.y >= 0 and p.x < stride and p.y < stride:
			return samples[p.y * stride + p.x]
		return source.sample_tile(tile)


## Berechnet einen Chunk komplett: Shader-Maske, Wasserkollision und Dekoration.
## Nur Daten und RefCounted-Objekte; keine Szene, Textur oder Physik im Worker.
class ChunkBuilder extends RefCounted:
	## Ergebnis der letzten `build()`-Ausführung.
	var result: ChunkResult

	## Weltdaten (im Worker nur lesend benutzt).
	var _world: WorldData

	## Soll Atlas-Dekoration berechnet werden?
	var _with_decoration: bool

	## Soll Wasserkollision berechnet werden?
	var _block_water: bool

	## Biom-Generatoren, die Deko beitragen (Biom-ID -> BiomeGenerator).
	var _generators: Dictionary = {}

	## Speichert Welt und Optionen. Legt die Generatoren nur an, wenn Deko gebraucht wird.
	func _init(data: WorldData, with_decoration: bool, block_water: bool) -> void:
		_world = data
		_with_decoration = with_decoration
		_block_water = block_water
		if _with_decoration:
			# Nur Biome, die Atlas-Deko beitragen. Ozean malt hier nichts.
			var seed_value := data.world_seed
			_generators = {
				WorldData.Biome.BEACH: BeachBiome.new(seed_value),
				WorldData.Biome.MOUNTAIN: MountainBiome.new(seed_value),
				WorldData.Biome.TUNDRA: TundraBiome.new(seed_value),
				WorldData.Biome.DESERT: DesertBiome.new(seed_value),
				WorldData.Biome.PLAINS: PlainsBiome.new(seed_value),
				WorldData.Biome.FOREST: ForestBiome.new(seed_value),
			}

	## Haupteinstieg für den Worker: sampelt den Chunk samt 1 Tile Rand einmal durch und
	## füllt dabei Shader-Maske, Wasser-Flags und Sample-Cache. Danach folgen
	## zusammengefasste Wasserrechtecke und die Dekoration.
	func build(c: Vector2i) -> void:
		result = ChunkResult.new()
		var side := _world.chunk_size
		var stride := side + 2
		var origin := c * side
		var mask_origin := origin - Vector2i.ONE
		var last_tile := _world.size * side - Vector2i.ONE
		var samples := PackedVector3Array()
		var water := PackedByteArray()
		result.mask.resize(stride * stride * 2)
		if _with_decoration:
			samples.resize(stride * stride)
		if _block_water:
			water.resize(side * side)

		for y in stride:
			for x in stride:
				var cell := mask_origin + Vector2i(x, y)
				var sample := _world.sample_tile(cell.clamp(Vector2i.ZERO, last_tile))
				var i := y * stride + x
				var height_byte := roundi(clampf(sample.x, 0.0, 1.0) * 255.0)
				result.mask[i * 2] = height_byte
				result.mask[i * 2 + 1] = roundi(clampf(sample.z, 0.0, 1.0) * 255.0)
				if _with_decoration:
					samples[i] = sample
				if _block_water and x > 0 and y > 0 and x <= side and y <= side:
					water[(y - 1) * side + x - 1] = int(
						float(height_byte) / 255.0 < _world.sea_level - WATER_COLLISION_DEPTH
					)

		if _block_water:
			result.water_rects = _merge_water_rows(water, side)
		if _with_decoration:
			var view := ChunkSamples.new(_world, mask_origin, stride, samples)
			result.tile_decor = _build_decor(c, origin, view)

	## Lässt die Biom-Generatoren die Dekoration des Chunks erzeugen: Zellen nach Biom
	## gruppieren, pro Biom einen ChunkContext bauen und den Generator aufrufen.
	## Bodenschreibzugriffe werden verworfen, nur die Deko wird zurückgegeben
	## (Zelle -> Vector4i(source_id, atlas_x, atlas_y, alternative)).
	func _build_decor(
		c: Vector2i, origin: Vector2i, view: ChunkSamples
	) -> Dictionary[Vector2i, Vector4i]:
		var side := view.chunk_size
		var by_biome: Dictionary = {}
		# Dieselbe Reihenfolge wie früher: X außen, Y innen.
		for x in side:
			for y in side:
				var cell := origin + Vector2i(x, y)
				var s := view.sample_tile(cell)
				var biome := view.classify_sample(s)
				if not _generators.has(biome):
					continue
				if not by_biome.has(biome):
					var cells: Array[Vector2i] = []
					by_biome[biome] = cells
				by_biome[biome].append(cell)

		var ignore_ground := ChunkContext.TileWrites.new(false)
		var decor := ChunkContext.TileWrites.new(true)
		for biome in by_biome:
			var gen: BiomeGenerator = _generators[biome]
			var ctx := ChunkContext.new()
			ctx.chunk = c
			ctx.origin = origin
			ctx.size = side
			ctx.world = view
			ctx.cells = by_biome[biome]
			ctx.rng = RandomNumberGenerator.new()
			ctx.rng.seed = hash([view.world_seed, c.x, c.y, biome])
			ctx.ground = ignore_ground
			ctx.overlay = ignore_ground
			ctx.decoration = decor
			gen.generate(ctx)
		return decor.cells

	## Fasst Wasserzellen zu möglichst wenigen Rechtecken zusammen: Zeilen werden zu
	## horizontalen Spannen vereint, gleiche Spannen in aufeinanderfolgenden Zeilen
	## werden nach unten verlängert. `water` enthält pro Zelle 0 oder 1.
	func _merge_water_rows(water: PackedByteArray, side: int) -> Array[Rect2i]:
		var finished: Array[Rect2i] = []
		var open: Dictionary[Vector2i, Rect2i] = {}
		for y in side:
			var next: Dictionary[Vector2i, Rect2i] = {}
			var x := 0
			while x < side:
				if water[y * side + x] == 0:
					x += 1
					continue
				var start := x
				while x < side and water[y * side + x] != 0:
					x += 1
				var span := Vector2i(start, x - start)
				var r := Rect2i(start, y, span.y, 1)
				if open.has(span):
					r = open[span]
					r.size.y += 1
					open.erase(span)
				next[span] = r
			for r in open.values():
				finished.append(r)
			open = next
		for r in open.values():
			finished.append(r)
		return finished
#endregion


#region Hilfsfunktionen
## Globale Position des Spawn-Punkts: Mitte des Chunks, den WorldData als Spawn vorschlägt.
func get_spawn_position_global() -> Vector2:
	var c := world.find_spawn_chunk()
	var tile := c * chunk_size + Vector2i.ONE * (chunk_size / 2)
	return ground.to_global(_grid_origin + (Vector2(tile) + Vector2(0.5, 0.5)) * _tile_pixels)


## Gibt zurück, ob der Chunk, in dem die globale Position `pos` liegt, geladen ist.
func is_chunk_loaded_at(pos: Vector2) -> bool:
	return loaded.has(_world_to_chunk(pos))


## Rechnet eine globale Position in Chunk-Einheiten um (mit Nachkommastellen,
## z. B. für die Marker-Position der Weltkarte).
func global_to_chunk_position(pos: Vector2) -> Vector2:
	return (ground.to_local(pos) - _grid_origin) / (_tile_pixels * float(chunk_size))


## Rechnet eine globale Position in die Koordinate des Chunks um, in dem sie liegt.
func _world_to_chunk(pos: Vector2) -> Vector2i:
	return Vector2i(global_to_chunk_position(pos).floor())


## Chunk-Abstand zwischen `a` und `b` (größte Achsendifferenz, Chebyshev-Metrik),
## entspricht dem quadratischen Ladebereich um den Spieler.
func _dist(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))
#endregion
