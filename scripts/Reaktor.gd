class_name Reaktor
extends StaticBody3D
## Der Kern der Mine. Zerstört startet er die Selbstzerstörung.

signal zerstoert

var hp := 350.0
var hp_max := 350.0
var ziel: Node3D
var welt: Node3D
var farbe := Color(1.0, 0.5, 0.1)
var kaputt := false
var geschirmt := false          ## Boss-Tiefe: unverwundbar, bis der Boss besiegt ist
var _schirm: MeshInstance3D
var _kern: MeshInstance3D
var _kmat: StandardMaterial3D
var _licht: OmniLight3D
var _cd := 3.0
var _t := 0.0


func einrichten(stufe: int, p_farbe: Color) -> void:
	farbe = p_farbe
	hp_max = 350.0 * (1.0 + 0.2 * (stufe - 1))
	hp = hp_max
	collision_layer = 4
	collision_mask = 0
	add_to_group("ziele")
	var form := CollisionShape3D.new()
	var kugel := SphereShape3D.new()
	kugel.radius = 2.5
	form.shape = kugel
	add_child(form)
	_kern = MeshInstance3D.new()
	var k := SphereMesh.new()
	k.radius = 1.5
	k.height = 3.0
	_kmat = StandardMaterial3D.new()
	_kmat.albedo_color = farbe
	_kmat.emission_enabled = true
	_kmat.emission = farbe
	_kmat.emission_energy_multiplier = 1.8
	k.material = _kmat
	_kern.mesh = k
	add_child(_kern)
	var metall := StandardMaterial3D.new()
	metall.albedo_color = Color(0.22, 0.22, 0.24)
	metall.metallic = 0.8
	metall.roughness = 0.35
	for i in 8:
		var stab := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.25, 4.6, 0.25)
		b.material = metall
		stab.mesh = b
		var w := TAU * i / 8.0
		stab.position = Vector3(cos(w) * 2.3, 0, sin(w) * 2.3)
		add_child(stab)
	for y in [-2.4, 2.4]:
		var ring := MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.top_radius = 2.6
		c.bottom_radius = 2.6
		c.height = 0.4
		c.material = metall
		ring.mesh = c
		ring.position.y = y
		add_child(ring)
	_licht = OmniLight3D.new()
	_licht.light_color = farbe
	_licht.omni_range = 20.0
	_licht.light_energy = 2.5
	add_child(_licht)


func _process(dt: float) -> void:
	_t += dt
	if kaputt:
		_licht.light_energy = 1.0 + randf() * 1.5
		return
	var tempo := 3.0 + 6.0 * (1.0 - hp / hp_max)
	_kmat.emission_energy_multiplier = 1.5 + sin(_t * tempo) * 0.7
	_licht.light_energy = 1.7 + sin(_t * tempo) * 0.5


func _physics_process(dt: float) -> void:
	if kaputt or ziel == null or welt == null or not is_instance_valid(ziel):
		return
	_cd -= dt
	if _cd > 0.0:
		return
	_cd = 1.8
	var weg := ziel.global_position - global_position
	if weg.length() > 45.0:
		return
	var start := global_position + weg.normalized() * 3.0
	var q := PhysicsRayQueryParameters3D.create(start, ziel.global_position, 1)
	if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
		return
	Effekte.ton("laser_gegner", start, 0.0)
	for i in 3:
		var r := (ziel.global_position - start).normalized()
		r = (r + Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 0.12).normalized()
		welt.add_child(Geschoss.neu(start, r, 30.0, 8.0, false, farbe, 0.0, 1.4))


func schirm_an() -> void:
	geschirmt = true
	_schirm = MeshInstance3D.new()
	var k := SphereMesh.new()
	k.radius = 3.4
	k.height = 6.8
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.4, 0.7, 1.6, 0.22)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	k.material = m
	_schirm.mesh = k
	add_child(_schirm)


func schirm_aus() -> void:
	geschirmt = false
	if _schirm:
		_schirm.queue_free()
		_schirm = null
	Effekte.explosion(get_parent(), global_position, Color(0.4, 0.7, 1.0), 7.0)


func treffer(s: float) -> void:
	if kaputt:
		return
	if geschirmt:
		Effekte.explosion(get_parent(), global_position + Vector3(0, 0, 0), Color(0.4, 0.7, 1.0), 1.0)
		return
	hp -= s
	if hp <= 0.0:
		kaputt = true
		remove_from_group("ziele")
		_kern.visible = false
		_licht.light_color = Color(1.0, 0.2, 0.1)
		Effekte.explosion(get_parent(), global_position, farbe, 9.0)
		zerstoert.emit()
