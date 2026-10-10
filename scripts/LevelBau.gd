class_name LevelBau
extends RefCounted
## Macht aus den Zellen des Generators sichtbare Wände, Kollision und Licht.
## Jede Seite einer befahrbaren Zelle, hinter der Fels liegt, wird eine Fläche.
## Die Ecken werden über einen Hash verschoben — derselbe Eckpunkt bekommt immer
## dieselbe Verschiebung, das Gitter bleibt also dicht, wirkt aber wie gehauener Fels.


static func baue(gen: LevelGen, thema: Dictionary, mats: Dictionary) -> Node3D:
	var mine := Node3D.new()
	mine.name = "Mine"
	var s := LevelGen.ZELLE
	var zacken: float = thema.zacken
	var arten := ["boden", "decke", "wand", "paneel"]
	var werkzeuge := {}
	var anzahl := {}
	for k in arten:
		var t := SurfaceTool.new()
		t.begin(Mesh.PRIMITIVE_TRIANGLES)
		werkzeuge[k] = t
		anzahl[k] = 0
	var kollision := PackedVector3Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = gen.saat + 17
	for c: Vector3i in gen.zellen:
		for d: Vector3i in LevelGen.RICHTUNGEN:
			if gen.zellen.has(c + d):
				continue
			var art := "wand"
			if d.y < 0:
				art = "boden"
			elif d.y > 0:
				art = "decke"
			elif rng.randf() < 0.05:
				art = "paneel"
			_flaeche(werkzeuge[art], kollision, c, d, s, zacken)
			anzahl[art] += 1

	var mesh := ArrayMesh.new()
	for k in arten:
		if anzahl[k] == 0:
			continue
		var t: SurfaceTool = werkzeuge[k]
		t.generate_tangents()
		t.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mats[k])
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.name = "Waende"
	mine.add_child(mi)

	var koerper := StaticBody3D.new()
	koerper.collision_layer = 1
	koerper.collision_mask = 0
	var form := CollisionShape3D.new()
	var flaechen := ConcavePolygonShape3D.new()
	flaechen.backface_collision = true
	flaechen.set_faces(kollision)
	form.shape = flaechen
	koerper.add_child(form)
	mine.add_child(koerper)

	_lichter(mine, gen, thema, rng)
	return mine


static func _flaeche(t: SurfaceTool, koll: PackedVector3Array, c: Vector3i, d: Vector3i, s: float, zacken: float) -> void:
	var n := -Vector3(d)
	var u: Vector3i
	var v: Vector3i
	if d.y != 0:
		u = Vector3i(1, 0, 0)
		v = Vector3i(0, 0, 1)
	elif d.x != 0:
		u = Vector3i(0, 0, 1)
		v = Vector3i(0, 1, 0)
	else:
		u = Vector3i(1, 0, 0)
		v = Vector3i(0, 1, 0)
	# Ecken in Halbzellen-Einheiten: alle Komponenten ungerade, also eindeutig je Gitterpunkt.
	var mitte := c * 2 + d
	var ecken := [mitte - u - v, mitte + u - v, mitte + u + v, mitte - u + v]
	var p: Array[Vector3] = []
	var uv: Array[Vector2] = []
	for k: Vector3i in ecken:
		p.append(_ecke(k, s, zacken))
		uv.append(_uv(Vector3(k) * s * 0.5, d, s))
	for tri in [[0, 1, 2], [0, 2, 3]]:
		var a := p[tri[0]]
		var b := p[tri[1]]
		var cc := p[tri[2]]
		var nt := (b - a).cross(cc - a).normalized()
		var folge: Array = tri
		# Vorderseite nach innen (Godot: im Uhrzeigersinn von vorn gesehen)
		if nt.dot(n) > 0.0:
			folge = [tri[0], tri[2], tri[1]]
		else:
			nt = -nt
		for i in folge:
			t.set_normal(nt)
			t.set_uv(uv[i])
			t.add_vertex(p[i])
			koll.append(p[i])


static func _ecke(k: Vector3i, s: float, zacken: float) -> Vector3:
	var p := Vector3(k) * s * 0.5
	if zacken <= 0.0:
		return p
	var h := hash(k)
	var j := Vector3(float(h & 255), float((h >> 8) & 255), float((h >> 16) & 255)) / 127.5 - Vector3.ONE
	return p + j * zacken


static func _uv(p: Vector3, d: Vector3i, s: float) -> Vector2:
	if d.y != 0:
		return Vector2(p.x, p.z) / s + Vector2(0.5, 0.5)
	if d.x != 0:
		return Vector2(p.z, -p.y) / s + Vector2(0.5, 0.5)
	return Vector2(p.x, -p.y) / s + Vector2(0.5, 0.5)


static func _lichter(mine: Node3D, gen: LevelGen, thema: Dictionary, rng: RandomNumberGenerator) -> void:
	var s := LevelGen.ZELLE
	var lampen_mat := StandardMaterial3D.new()
	lampen_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for i in gen.raeume.size():
		var r := gen.raeume[i]
		var farbe: Color = thema.lichter[rng.randi_range(0, thema.lichter.size() - 1)]
		var oben := gen.mitte(i) + Vector3(0, (r.groesse.y - 1) * s * 0.5 + s * 0.3, 0)
		var l := OmniLight3D.new()
		l.light_color = farbe
		l.omni_range = maxf(r.groesse.x, r.groesse.z) * s * 0.9 + 6.0
		l.light_energy = 1.7
		l.omni_attenuation = 0.8
		l.position = oben
		mine.add_child(l)
		var lampe := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(1.6, 0.25, 1.6)
		var m := lampen_mat.duplicate() as StandardMaterial3D
		m.albedo_color = Color(farbe.r * 3.0, farbe.g * 3.0, farbe.b * 3.0)
		box.material = m
		lampe.mesh = box
		lampe.position = oben + Vector3(0, s * 0.18, 0)
		mine.add_child(lampe)
		# Stollen: jede dritte Zelle ein schwaches Licht
		var weg: Array = r.tunnel
		for j in range(1, weg.size(), 3):
			var tl := OmniLight3D.new()
			tl.light_color = farbe.lerp(Color.WHITE, 0.2)
			tl.omni_range = 10.0
			tl.light_energy = 0.9
			tl.position = LevelGen.welt_von(weg[j]) + Vector3(0, s * 0.3, 0)
			mine.add_child(tl)
