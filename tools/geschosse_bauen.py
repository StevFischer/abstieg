"""Baut die vier Raketenmodelle in Blender und exportiert je ein GLB nach assets/geschosse/.

Aufruf (ohne Fenster):
    blender -b --factory-startup --python tools/geschosse_bauen.py -- assets/geschosse [vorschau.png]

Vorne ist +Y (wird in Godot zu -Z), Länge etwa 1 m. Materialnamen sind die Schnittstelle zu Godot
(Optik.gd ersetzt sie): Huelle (helles Metall), Streifen (Farbe der Waffe, leuchtet schwach),
Duese (dunkel), Kopf (leuchtende Spitze/Sucherkopf).
"""
import bpy, math, sys, os

argv = sys.argv[sys.argv.index("--") + 1:]
AUS = os.path.abspath(argv[0])
VORSCHAU = os.path.abspath(argv[1]) if len(argv) > 1 else None
os.makedirs(AUS, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
R = math.radians

MATS = {}
def mat(name, farbe, leucht=0.0, metall=0.6, rauh=0.35):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    p.inputs["Base Color"].default_value = (*farbe, 1)
    p.inputs["Metallic"].default_value = metall
    p.inputs["Roughness"].default_value = rauh
    if leucht > 0:
        p.inputs["Emission Color"].default_value = (*farbe, 1)
        p.inputs["Emission Strength"].default_value = leucht
    MATS[name] = m

mat("Huelle", (0.75, 0.76, 0.8))
mat("Streifen", (1.0, 0.6, 0.2), leucht=1.0)
mat("Duese", (0.12, 0.12, 0.13), metall=0.8, rauh=0.5)
mat("Kopf", (1.0, 0.9, 0.6), leucht=3.0)


def _fertig(o, w, m, glatt=True, fase=0.0):
    o.data.materials.append(MATS[m])
    if fase > 0:
        b = o.modifiers.new("Fase", "BEVEL")
        b.width = fase
        b.segments = 2
    if glatt:
        for p in o.data.polygons:
            p.use_smooth = True
    o.parent = w
    return o


def zyl(w, name, r, tiefe, y, m="Huelle", r2=None, ecken=14):
    if r2 is None:
        bpy.ops.mesh.primitive_cylinder_add(vertices=ecken, radius=r, depth=tiefe, location=(0, y, 0), rotation=(R(-90), 0, 0))
    else:
        bpy.ops.mesh.primitive_cone_add(vertices=ecken, radius1=r, radius2=r2, depth=tiefe, location=(0, y, 0), rotation=(R(-90), 0, 0))
    o = bpy.context.active_object
    o.name = name
    return _fertig(o, w, m)


def kugel(w, name, r, y, m="Kopf", streck=(1, 1, 1)):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=14, ring_count=8, radius=r, location=(0, y, 0))
    o = bpy.context.active_object
    o.name = name
    o.scale = streck
    bpy.ops.object.transform_apply(scale=True)
    return _fertig(o, w, m)


def flossen(w, n, laenge, hoehe, y, dicke=0.02, abstand=0.06, m="Streifen", pfeil=0.5):
    for i in range(n):
        a = R(i * 360 / n + 45)
        bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 0))
        o = bpy.context.active_object
        o.name = f"Flosse{i}"
        o.scale = (hoehe, laenge, dicke)
        bpy.ops.object.transform_apply(scale=True)
        for v in o.data.vertices:          # nach hinten gepfeilt: vordere Außenkante zurückziehen
            if v.co.y > 0 and v.co.x > 0:
                v.co.y -= laenge * pfeil
        o.location = (math.cos(a) * (abstand + hoehe / 2), y, math.sin(a) * (abstand + hoehe / 2))
        o.rotation_euler = (0, -a, 0)
        _fertig(o, w, m, glatt=False)


def wurzel(name):
    o = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(o)
    return o


def zielsuch():
    w = wurzel("rakete_zielsuch")
    zyl(w, "Rumpf", 0.07, 0.62, 0.0)
    zyl(w, "Nase", 0.07, 0.22, 0.42, r2=0.035)
    kugel(w, "Sucherkopf", 0.04, 0.54)
    zyl(w, "Band1", 0.073, 0.05, 0.18, m="Streifen")
    zyl(w, "Band2", 0.073, 0.05, -0.12, m="Streifen")
    flossen(w, 4, 0.16, 0.08, -0.24)
    flossen(w, 4, 0.08, 0.04, 0.24, m="Huelle")      # kleine Steuerflächen vorn
    zyl(w, "Duese", 0.055, 0.08, -0.34, m="Duese", r2=0.065)
    return w


def streu_r():
    w = wurzel("rakete_streu_r")
    zyl(w, "Rumpf", 0.085, 0.42, 0.0)
    zyl(w, "Nase", 0.085, 0.18, 0.3, r2=0.0)
    zyl(w, "Band", 0.088, 0.08, 0.08, m="Streifen")
    flossen(w, 3, 0.18, 0.1, -0.16)
    zyl(w, "Duese", 0.06, 0.07, -0.24, m="Duese", r2=0.075)
    return w


def smart():
    w = wurzel("rakete_smart")
    zyl(w, "Rumpf", 0.1, 0.5, 0.0)
    zyl(w, "Nase", 0.1, 0.12, 0.31, r2=0.06)
    kugel(w, "Kopf", 0.06, 0.38)
    for i in range(5):           # fünf Kapseln rundum: zerplatzt in fünf Zielsucher
        a = R(i * 72)
        bpy.ops.mesh.primitive_uv_sphere_add(segments=10, ring_count=6, radius=0.045,
                                             location=(math.cos(a) * 0.1, 0.05, math.sin(a) * 0.1))
        o = bpy.context.active_object
        o.name = f"Kapsel{i}"
        o.scale = (1, 2.4, 1)
        bpy.ops.object.transform_apply(scale=True)
        _fertig(o, w, "Streifen")
    flossen(w, 4, 0.15, 0.1, -0.2)
    zyl(w, "Duese", 0.07, 0.08, -0.29, m="Duese", r2=0.085)
    return w


def mega():
    w = wurzel("rakete_mega")
    zyl(w, "Rumpf", 0.12, 0.7, 0.0)
    zyl(w, "Nase", 0.12, 0.3, 0.5, r2=0.03)
    kugel(w, "Spitze", 0.035, 0.66)
    for k, y in enumerate((0.26, 0.12, -0.02)):        # Warnringe
        zyl(w, f"Ring{k}", 0.124, 0.04, y, m="Streifen")
    flossen(w, 4, 0.26, 0.14, -0.26)
    zyl(w, "Heck", 0.12, 0.06, -0.38, m="Duese", r2=0.1)
    zyl(w, "Duese", 0.08, 0.1, -0.45, m="Duese", r2=0.1)
    return w


BAUER = {"rakete_zielsuch": zielsuch, "rakete_streu_r": streu_r, "rakete_smart": smart, "rakete_mega": mega}
wurzeln = {}
for name, f in BAUER.items():
    w = f()
    wurzeln[name] = w
    teile = [w] + list(w.children_recursive)
    bpy.ops.object.select_all(action="DESELECT")
    for o in teile:
        o.select_set(True)
    pfad = os.path.join(AUS, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=pfad, export_format="GLB", use_selection=True, export_apply=True)
    print(f"MODELL {name}: {len(teile) - 1} Teile, {os.path.getsize(pfad)} Bytes -> {pfad}")

if VORSCHAU:
    for i, (name, w) in enumerate(wurzeln.items()):
        w.location = ((i - 1.5) * 0.7, 0, 0)
        w.rotation_euler = (0, 0, R(-70))
    cam = bpy.data.objects.new("Kamera", bpy.data.cameras.new("Kamera"))
    bpy.context.collection.objects.link(cam)
    cam.location = (0, -0.6, 3.2)
    cam.rotation_euler = (R(12), 0, 0)
    cam.data.lens = 50
    bpy.context.scene.camera = cam
    sz = bpy.context.scene
    sz.render.engine = "BLENDER_WORKBENCH"
    sz.display.shading.light = "STUDIO"
    sz.display.shading.color_type = "MATERIAL"
    sz.display.shading.show_cavity = True
    sz.render.resolution_x = 1600
    sz.render.resolution_y = 700
    sz.render.filepath = VORSCHAU
    bpy.ops.render.render(write_still=True)
    print("VORSCHAU", VORSCHAU)
