class_name Optik
extends RefCounted
## Aussehen von Geschossen und Explosionen (Stev 2026-10-10: „Geschosse mit Blender überarbeiten, damit da
## was Schöneres rauskommt, und die Explosionen“ — Stil leuchtend Sci-Fi, Explosionen gedämpft, kurze Leuchtspur).
## Laser: weiß glühender Kern + weicher Schein + Leuchtspur, Form je Waffe.
## Raketen: Modelle aus tools/geschosse_bauen.py (assets/geschosse/), Düsenflamme, kurze Spur.
## Gegnerschüsse: leuchtende Kugel mit Schein — anders als eigene Bolzen, damit Gefahr sofort lesbar ist.
## Explosion: Blitz, weicher Feuerball, Funken, ab mittlerer Größe Druckwelle; nach 0,6 s vorbei.

static var _glanz: Texture2D
static var _ring: Texture2D
static var _spur: Texture2D
static var _modelle := {}
static var _mat := {}


## Weicher runder Schein (weiß, nach außen durchsichtig)
static func glanz() -> Texture2D:
	if _glanz == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(0.5, 0.0)
		t.width = 64
		t.height = 64
		_glanz = t
	return _glanz


## Ring für die Druckwelle
static func ring() -> Texture2D:
	if _ring == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.62, 0.8, 0.9, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.3), Color(1, 1, 1, 0)])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(0.5, 0.0)
		t.width = 128
		t.height = 128
		_ring = t
	return _ring


## Längsverlauf für Leuchtspuren: vorn hell, hinten durchsichtig (V-Koordinate des Zylinders)
static func spur() -> Texture2D:
	if _spur == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 0.9), Color(1, 1, 1, 0)])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill_from = Vector2(0, 0)
		t.fill_to = Vector2(0, 1)
		t.width = 4
		t.height = 64
		_spur = t
	return _spur


## Additives, unbeleuchtetes Material (für Schein, Flamme, Spur); billboard = zeigt immer zur Kamera
static func leucht(farbe: Color, tex: Texture2D = null, billboard := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	m.albedo_color = farbe
	if tex:
		m.albedo_texture = tex
	if billboard:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.billboard_keep_scale = true
	return m


## Wie leucht(), aber geteilt je Farbe/Textur — für Geschosse, die ihre Materialien nicht verändern
## (sonst legte jedes Geschoss fünf neue Materialien an, beim Vulkan rund 90 je Sekunde).
static var _fest := {}
static func leucht_fest(farbe: Color, tex: Texture2D = null, billboard := false) -> StandardMaterial3D:
	var k := [farbe, tex, billboard]
	if not _fest.has(k):
		_fest[k] = leucht(farbe, tex, billboard)
	return _fest[k]


static func kern(farbe: Color) -> StandardMaterial3D:
	var k := ["kern", farbe]
	if not _fest.has(k):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = farbe
		_fest[k] = m
	return _fest[k]


static func _teil(eltern: Node3D, mesh: Mesh, mat: Material, pos := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	eltern.add_child(mi)
	return mi


static func _schein(eltern: Node3D, farbe: Color, groesse: float, pos := Vector3.ZERO, fest := false) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = Vector2(groesse, groesse)
	return _teil(eltern, q, leucht_fest(farbe, glanz(), true) if fest else leucht(farbe, glanz(), true), pos)


## Leuchtspur hinter dem Geschoss (+Z ist hinten): spitz zulaufender Kegel mit Längsverlauf
static func _spur_teil(eltern: Node3D, farbe: Color, laenge: float, breite: float) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = breite
	c.bottom_radius = 0.0
	c.height = laenge
	c.radial_segments = 8
	c.rings = 1
	c.cap_top = false
	c.cap_bottom = false
	var mi := _teil(eltern, c, leucht_fest(farbe, spur()), Vector3(0, 0, laenge * 0.5))
	mi.rotation.x = -PI / 2.0      # Zylinderachse: oberes Ende (breit, V=0 = hell) am Geschoss, Spitze nach hinten (+Z)
	return mi


## Baut das Aussehen eines Geschosses unter "g". art: Waffen-ID ("zwilling", "zielsuch" …), "mini" (Splitter-
## Zielsucher), "" = Gegnerschuss bzw. Standard-Laser.
static func geschoss(g: Node3D, art: String, farbe: Color, groesse: float, vom_spieler: bool) -> void:
	var hell := Color(farbe.r * 1.6, farbe.g * 1.6, farbe.b * 1.6)
	var kern_farbe := farbe.lerp(Color.WHITE, 0.65) * 2.2
	if not vom_spieler:
		# Gegner: Kugel mit weißem Kern und farbigem Schein
		var s := SphereMesh.new()
		s.radius = 0.13 * groesse
		s.height = 0.26 * groesse
		s.radial_segments = 8
		s.rings = 4
		var km := kern(kern_farbe)
		_teil(g, s, km)
		_schein(g, Color(hell, 0.75), 0.7 * groesse, Vector3.ZERO, true)
		_spur_teil(g, Color(farbe, 0.5), 0.8 * groesse, 0.08 * groesse)
		return
	if art in Waffen.RAKETEN.map(func(w): return w.id) or art == "mini":
		var id := "zielsuch" if art == "mini" else art
		var m := modell(id, farbe)
		m.scale = Vector3.ONE * (0.55 if art == "mini" else 1.1) * groesse
		g.add_child(m)
		var heck: float = {"zielsuch": 0.4, "streu_r": 0.3, "smart": 0.36, "mega": 0.55}.get(id, 0.4) * m.scale.x
		_schein(g, Color(1.0, 0.75, 0.4, 0.8), 0.28 * groesse, Vector3(0, 0, heck), true)       # Düsenflamme
		var flamme := _spur_teil(g, Color(1.0, 0.6, 0.25, 0.9), 0.5 * groesse, 0.06 * groesse)
		flamme.position.z += heck
		var sp := _spur_teil(g, Color(farbe, 0.45), 2.2 * groesse, 0.05 * groesse)       # kurze Leuchtspur (3–4 m)
		sp.position.z += heck
		return
	# Laser je Waffe: Kernlänge, Kerndicke, Scheingröße, Spurlänge
	var f: Array = {"zwilling": [0.9, 0.05, 0.55, 2.4], "streu": [0.55, 0.05, 0.45, 1.2],
		"vulkan": [0.45, 0.035, 0.35, 3.0], "plasma": [0.0, 0.0, 0.75, 1.4]}.get(art, [0.9, 0.05, 0.55, 2.4])
	if art == "plasma":
		var s := SphereMesh.new()
		s.radius = 0.16 * groesse
		s.height = 0.32 * groesse
		s.radial_segments = 10
		s.rings = 5
		var km := kern(kern_farbe)
		_teil(g, s, km)
		_schein(g, Color(hell, 0.6), f[2] * groesse, Vector3.ZERO, true)
		var rq := QuadMesh.new()
		rq.size = Vector2(0.6, 0.6) * groesse
		_teil(g, rq, leucht_fest(Color(hell, 0.6), ring(), true))
	else:
		var k := CapsuleMesh.new()
		k.radius = f[1] * groesse
		k.height = f[0] * groesse
		k.radial_segments = 6
		k.rings = 2
		var km := kern(kern_farbe)
		var kern := _teil(g, k, km)
		kern.rotation.x = PI / 2.0
		var h := CapsuleMesh.new()          # farbige Hülle um den Kern: weicher Rand
		h.radius = f[1] * 2.6 * groesse
		h.height = f[0] * 1.15 * groesse
		h.radial_segments = 8
		h.rings = 2
		_teil(g, h, leucht_fest(Color(hell, 0.35))).rotation.x = PI / 2.0
		_schein(g, Color(hell, 0.5), f[2] * groesse, Vector3.ZERO, true)
	_spur_teil(g, Color(farbe, 0.5), f[3] * groesse, f[1] * 1.8 * groesse + 0.02)


## Raketenmodell mit Materialien in der Waffenfarbe (geteilt je Waffe)
static func modell(id: String, farbe: Color) -> Node3D:
	if not _modelle.has(id):
		_modelle[id] = load("res://assets/geschosse/rakete_%s.glb" % id)
	var m: Node3D = _modelle[id].instantiate()
	if not _mat.has(id):
		var huelle := StandardMaterial3D.new()
		huelle.albedo_color = Color(0.78, 0.79, 0.84)
		huelle.metallic = 0.5
		huelle.roughness = 0.35
		var streifen := StandardMaterial3D.new()
		streifen.albedo_color = farbe
		streifen.emission_enabled = true
		streifen.emission = farbe
		streifen.emission_energy_multiplier = 0.8
		var duese := StandardMaterial3D.new()
		duese.albedo_color = Color(0.12, 0.12, 0.13)
		duese.metallic = 0.7
		var kopf := StandardMaterial3D.new()
		kopf.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		kopf.albedo_color = farbe.lerp(Color.WHITE, 0.5) * 1.8
		_mat[id] = {"Huelle": huelle, "Streifen": streifen, "Duese": duese, "Kopf": kopf}
	for mi: MeshInstance3D in m.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for s in mi.mesh.get_surface_count():
			var alt := mi.mesh.surface_get_material(s)
			var n := alt.resource_name if alt else ""
			for k in _mat[id]:
				if n.begins_with(k):
					mi.set_surface_override_material(s, _mat[id][k])
	return m


## Explosion ohne Ton (der kommt aus Effekte.explosion). groesse wie bisher: ≤1,5 Einschlag, ≤5 mittel, darüber groß.
static func explosion(eltern: Node, pos: Vector3, farbe: Color, groesse: float) -> Node3D:
	var wurzel := Node3D.new()
	eltern.add_child(wurzel)
	wurzel.global_position = pos
	var klein := groesse <= 1.5
	var hell := Color(farbe.r * 1.5, farbe.g * 1.5, farbe.b * 1.5)
	# 1 Blitz: weiß, sehr kurz
	var blitz := _schein(wurzel, Color(1.0, 0.95, 0.85, 0.9), groesse * (0.9 if klein else 0.7))
	var tw := wurzel.create_tween().set_parallel()
	tw.tween_property(blitz, "scale", Vector3.ONE * 1.4, 0.12)
	tw.tween_property(blitz.material_override, "albedo_color:a", 0.0, 0.14)
	# 2 Feuerball: weicher Schein in der Farbe, wächst und verblasst; kleine Einschläge nur ein farbiger Hauch
	if klein:
		var hauch := _schein(wurzel, Color(hell, 0.7), groesse * 0.8)
		hauch.scale = Vector3.ONE * 0.4
		tw.tween_property(hauch, "scale", Vector3.ONE, 0.18).set_ease(Tween.EASE_OUT)
		tw.tween_property(hauch.material_override, "albedo_color:a", 0.0, 0.25)
	else:
		# versetzte Glutwolken: der Feuerball ist keine glatte Scheibe
		for i in 5:
			var r := Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5).normalized() * groesse * 0.22
			var w := _schein(wurzel, Color(farbe.lerp(Color(1, 0.5, 0.15), 0.4) * 1.4, 0.6), groesse * 0.5, r * 0.3)
			w.scale = Vector3.ONE * 0.3
			tw.tween_property(w, "position", r * 1.6, 0.45).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
			tw.tween_property(w, "scale", Vector3.ONE, 0.4).set_ease(Tween.EASE_OUT)
			tw.tween_property(w.material_override, "albedo_color:a", 0.0, 0.5).set_delay(0.05)
		for schicht in [[hell, 1.0, 0.4], [farbe.lerp(Color(1, 0.85, 0.5), 0.5) * 1.6, 0.55, 0.3]]:
			var fb := _schein(wurzel, Color(schicht[0], 0.75), groesse * schicht[1])
			fb.scale = Vector3.ONE * 0.25
			tw.tween_property(fb, "scale", Vector3.ONE, schicht[2]).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
			tw.tween_property(fb.material_override, "albedo_color:a", 0.0, schicht[2] + 0.15).set_delay(0.08)
	# 3 Funken
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 6 if klein else (14 if groesse <= 5.0 else 24)
	p.lifetime = 0.35 if klein else 0.55
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 3.0 + groesse * 1.2
	p.initial_velocity_max = 6.0 + groesse * 2.2
	p.gravity = Vector3(0, -4.0, 0)
	p.damping_min = 2.0
	p.damping_max = 4.0
	p.particle_flag_align_y = true
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.0
	var fm := BoxMesh.new()
	fm.size = Vector3(0.04, 0.35, 0.04)
	var fmat := StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.vertex_color_use_as_albedo = true
	fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.material = fmat
	p.mesh = fm
	var verlauf := Gradient.new()
	verlauf.colors = PackedColorArray([Color(1, 0.95, 0.8, 1), Color(hell, 0.9), Color(farbe, 0.0)])
	verlauf.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	p.color_ramp = verlauf
	p.emitting = true
	wurzel.add_child(p)
	# 4 Druckwelle: Ring, ab mittlerer Größe
	if groesse > 2.5:
		var rq := QuadMesh.new()
		rq.size = Vector2.ONE * groesse * 1.6
		var r := _teil(wurzel, rq, leucht(Color(hell, 0.55), ring(), true))
		r.scale = Vector3.ONE * 0.2
		tw.tween_property(r, "scale", Vector3.ONE, 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(r.material_override, "albedo_color:a", 0.0, 0.4)
	# 5 Licht wie bisher
	var licht := OmniLight3D.new()
	licht.light_color = farbe
	licht.omni_range = groesse * (2.5 if klein else 4.0)
	licht.light_energy = 0.6 if klein else 2.2
	wurzel.add_child(licht)
	tw.tween_property(licht, "light_energy", 0.0, 0.5)
	tw.chain().tween_interval(0.15)
	tw.chain().tween_callback(wurzel.queue_free)
	return wurzel
