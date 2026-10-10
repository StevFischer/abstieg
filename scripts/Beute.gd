class_name Beute
extends Area3D
## Aufsammelbares. Jede Art hat eine eigene Form (auch ohne Farbe erkennbar) und ein
## Schild mit Name und Menge darüber, das aus der Nähe sichtbar wird.
## Erz (Kristallbündel), Schild (Kugel mit Ring), Reparatur (Kreuz), Rakete.

const ARTEN := {
	"erz": {"farbe": Color(1.0, 0.8, 0.2), "menge": 5, "name": "ERZ"},
	"schild": {"farbe": Color(0.3, 0.6, 1.0), "menge": 25, "name": "SCHILD"},
	"reparatur": {"farbe": Color(0.3, 1.0, 0.45), "menge": 30, "name": "HÜLLE"},
	"rakete": {"farbe": Color(1.0, 0.3, 0.3), "menge": 2, "name": "RAKETEN"},
	"modul": {"farbe": Color(0.75, 0.75, 0.75), "menge": 1, "name": "MODUL"},
	"kristall": {"farbe": Color(0.75, 0.4, 1.0), "menge": 3, "name": "KRISTALLE"},
}
const SICHTWEITE := 30.0   ## ab hier erscheint das Namensschild

var art := "erz"
var modul := {}     ## nur bei art "modul": das Modul selbst (Module.gd)
var menge := 5
var _t := 0.0
var _form: Node3D
var _mat: StandardMaterial3D
var _glanz: StandardMaterial3D


static func neu(p_art: String, pos: Vector3, p_menge := -1) -> Beute:
	var b := Beute.new()
	b.art = p_art
	b.menge = p_menge if p_menge > 0 else int(ARTEN[p_art].menge)
	b.position = pos
	b._t = randf() * 6.0
	return b


static func beschriftung(p_art: String, p_menge: int) -> String:
	return "%s +%d" % [ARTEN[p_art].name, p_menge]


## Aufnahmekugel. Mit dem Schiffsradius 0,9 m wird Beute bis 4,6 m Mittelpunktabstand eingesammelt
## (vorher 1,4 → 2,3 m; Stev 2026-10-10: „verdoppele die Einsammelreichweite“).
const SAMMEL_RADIUS := 3.7


func _ready() -> void:
	collision_layer = 8
	collision_mask = 2
	var form := CollisionShape3D.new()
	var kugel := SphereShape3D.new()
	kugel.radius = SAMMEL_RADIUS
	form.shape = kugel
	add_child(form)
	var farbe: Color = Module.farbe(modul) if art == "modul" else ARTEN[art].farbe
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = farbe
	_mat.metallic = 0.4
	_mat.roughness = 0.35
	_mat.emission_enabled = true
	_mat.emission = farbe
	_mat.emission_energy_multiplier = 0.9
	_glanz = StandardMaterial3D.new()
	_glanz.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glanz.albedo_color = Color(farbe.r * 1.6, farbe.g * 1.6, farbe.b * 1.6)
	_form = Node3D.new()
	add_child(_form)
	match art:
		"erz":
			for w in [Vector3(0, 0, 0), Vector3(0.5, 0, 0.6), Vector3(-0.5, 0, -0.4), Vector3(0.1, 0, -0.7)]:
				var k := _teil(_kristall(0.22, 0.9), Vector3(w.x * 0.35, -0.1, w.z * 0.35))
				k.rotation = Vector3(w.x, randf() * TAU, w.z)
		"schild":
			var blase := SphereMesh.new()
			blase.radius = 0.45
			blase.height = 0.9
			_teil(blase, Vector3.ZERO)
			var ring := TorusMesh.new()
			ring.inner_radius = 0.6
			ring.outer_radius = 0.72
			_teil(ring, Vector3.ZERO, _glanz).rotation.x = PI / 2.0
			var ring2 := TorusMesh.new()
			ring2.inner_radius = 0.6
			ring2.outer_radius = 0.72
			_teil(ring2, Vector3.ZERO, _glanz).rotation.z = PI / 2.0
		"reparatur":
			_teil(_box(Vector3(0.3, 1.0, 0.3)), Vector3.ZERO)
			_teil(_box(Vector3(1.0, 0.3, 0.3)), Vector3.ZERO)
			_teil(_box(Vector3(0.36, 0.36, 0.36)), Vector3.ZERO, _glanz)
		"kristall":      # drei lange, schlanke Spitzen — anders als das gedrungene Erzbündel
			for w in [Vector3(0, 0, 0), Vector3(0.35, 0, 0.2), Vector3(-0.3, 0, -0.25)]:
				var k := _teil(_kristall(0.14, 1.4), Vector3(w.x * 0.6, 0.1, w.z * 0.6), _glanz if w == Vector3.ZERO else null)
				k.rotation = Vector3(w.z * 0.6, randf() * TAU, -w.x * 0.6)
		"modul":         # Kasten mit leuchtendem Rahmen in der Seltenheitsfarbe
			_teil(_box(Vector3(0.7, 0.45, 0.7)), Vector3.ZERO)
			for y in [-0.25, 0.25]:
				_teil(_box(Vector3(0.82, 0.07, 0.82)), Vector3(0, y, 0), _glanz)
			_teil(_box(Vector3(0.2, 0.2, 0.86)), Vector3.ZERO, _glanz)
		"rakete":
			for x in [-0.22, 0.22]:
				var rumpf := CylinderMesh.new()
				rumpf.top_radius = 0.12
				rumpf.bottom_radius = 0.12
				rumpf.height = 0.8
				_teil(rumpf, Vector3(x, -0.05, 0))
				var spitze := CylinderMesh.new()
				spitze.top_radius = 0.0
				spitze.bottom_radius = 0.12
				spitze.height = 0.3
				_teil(spitze, Vector3(x, 0.5, 0), _glanz)
				_teil(_box(Vector3(0.36, 0.22, 0.04)), Vector3(x, -0.38, 0))
	_form.scale = Vector3.ONE * 1.3

	var schild := Label3D.new()
	schild.text = Module.name_von(modul) if art == "modul" else beschriftung(art, menge)
	schild.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	schild.font_size = 40
	schild.outline_size = 12
	# Schrumpft mit der Entfernung (Tiefenwirkung, Schilder überdecken sich nicht), aber groß genug:
	# bei 1080p etwa 33 Pixel hoch aus 8 m, 18 Pixel aus 15 m.
	schild.pixel_size = 0.012
	schild.modulate = farbe.lerp(Color.WHITE, 0.35)
	schild.outline_modulate = Color(0, 0, 0, 0.85)
	schild.position = Vector3(0, 1.7, 0)
	schild.visibility_range_end = SICHTWEITE
	schild.visibility_range_end_margin = 4.0
	schild.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(schild)

	var l := OmniLight3D.new()
	l.light_color = farbe
	l.omni_range = 4.0
	l.light_energy = 1.0
	add_child(l)
	add_to_group("beute_" + art)
	add_to_group("beute")
	body_entered.connect(_rein)


func _box(g: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = g
	return b


func _kristall(r: float, h: float) -> SphereMesh:
	var k := SphereMesh.new()   # vier Seiten, zwei Ringe: eine spitze Doppelpyramide
	k.radius = r
	k.height = h
	k.radial_segments = 4
	k.rings = 2
	return k


func _teil(mesh: Mesh, pos: Vector3, mat: Material = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat if mat != null else _mat
	mi.position = pos
	_form.add_child(mi)
	return mi


func _process(dt: float) -> void:
	_t += dt
	_form.rotation.y = _t * 1.6
	_form.position.y = sin(_t * 2.5) * 0.15


func _rein(k: Node3D) -> void:
	if art == "modul":
		if k is Schiff:
			k.modul_gefunden.emit(modul)
			queue_free()
		return
	if k.has_method("aufnehmen") and k.aufnehmen(art, menge):
		queue_free()
