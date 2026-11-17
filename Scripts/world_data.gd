class_name WorldData
extends RefCounted

enum Biome { OCEAN, BEACH, MOUNTAIN, TUNDRA, DESERT, PLAINS, FOREST }

const BIOME_COLORS := {
	Biome.OCEAN: Color("2a5db0"),
	Biome.BEACH: Color("e8d28a"),
	Biome.MOUNTAIN: Color("8a8a8a"),
	Biome.TUNDRA: Color("dfe8ef"),
	Biome.DESERT: Color("d9a441"),
	Biome.PLAINS: Color("8fc36a"),
	Biome.FOREST: Color("2f7d3a"),
}

# Schwellwerte (auf 0..1 normalisierte Werte), per Vorschau-Bild feintunen
var sea_level := 0.40
var mountain_level := 0.72

var world_seed := 0
var size := Vector2i(64, 64)   # in Chunks

var height := PackedFloat32Array()
var temperature := PackedFloat32Array()
var vegetation := PackedFloat32Array()
var biomes := PackedInt32Array()

var chunk_size := 32                    # NEU
var _h_noise: FastNoiseLite             # NEU: als Member behalten
var _v_noise: FastNoiseLite

func generate(p_seed: int, p_size: Vector2i, p_chunk_size: int = 32) -> void:
	world_seed = p_seed
	size = p_size
	chunk_size = p_chunk_size
	_h_noise = _make_noise(world_seed, 0.04, 4)
	_v_noise = _make_noise(world_seed + 1337, 0.08, 3)

	var n := size.x * size.y
	height.resize(n)
	temperature.resize(n)
	vegetation.resize(n)
	biomes.resize(n)

	# Grobe Karte: am Mittelpunkt jedes Chunks abtasten (für Vorschau und Spawn)
	for y in size.y:
		for x in size.x:
			var i := y * size.x + x
			var s := _sample(Vector2(x + 0.5, y + 0.5))
			height[i] = s.x
			temperature[i] = s.y
			vegetation[i] = s.z
			biomes[i] = _classify(s.x, s.y, s.z)


# pos in Chunk-Einheiten (mit Nachkommastellen). Rückgabe: x = Höhe, y = Klima, z = Vegetation
func _sample(pos: Vector2) -> Vector3:
	var h := (_h_noise.get_noise_2d(pos.x, pos.y) + 1.0) * 0.5
	var v := (_v_noise.get_noise_2d(pos.x, pos.y) + 1.0) * 0.5
	var t := 1.0 - absf(pos.y / float(size.y) * 2.0 - 1.0)
	t = clampf(t - maxf(0.0, h - sea_level) * 0.5, 0.0, 1.0)
	return Vector3(h, t, v)


func biome_at_tile(tile: Vector2i) -> int:
	var s := _sample(Vector2(tile) / float(chunk_size))
	return _classify(s.x, s.y, s.z)


func vegetation_at_tile(tile: Vector2i) -> float:
	return _sample(Vector2(tile) / float(chunk_size)).z


func tile_in_bounds(tile: Vector2i) -> bool:
	return tile.x >= 0 and tile.y >= 0 \
		and tile.x < size.x * chunk_size and tile.y < size.y * chunk_size


func _classify(h: float, t: float, v: float) -> int:
	if h < sea_level:
		return Biome.OCEAN
	if h < sea_level + 0.04:
		return Biome.BEACH
	if h > mountain_level:
		return Biome.MOUNTAIN
	if t < 0.3:
		return Biome.TUNDRA
	if t > 0.65 and v < 0.5:
		return Biome.DESERT
	if v > 0.55:
		return Biome.FOREST
	return Biome.PLAINS


func _make_noise(p_seed: int, freq: float, octaves: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = p_seed
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_octaves = octaves
	return n


func in_bounds(chunk: Vector2i) -> bool:
	return chunk.x >= 0 and chunk.y >= 0 and chunk.x < size.x and chunk.y < size.y


func get_biome(chunk: Vector2i) -> int:
	return biomes[chunk.y * size.x + chunk.x] if in_bounds(chunk) else -1


func get_vegetation(chunk: Vector2i) -> float:
	return vegetation[chunk.y * size.x + chunk.x]


# Chunk in Kartenmitte, der zum gewünschten Biom passt (für den Spawn)
func find_spawn_chunk(preferred: int = Biome.PLAINS) -> Vector2i:
	var center := size / 2
	var best := center
	var best_dist := INF
	for y in size.y:
		for x in size.x:
			var b := biomes[y * size.x + x]
			if b != preferred:
				continue
			var d := Vector2(Vector2i(x, y) - center).length_squared()
			if d < best_dist:
				best_dist = d
				best = Vector2i(x, y)
	return best

func height_at_tile(tile: Vector2i) -> float:
	return _sample(Vector2(tile) / float(chunk_size)).x

func temperature_at_tile(tile: Vector2i) -> float:
	return _sample(Vector2(tile) / float(chunk_size)).y

# Vorschau-Bild: 1 Pixel pro Chunk
func to_image() -> Image:
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGB8)
	for y in size.y:
		for x in size.x:
			img.set_pixel(x, y, BIOME_COLORS[biomes[y * size.x + x]])
	return img
