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
	m.albedo_color = Color(p_farbe.r * 4.0, p_farbe.g * 4.0, p_farbe.b * 4.0)
	kapsel.material = m
	mi.mesh = kapsel
	mi.rotation.x = PI / 2.0
	g.add_child(mi)
	var l := OmniLight3D.new()
	l.light_color = p_farbe
	l.omni_range = 4.0 * groesse
	l.light_energy = 1.2
	g.add_child(l)
	return g


func _ready() -> void:
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
		if obj != null and obj.has_method("treffer"):
			obj.treffer(schaden)
		Effekte.explosion(get_parent(), treffer.position, farbe, 4.0 if lenkung > 0.0 else 1.2)
		queue_free()
		return
	global_position = nach
	_ausrichten()


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
			if d < beste and vor.dot(weg / maxf(d, 0.01)) > 0.4:
				beste = d
				_ziel = z
	if _ziel == null:
		return
	var soll := (_ziel.global_position - global_position).normalized()
	var tempo := geschw.length()
	geschw = geschw.normalized().lerp(soll, clampf(lenkung * dt, 0.0, 1.0)).normalized() * tempo
