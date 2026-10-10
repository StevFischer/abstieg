class_name Ausgang
extends Area3D
## Der Ausstiegsschacht im Startraum: ein Wirbel in einem achteckigen Stahlrahmen.
## Verschlossen dreht er sich träge und rot; nach der Reaktorzerstörung wird er grün, wirbelt schnell
## und saugt Funken nach innen. Hineinfliegen führt eine Tiefe tiefer.

signal erreicht

const WIRBEL := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform vec4 farbe : source_color = vec4(1.0, 0.2, 0.1, 1.0);
uniform float tempo = 1.0;
uniform float staerke = 0.5;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) { discard; }
	float a = atan(p.y, p.x);
	float spirale = 0.5 + 0.5 * sin(a * 5.0 + r * 16.0 - TIME * tempo);
	float kern = pow(1.0 - r, 0.7);
	float rand = smoothstep(0.8, 1.0, r) * (1.0 - smoothstep(0.97, 1.0, r));
	float v = (spirale * 0.75 + 0.25) * kern * staerke + rand * 0.9;
	ALBEDO = farbe.rgb * v;
}
"""

var offen := false
var _wirbel_mat: ShaderMaterial
var _lichter_mat: StandardMaterial3D
var _ringe: Array[MeshInstance3D] = []
var _funken: GPUParticles3D
var _licht: OmniLight3D
var _t := 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	var form := CollisionShape3D.new()
	var kugel := SphereShape3D.new()
	kugel.radius = 2.2
	form.shape = kugel
	add_child(form)

	# Wirbelscheibe
	var scheibe := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(4.4, 4.4)
	_wirbel_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = WIRBEL
	_wirbel_mat.shader = sh
	quad.material = _wirbel_mat
	scheibe.mesh = quad
	add_child(scheibe)

	# Achteckiger Stahlrahmen mit Signallampen
	var stahl := StandardMaterial3D.new()
	stahl.albedo_color = Color(0.3, 0.3, 0.33)
	stahl.metallic = 0.4
	stahl.roughness = 0.45
	_lichter_mat = StandardMaterial3D.new()
	_lichter_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for i in 8:
		var w := TAU * i / 8.0
		var balken := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(1.85, 0.32, 0.5)
		b.material = stahl
		balken.mesh = b
		balken.position = Vector3(cos(w + TAU / 16.0), sin(w + TAU / 16.0), 0) * 2.35
		balken.rotation.z = w + TAU / 16.0 + PI / 2.0
		add_child(balken)
		var lampe := MeshInstance3D.new()
		var k := BoxMesh.new()
		k.size = Vector3(0.22, 0.22, 0.56)
		k.material = _lichter_mat
		lampe.mesh = k
		lampe.position = Vector3(cos(w), sin(w), 0) * 2.55
		add_child(lampe)

	# Zwei dünne Ringe, die in verschiedene Richtungen kreisen
	for i in 2:
		var ring := MeshInstance3D.new()
		var t := TorusMesh.new()
		t.inner_radius = 2.7 + i * 0.3
		t.outer_radius = 2.78 + i * 0.3
		t.rings = 48
		t.material = _lichter_mat
		ring.mesh = t
		ring.rotation.x = PI / 2.0
		add_child(ring)
		_ringe.append(ring)

	# Funken, die nach innen gesogen werden (nur offen)
	_funken = GPUParticles3D.new()
	_funken.amount = 70
	_funken.lifetime = 0.9
	_funken.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3(0, 0, 1)
	pm.emission_ring_radius = 2.4
	pm.emission_ring_inner_radius = 2.1
	pm.emission_ring_height = 0.2
	pm.gravity = Vector3.ZERO
	pm.radial_accel_min = -9.0
	pm.radial_accel_max = -6.0
	pm.tangential_accel_min = 3.0
	pm.tangential_accel_max = 5.0
	pm.scale_min = 0.6
	pm.scale_max = 1.0
	_funken.process_material = pm
	var funke := QuadMesh.new()
	funke.size = Vector2(0.12, 0.12)
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fm.albedo_color = Color(0.6, 2.0, 0.8)
	funke.material = fm
	_funken.draw_pass_1 = funke
	add_child(_funken)

	_licht = OmniLight3D.new()
	_licht.omni_range = 10.0
	add_child(_licht)
	_zustand_zeigen()
	body_entered.connect(_rein)


func _zustand_zeigen() -> void:
	var farbe := Color(0.4, 1.6, 0.6) if offen else Color(1.3, 0.2, 0.12)
	_wirbel_mat.set_shader_parameter("farbe", farbe)
	_wirbel_mat.set_shader_parameter("tempo", 7.0 if offen else 1.2)
	_wirbel_mat.set_shader_parameter("staerke", 0.9 if offen else 0.35)
	_lichter_mat.albedo_color = farbe
	_licht.light_color = Color(0.3, 1.0, 0.4) if offen else Color(1.0, 0.2, 0.1)
	_licht.light_energy = 2.2 if offen else 1.0
	_funken.emitting = offen


func _process(dt: float) -> void:
	_t += dt
	rotation.y += dt * (0.5 if offen else 0.15)
	_ringe[0].rotation.y += dt * (2.4 if offen else 0.4)
	_ringe[1].rotation.x += dt * (1.7 if offen else 0.3)
	_lichter_mat.albedo_color.a = 1.0
	if offen:
		_licht.light_energy = 1.8 + sin(_t * 6.0) * 0.6


func oeffnen() -> void:
	offen = true
	_zustand_zeigen()
	for k in get_overlapping_bodies():
		_rein(k)


func _rein(k: Node3D) -> void:
	if offen and k is Schiff:
		erreicht.emit()
