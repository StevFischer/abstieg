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
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = Color(3.0, 1.3, 0.3)
	var kern := MeshInstance3D.new()
	var kugel := SphereMesh.new()
	kugel.radius = 0.32
	kugel.height = 0.64
	kugel.radial_segments = 10
	kugel.rings = 6
	kugel.material = _mat
	kern.mesh = kugel
	add_child(kern)
	var stahl := StandardMaterial3D.new()
	stahl.albedo_color = Color(0.25, 0.24, 0.24)
	stahl.metallic = 0.8
	stahl.roughness = 0.4
	for r in [Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
		var dorn := MeshInstance3D.new()
		var kegel := CylinderMesh.new()
		kegel.top_radius = 0.0
		kegel.bottom_radius = 0.1
		kegel.height = 0.4
		kegel.radial_segments = 6
		kegel.material = stahl
		dorn.mesh = kegel
		dorn.position = r * 0.42
		dorn.basis = Basis(Quaternion(Vector3.UP, r)) if r != Vector3.DOWN else Basis(Vector3.RIGHT, PI)
		add_child(dorn)
	_licht = OmniLight3D.new()
	_licht.light_color = Color(1.0, 0.45, 0.1)
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
	_mat.albedo_color.a = 1.0
	_licht.light_energy = 1.6 if an else 0.2
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
