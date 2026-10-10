class_name Beute
extends Area3D
## Aufsammelbares: Erz (Währung), Schild, Energie, Raketen.

const ARTEN := {
	"erz": {"farbe": Color(1.0, 0.8, 0.2), "menge": 5},
	"schild": {"farbe": Color(0.3, 0.6, 1.0), "menge": 25},
	"energie": {"farbe": Color(0.85, 1.0, 0.3), "menge": 30},
	"rakete": {"farbe": Color(1.0, 0.3, 0.3), "menge": 2},
}

var art := "erz"
var menge := 5
var _t := 0.0
var _mesh: MeshInstance3D


static func neu(p_art: String, pos: Vector3, p_menge := -1) -> Beute:
	var b := Beute.new()
	b.art = p_art
	b.menge = p_menge if p_menge > 0 else int(ARTEN[p_art].menge)
	b.position = pos
	b._t = randf() * 6.0
	return b


func _ready() -> void:
	collision_layer = 8
	collision_mask = 2
	var form := CollisionShape3D.new()
	var kugel := SphereShape3D.new()
	kugel.radius = 1.4
	form.shape = kugel
	add_child(form)
	var farbe: Color = ARTEN[art].farbe
	var m := StandardMaterial3D.new()
	m.albedo_color = farbe
	m.emission_enabled = true
	m.emission = farbe
	m.emission_energy_multiplier = 2.0
	_mesh = MeshInstance3D.new()
	if art == "erz":
		var k := SphereMesh.new()   # grob facettiert: wie ein Kristall
		k.radius = 0.45
		k.height = 1.1
		k.radial_segments = 4
		k.rings = 2
		k.material = m
		_mesh.mesh = k
	else:
		var b := BoxMesh.new()
		b.size = Vector3(0.7, 0.7, 0.7)
		b.material = m
		_mesh.mesh = b
	add_child(_mesh)
	var l := OmniLight3D.new()
	l.light_color = farbe
	l.omni_range = 3.5
	l.light_energy = 0.8
	add_child(l)
	body_entered.connect(_rein)


func _process(dt: float) -> void:
	_t += dt
	_mesh.rotation.y = _t * 2.0
	_mesh.position.y = sin(_t * 2.5) * 0.2


func _rein(k: Node3D) -> void:
	if k.has_method("aufnehmen") and k.aufnehmen(art, menge):
		queue_free()
