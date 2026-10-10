class_name Mine
extends StaticBody3D
## Vom Minenleger gelegt. Steht still, blinkt; fliegt das Schiff näher als AUSLOESER heran,
## explodiert sie nach kurzer Verzögerung. Abschießbar (ein Lasertreffer genügt).

const AUSLOESER := 4.5
const WIRKUNG := 6.0
const LEBENSZEIT := 45.0

var schaden := 18.0
var _t := 0.0
var _scharf := -1.0        ## >= 0: Zündung läuft
var _weg := false
var _mat: StandardMaterial3D
var _licht: OmniLight3D


static func neu(pos: Vector3, p_schaden: float) -> Mine:
	var m := Mine.new()
	m.position = pos
	m.schaden = p_schaden
	return m


func _ready() -> void:
	collision_layer = 4
	collision_mask = 0
	add_to_group("minen")
	var form := CollisionShape3D.new()
	var k := SphereShape3D.new()
	k.radius = 0.55
	form.shape = k
	add_child(form)
	# Dunkler Stahl mit roten Warnlichtern — darf nicht aussehen wie Beute (die leuchtet bunt und freundlich).
	var stahl := StandardMaterial3D.new()
	stahl.albedo_color = Color(0.16, 0.15, 0.15)
	stahl.metallic = 0.5
	stahl.roughness = 0.35
	var kern := MeshInstance3D.new()
	var kugel := SphereMesh.new()
	kugel.radius = 0.4
	kugel.height = 0.8
	kugel.radial_segments = 12
	kugel.rings = 8
	kugel.material = stahl
	kern.mesh = kugel
	add_child(kern)
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = Color(2.0, 0.05, 0.03)
	var band := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 0.38
	t.outer_radius = 0.45
	t.material = _mat
	band.mesh = t
	add_child(band)
	var schrift := Label3D.new()
	schrift.text = "MINE"
	schrift.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	schrift.font_size = 40
	schrift.outline_size = 12
	schrift.pixel_size = 0.012
	schrift.modulate = Color(1.0, 0.25, 0.2)
	schrift.outline_modulate = Color(0, 0, 0, 0.9)
	schrift.position = Vector3(0, 1.1, 0)
	schrift.visibility_range_end = 25.0
	add_child(schrift)
	for r in [Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK,
			Vector3(1, 1, 0).normalized(), Vector3(-1, 1, 0).normalized(), Vector3(0, 1, 1).normalized(), Vector3(0, 1, -1).normalized(),
			Vector3(1, -1, 0).normalized(), Vector3(-1, -1, 0).normalized(), Vector3(0, -1, 1).normalized(), Vector3(0, -1, -1).normalized()]:
		var dorn := MeshInstance3D.new()
		var kegel := CylinderMesh.new()
		kegel.top_radius = 0.0
		kegel.bottom_radius = 0.08
		kegel.height = 0.45
		kegel.radial_segments = 6
		kegel.material = stahl
		dorn.mesh = kegel
		dorn.position = r * 0.55
		dorn.basis = Basis(Quaternion(Vector3.UP, r)) if r != Vector3.DOWN else Basis(Vector3.RIGHT, PI)
		add_child(dorn)
	_licht = OmniLight3D.new()
	_licht.light_color = Color(1.0, 0.08, 0.05)
	_licht.omni_range = 4.0
	add_child(_licht)


func _physics_process(dt: float) -> void:
	if _weg:
		return
	_t += dt
	rotation.y += dt * 1.2
	var schiff := _schiff()
	var d := INF if schiff == null else global_position.distance_to(schiff.global_position)
	if _scharf < 0.0 and d < AUSLOESER:
		_scharf = 0.45       # kurze Zündverzögerung: wer schnell ist, kommt noch vorbei
	var takt := 10.0 if _scharf >= 0.0 else (5.0 if d < 12.0 else 1.6)
	var an := sin(_t * takt) > 0.0
	_mat.albedo_color = Color(2.0, 0.05, 0.03) if an else Color(0.25, 0.02, 0.02)
	_licht.light_energy = 1.4 if an else 0.1
	if _scharf >= 0.0:
		_scharf -= dt
		if _scharf <= 0.0:
			_explodieren(schiff, d)
	elif _t > LEBENSZEIT:
		_explodieren(null, INF)


func _schiff() -> Node3D:
	var s := get_tree().get_first_node_in_group("spieler")
	return s as Node3D


func treffer(_s: float) -> void:
	var schiff := _schiff()
	_explodieren(schiff, INF if schiff == null else global_position.distance_to(schiff.global_position))


func _explodieren(schiff: Node3D, d: float) -> void:
	if _weg:
		return
	_weg = true
	if schiff != null and d < WIRKUNG and schiff.has_method("treffer"):
		schiff.treffer(schaden * (1.0 - d / WIRKUNG * 0.5))
	Effekte.explosion(get_parent(), global_position, Color(1.0, 0.5, 0.15), 4.5)
	queue_free()
