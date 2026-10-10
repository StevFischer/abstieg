class_name Geschoss
extends Node3D
## Laserbolzen und Raketen. Treffer per Strahl von der alten zur neuen Lage —
## so fliegt auch ein schnelles Geschoss nicht durch eine dünne Wand.

const EBENE_WELT := 1
const EBENE_SPIELER := 2
const EBENE_GEGNER := 4

var geschw := Vector3.ZERO
var schaden := 10.0
var vom_spieler := true
var lebenszeit := 3.0
var lenkung := 0.0        ## > 0: Zielsuchrakete, Wendigkeit je Sekunde
var farbe := Color.RED
var knall := -1.0         ## Explosionsgröße beim Einschlag; < 0: nach Art (Laser klein, Rakete mittel)
var flaeche := 0.0        ## > 0: Flächenschaden in diesem Radius, nimmt nach außen ab (trifft auch das eigene Schiff)
var splitter := 0         ## > 0: beim Einschlag so viele kleine Zielsucher
var rundum := false       ## Zielsuche in alle Richtungen (Splitter), sonst nur nach vorn
var _ziel: Node3D


static func neu(pos: Vector3, richtung: Vector3, tempo: float, p_schaden: float, p_vom_spieler: bool,
		p_farbe: Color, p_lenkung := 0.0, groesse := 1.0) -> Geschoss:
	var g := Geschoss.new()
	g.position = pos
	g.geschw = richtung.normalized() * tempo
	g.schaden = p_schaden
	g.vom_spieler = p_vom_spieler
	g.farbe = p_farbe
	g.lenkung = p_lenkung
	if p_lenkung > 0.0 or tempo < 40.0:
		g.lebenszeit = 6.0      # Raketen und langsame Gegnerschüsse brauchen länger für dieselbe Strecke
	var mi := MeshInstance3D.new()
	var kapsel := CapsuleMesh.new()
	kapsel.radius = 0.09 * groesse
	kapsel.height = 0.9 * groesse
	kapsel.radial_segments = 6
	kapsel.rings = 2
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(p_farbe.r * 2.2, p_farbe.g * 2.2, p_farbe.b * 2.2)
	kapsel.material = m
	mi.mesh = kapsel
	mi.rotation.x = PI / 2.0
	g.add_child(mi)
	var l := OmniLight3D.new()
	l.light_color = p_farbe
	l.omni_range = 4.0 * groesse
	l.light_energy = 0.8
	g.add_child(l)
	return g


func _ready() -> void:
	if vom_spieler:
		add_to_group("spieler_geschoss")      # Gegner sehen sie kommen und weichen aus
	_ausrichten()


func _physics_process(dt: float) -> void:
	lebenszeit -= dt
	if lebenszeit <= 0.0:
		queue_free()
		return
	if lenkung > 0.0:
		_lenken(dt)
	var von := global_position
	var nach := von + geschw * dt
	var maske := EBENE_WELT | (EBENE_GEGNER if vom_spieler else EBENE_SPIELER)
	var q := PhysicsRayQueryParameters3D.create(von, nach, maske)
	var treffer := get_world_3d().direct_space_state.intersect_ray(q)
	if not treffer.is_empty():
		var obj: Object = treffer.collider
		if obj != null and flaeche <= 0.0:
			if obj.has_method("treffer_von"):
				obj.treffer_von(schaden, geschw)
			elif obj.has_method("treffer"):
				obj.treffer(schaden)
		var groesse := knall if knall > 0.0 else (4.0 if lenkung > 0.0 else 1.2)
		Effekte.explosion(get_parent(), treffer.position, farbe, groesse)
		if flaeche > 0.0:
			_flaechenschaden(treffer.position)
		if splitter > 0:
			_zersplittern(treffer.position, treffer.normal)
		queue_free()
		return
	global_position = nach
	_ausrichten()


func _flaechenschaden(mitte: Vector3) -> void:
	var opfer := get_tree().get_nodes_in_group("ziele") + get_tree().get_nodes_in_group("minen") \
		+ get_tree().get_nodes_in_group("spieler")
	for o in opfer:
		var d: float = o.global_position.distance_to(mitte)
		if d < flaeche and o.has_method("treffer"):
			o.treffer(schaden * (1.0 - d / flaeche * 0.7))


func _zersplittern(mitte: Vector3, normale: Vector3) -> void:
	for i in splitter:
		# enger Fächer weg von der Einschlagstelle; langsam und sehr wendig (Wendekreis ~2 m),
		# sonst prallen sie in einem 6 m hohen Raum gegen die Wand, bevor sie umdrehen
		var r := (normale + Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 1.2).normalized()
		var g := Geschoss.neu(mitte + normale * 0.6, r, 20.0, schaden * 0.4, true, farbe, 10.0, 0.9)
		g.lebenszeit = 4.0
		g.rundum = true
		get_parent().add_child.call_deferred(g)


func _ausrichten() -> void:
	if geschw.length_squared() < 0.01:
		return
	var vor := geschw.normalized()
	var oben := Vector3.UP if absf(vor.y) < 0.95 else Vector3.FORWARD
	global_basis = Basis.looking_at(vor, oben)


func _lenken(dt: float) -> void:
	if _ziel == null or not is_instance_valid(_ziel) or not _ziel.is_in_group("ziele"):
		_ziel = null
		var beste := 70.0
		var vor := geschw.normalized()
		for z in get_tree().get_nodes_in_group("ziele"):
			var weg: Vector3 = z.global_position - global_position
			var d := weg.length()
			if d < beste and (rundum or vor.dot(weg / maxf(d, 0.01)) > 0.4):
				beste = d
				_ziel = z
	if _ziel == null:
		return
	var soll := (_ziel.global_position - global_position).normalized()
	var tempo := geschw.length()
	geschw = geschw.normalized().lerp(soll, clampf(lenkung * dt, 0.0, 1.0)).normalized() * tempo
