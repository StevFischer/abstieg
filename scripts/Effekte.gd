class_name Effekte
extends RefCounted
## Explosionen: leuchtende Kugel, die aufbläht und verblasst, dazu ein kurzer Lichtblitz.


static func explosion(eltern: Node, pos: Vector3, farbe: Color, groesse: float) -> void:
	if eltern == null or not eltern.is_inside_tree():
		return
	var k := MeshInstance3D.new()
	var kugel := SphereMesh.new()
	kugel.radius = 0.5
	kugel.height = 1.0
	kugel.radial_segments = 10
	kugel.rings = 6
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(farbe.r * 3.0, farbe.g * 3.0, farbe.b * 3.0, 1.0)
	kugel.material = m
	k.mesh = kugel
	eltern.add_child(k)
	k.global_position = pos
	k.scale = Vector3.ONE * 0.2
	var licht := OmniLight3D.new()
	licht.light_color = farbe
	licht.omni_range = groesse * 4.0
	licht.light_energy = 4.0
	eltern.add_child(licht)
	licht.global_position = pos
	var tw := k.create_tween().set_parallel()
	tw.tween_property(k, "scale", Vector3.ONE * groesse, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.45)
	tw.tween_property(licht, "light_energy", 0.0, 0.5)
	tw.chain().tween_callback(func():
		k.queue_free()
		licht.queue_free())
