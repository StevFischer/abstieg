class_name Texturen
extends RefCounted
## Erzeugt die Minentexturen im Code: 64×64 Pixel, ohne Filterung — der grobe
## Descent-Look von 1995, aber mit Normalenkarte, damit das Licht Kanten findet.

const G := 64


static func materialien(thema: Dictionary, saat: int) -> Dictionary:
	var wand := _fels(thema, saat) if thema.fels else _platten(thema, saat, thema.wand_dunkel, thema.wand_hell, 32)
	return {
		"wand": _material(wand, thema, false),
		"boden": _material(_boden(thema, saat + 1), thema, false),
		"decke": _material(_platten(thema, saat + 2, thema.decke * 0.5, thema.decke, 16), thema, false),
		"paneel": _material(_paneel(thema), thema, true),
	}


static func _rauschen(saat: int, frequenz: float, art: int) -> Image:
	var n := FastNoiseLite.new()
	n.seed = saat
	n.frequency = frequenz
	n.noise_type = art
	return n.get_seamless_image(G, G)


## Gibt [Farbbild, Höhenbild] zurück.
static func _fels(thema: Dictionary, saat: int) -> Array:
	var zellen := _rauschen(saat, 0.09, FastNoiseLite.TYPE_CELLULAR)
	var fein := _rauschen(saat + 7, 0.2, FastNoiseLite.TYPE_SIMPLEX)
	var farbe := Image.create(G, G, false, Image.FORMAT_RGBA8)
	var hoehe := Image.create(G, G, false, Image.FORMAT_RGBA8)
	for y in G:
		for x in G:
			var h := 0.6 * zellen.get_pixel(x, y).r + 0.4 * fein.get_pixel(x, y).r
			h = floorf(h * 10.0) / 10.0   # wenige Stufen: grob wie damals
			farbe.set_pixel(x, y, thema.wand_dunkel.lerp(thema.wand_hell, h))
			hoehe.set_pixel(x, y, Color(h, h, h))
	return [farbe, hoehe]


static func _platten(_thema: Dictionary, saat: int, dunkel: Color, hell: Color, raster: int) -> Array:
	var flecken := _rauschen(saat, 0.05, FastNoiseLite.TYPE_SIMPLEX)
	var fein := _rauschen(saat + 3, 0.35, FastNoiseLite.TYPE_VALUE)
	var farbe := Image.create(G, G, false, Image.FORMAT_RGBA8)
	var hoehe := Image.create(G, G, false, Image.FORMAT_RGBA8)
	for y in G:
		for x in G:
			var px := x % raster
			var py := y % raster
			var h := 0.55 + 0.15 * fein.get_pixel(x, y).r - 0.25 * flecken.get_pixel(x, y).r
			if px == 0 or py == 0:
				h = 0.12          # Fuge
			elif px == 1 or py == 1:
				h = 0.85          # Lichtkante
			elif (px == 4 or px == raster - 4) and (py == 4 or py == raster - 4):
				h = 0.95          # Niete
			h = floorf(clampf(h, 0.0, 1.0) * 12.0) / 12.0
			farbe.set_pixel(x, y, dunkel.lerp(hell, h))
			hoehe.set_pixel(x, y, Color(h, h, h))
	return [farbe, hoehe]


static func _boden(thema: Dictionary, saat: int) -> Array:
	var flecken := _rauschen(saat, 0.06, FastNoiseLite.TYPE_SIMPLEX)
	var farbe := Image.create(G, G, false, Image.FORMAT_RGBA8)
	var hoehe := Image.create(G, G, false, Image.FORMAT_RGBA8)
	for y in G:
		for x in G:
			var h := 0.45 - 0.2 * flecken.get_pixel(x, y).r
			# Riffelblech: kurze Rauten im Wechsel
			var feld := (x / 8 + y / 8) % 2
			var a := (x + y) % 8 if feld == 0 else (x - y + 64) % 8
			if a < 2:
				h += 0.3
			if x % 32 == 0 or y % 32 == 0:
				h = 0.1
			h = floorf(clampf(h, 0.0, 1.0) * 12.0) / 12.0
			farbe.set_pixel(x, y, thema.boden_dunkel.lerp(thema.boden_hell, h))
			hoehe.set_pixel(x, y, Color(h, h, h))
	return [farbe, hoehe]


static func _paneel(thema: Dictionary) -> Array:
	var licht: Color = thema.lichter[0]
	var farbe := Image.create(G, G, false, Image.FORMAT_RGBA8)
	var hoehe := Image.create(G, G, false, Image.FORMAT_RGBA8)
	for y in G:
		for x in G:
			var rand := x < 6 or y < 6 or x >= G - 6 or y >= G - 6
			var leuchtet := not rand and (y % 10) < 6
			var c := licht.darkened(0.45 + 0.15 * float(y % 10) / 6.0) if leuchtet else (Color(0.08, 0.08, 0.09) if not rand else Color(0.25, 0.25, 0.27))
			farbe.set_pixel(x, y, c)
			var h := 0.9 if rand else (0.5 if leuchtet else 0.3)
			hoehe.set_pixel(x, y, Color(h, h, h))
	return [farbe, hoehe]


static func _material(bilder: Array, thema: Dictionary, leuchtend: bool) -> StandardMaterial3D:
	var farbe: Image = bilder[0]
	var normale: Image = bilder[1]
	normale.bump_map_to_normal_map(3.0)
	farbe.generate_mipmaps()
	normale.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(farbe)
	m.normal_enabled = true
	m.normal_texture = ImageTexture.create_from_image(normale)
	m.normal_scale = 0.9
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.roughness = 0.78
	m.metallic = thema.metall
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if leuchtend:
		m.emission_enabled = true
		m.emission_texture = m.albedo_texture
		m.emission_energy_multiplier = 0.55
	return m
