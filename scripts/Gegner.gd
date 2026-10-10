class_name Gegner
extends CharacterBody3D
## Minenroboter. Schweben ruhig, bis sie das Schiff sehen; danach jagen sie es,
## fliegen zur letzten bekannten Stelle, wenn die Sicht abreißt.

signal zerstoert(g: Gegner)

const TYPEN := {
	"jaeger": {"hp": 30.0, "schaden": 6.0, "cd": 1.1, "schuss": 16.0, "tempo": 9.0, "abstand": 11.0, "radius": 1.0,
		"farbe": Color(0.55, 0.14, 0.10), "auge": Color(1.0, 0.25, 0.1), "erz": 4},
	"geschuetz": {"hp": 55.0, "schaden": 9.0, "cd": 1.6, "schuss": 13.0, "tempo": 0.0, "abstand": 0.0, "radius": 1.0,
		"farbe": Color(0.42, 0.42, 0.47), "auge": Color(1.0, 0.6, 0.1), "erz": 5},
	"waechter": {"hp": 130.0, "schaden": 14.0, "cd": 2.0, "schuss": 11.0, "tempo": 4.5, "abstand": 6.0, "radius": 1.4,
		"farbe": Color(0.22, 0.36, 0.22), "auge": Color(0.3, 1.0, 0.3), "erz": 10},
}

var typ := "jaeger"
var hp := 30.0
var schaden := 6.0
var cd_basis := 1.0
var tempo := 9.0
var abstand := 10.0
var erz := 4
## Geschosstempo: wie im Original anfangs gemächlich (11–16 m/s, das Schiff fliegt 14),
## +8 % je Tiefe, höchstens doppelt so schnell wie am Anfang.
var schuss_tempo := 16.0
var ziel: Node3D
var welt: Node3D
var _cd := 1.5
var _sicht := false
var _sicht_t := 0.0
var _alarm := false
var _letzte := Vector3.ZERO
var _zeit := 0.0
var _tot := false
var _mat: StandardMaterial3D
var _auge: Color


func einrichten(p_typ: String, stufe: int) -> void:
	typ = p_typ
	var d: Dictionary = TYPEN[typ]
	var f := 1.0 + 0.18 * (stufe - 1)
	hp = d.hp * f
	schaden = d.schaden * (1.0 + 0.1 * (stufe - 1))
	cd_basis = d.cd / (1.0 + 0.05 * (stufe - 1))
	tempo = d.tempo * minf(1.0 + 0.03 * (stufe - 1), 1.8)
	abstand = d.abstand
	erz = int(d.erz) + stufe
	schuss_tempo = d.schuss * minf(1.0 + 0.08 * (stufe - 1), 2.0)
	_auge = d.auge
	_zeit = randf() * 10.0
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	add_to_group("ziele")
	add_to_group("gegner")
	var form := CollisionShape3D.new()
	var kugel := SphereShape3D.new()
	kugel.radius = d.radius
	form.shape = kugel
	add_child(form)
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = d.farbe
	_mat.metallic = 0.6
	_mat.roughness = 0.4
	match typ:
		"jaeger":
			_teil(_box(Vector3(1.0, 0.5, 1.6)), Vector3.ZERO)
			_teil(_box(Vector3(2.6, 0.1, 0.7)), Vector3(0, 0, 0.3))
			_teil(_box(Vector3(0.1, 0.8, 0.6)), Vector3(1.3, 0, 0.3))
			_teil(_box(Vector3(0.1, 0.8, 0.6)), Vector3(-1.3, 0, 0.3))
			_leuchte(0.18, Vector3(0, 0, -0.82))
		"geschuetz":
			var k := SphereMesh.new()
			k.radius = 0.9
			k.height = 1.8
			k.radial_segments = 10
			k.rings = 6
			_teil(k, Vector3.ZERO)
			var rohr := CylinderMesh.new()
			rohr.top_radius = 0.15
			rohr.bottom_radius = 0.2
			rohr.height = 1.3
			var r := _teil(rohr, Vector3(0, -0.15, -0.9))
			r.rotation.x = PI / 2.0
			_leuchte(0.22, Vector3(0, 0.35, -0.75))
		"waechter":
			_teil(_box(Vector3(2.0, 2.0, 2.0)), Vector3.ZERO)
			for x in [-1.0, 1.0]:
				for y in [-1.0, 1.0]:
					_teil(_box(Vector3(0.4, 0.4, 2.4)), Vector3(x, y, 0))
			_leuchte(0.38, Vector3(0, 0, -1.02))


func _box(g: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = g
	return b


func _teil(mesh: Mesh, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat
	mi.position = pos
	add_child(mi)
	return mi


func _leuchte(r: float, pos: Vector3) -> void:
	var k := SphereMesh.new()
	k.radius = r
	k.height = r * 2.0
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(_auge.r * 3.0, _auge.g * 3.0, _auge.b * 3.0)
	k.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = k
	mi.position = pos
	add_child(mi)


func _physics_process(dt: float) -> void:
	if _tot or ziel == null or not is_instance_valid(ziel):
		return
	_zeit += dt
	_cd -= dt
	_sicht_t -= dt
	var zum := ziel.global_position - global_position
	var dist := zum.length()
	if _sicht_t <= 0.0:
		_sicht_t = 0.25
		_sicht = dist < 55.0 and _frei(ziel.global_position)
	if _sicht:
		_alarm = true
		_letzte = ziel.global_position
	var soll_v := Vector3(0, sin(_zeit * 1.7) * 0.4, 0)
	if _alarm:
		_drehen_zu(ziel.global_position if _sicht else _letzte, dt)
		if tempo > 0.0:
			if _sicht:
				var r := zum / maxf(dist, 0.01)
				soll_v = Vector3.ZERO
				if dist > abstand + 2.0:
					soll_v = r * tempo
				elif dist < abstand - 2.0:
					soll_v = -r * tempo
				if typ == "jaeger":
					soll_v += global_basis.x * sin(_zeit * 1.3) * tempo * 0.6
			else:
				var w := _letzte - global_position
				soll_v = w.normalized() * tempo if w.length() > 2.0 else Vector3.ZERO
		if _sicht and _cd <= 0.0 and (-global_basis.z).dot(zum / maxf(dist, 0.01)) > 0.85:
			_schiessen()
			_cd = cd_basis * randf_range(0.8, 1.3)
	velocity = velocity.lerp(soll_v, 1.0 - exp(-3.0 * dt))
	move_and_slide()


func _frei(p: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(global_position, p, 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _drehen_zu(p: Vector3, dt: float) -> void:
	var vor := p - global_position
	if vor.length_squared() < 0.01:
		return
	vor = vor.normalized()
	var oben := Vector3.UP if absf(vor.y) < 0.95 else Vector3.FORWARD
	var rate := 2.0 if typ == "geschuetz" else 3.5
	global_basis = global_basis.slerp(Basis.looking_at(vor, oben), minf(1.0, rate * dt)).orthonormalized()


func _schiessen() -> void:
	if welt == null:
		return
	var start := global_position - global_basis.z * 1.4
	var richtung := (ziel.global_position - start).normalized()
	richtung = (richtung + Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 0.06).normalized()
	welt.add_child(Geschoss.neu(start, richtung, schuss_tempo, schaden, false, _auge))
	Effekte.ton("laser_gegner", start, -4.0)


func treffer(s: float) -> void:
	if _tot:
		return
	hp -= s
	_alarm = true
	if ziel != null and is_instance_valid(ziel):
		_letzte = ziel.global_position
	var alt := _mat.albedo_color
	_mat.albedo_color = Color.WHITE
	create_tween().tween_property(_mat, "albedo_color", alt, 0.15)
	if hp <= 0.0:
		_tot = true
		remove_from_group("ziele")
		Effekte.explosion(get_parent(), global_position, Color(1.0, 0.6, 0.2), 3.5)
		zerstoert.emit(self)
		queue_free()
