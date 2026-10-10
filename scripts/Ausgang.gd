class_name Ausgang
extends Area3D
## Der Ausstiegsschacht im Startraum. Rot und verschlossen, bis der Reaktor fällt.

signal erreicht

var offen := false
var _ring: MeshInstance3D
var _mat: StandardMaterial3D
var _flaeche: MeshInstance3D
var _licht: OmniLight3D


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	var form := CollisionShape3D.new()
	var kugel := SphereShape3D.new()
	kugel.radius = 2.2
	form.shape = kugel
	add_child(form)
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = Color(2.5, 0.3, 0.2)
	_ring = MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 1.6
	t.outer_radius = 2.0
	t.material = _mat
	_ring.mesh = t
	_ring.rotation.x = PI / 2.0
	add_child(_ring)
	_flaeche = MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 1.6
	c.bottom_radius = 1.6
	c.height = 0.05
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.albedo_color = Color(0.4, 2.0, 0.6, 0.45)
	c.material = fm
	_flaeche.mesh = c
	_flaeche.rotation.x = PI / 2.0
	_flaeche.visible = false
	add_child(_flaeche)
	_licht = OmniLight3D.new()
	_licht.light_color = Color(1.0, 0.2, 0.1)
	_licht.omni_range = 9.0
	_licht.light_energy = 1.5
	add_child(_licht)
	body_entered.connect(_rein)


func _process(dt: float) -> void:
	rotation.y += dt * (1.5 if offen else 0.3)


func oeffnen() -> void:
	offen = true
	_mat.albedo_color = Color(0.4, 2.5, 0.6)
	_licht.light_color = Color(0.3, 1.0, 0.4)
	_licht.light_energy = 3.0
	_flaeche.visible = true
	for k in get_overlapping_bodies():
		_rein(k)


func _rein(k: Node3D) -> void:
	if offen and k is Schiff:
		erreicht.emit()
