"""Baut die fünf Gegnerroboter in Blender und exportiert je ein GLB.

Aufruf (ohne Fenster):
    blender -b --factory-startup --python tools/modelle_bauen.py -- assets/gegner [vorschau.png]

Vorne ist +Y (wird in Godot zu -Z). Materialnamen sind die Schnittstelle zu Godot:
Panzer, Rahmen, Leuchte, Duese, Mine — Gegner.gd ersetzt sie durch eigene Materialien
(Typfarbe, Plattentextur im Minenstil). Ein Teil namens "Rotor" dreht sich im Spiel.
"""
import bpy, bmesh, math, sys, os

argv = sys.argv[sys.argv.index("--") + 1:]
AUS = os.path.abspath(argv[0])
VORSCHAU = os.path.abspath(argv[1]) if len(argv) > 1 else None
os.makedirs(AUS, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
R = math.radians

MATS = {}
def mat(name, farbe, leucht=0.0, metall=0.7, rauh=0.4):
    if name in MATS:
        return MATS[name]
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
    return m

mat("Panzer", (0.55, 0.2, 0.15))
mat("Rahmen", (0.12, 0.12, 0.13), metall=0.8, rauh=0.5)
mat("Leuchte", (1.0, 0.2, 0.1), leucht=4.0)
mat("Duese", (1.0, 0.55, 0.2), leucht=3.0)
mat("Mine", (1.0, 0.45, 0.1), leucht=2.0)
mat("Schild", (0.3, 0.6, 1.0), leucht=1.5, metall=0.0, rauh=0.1)


def _fertig(o, wurzel, m, fase, glatt=False):
    o.data.materials.append(MATS[m])
    if fase > 0:
        b = o.modifiers.new("Fase", "BEVEL")
        b.width = fase
        b.segments = 2
        b.limit_method = "ANGLE"
        b.angle_limit = R(35)
    if glatt:
        for p in o.data.polygons:
            p.use_smooth = True
    o.parent = wurzel
    return o


def _skalieren(o, groesse):
    o.scale = groesse
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)


def box(w, name, groesse, ort, rot=(0, 0, 0), m="Panzer", fase=0.04, verjuengt=None):
    bpy.ops.mesh.primitive_cube_add(size=1, location=ort, rotation=[R(a) for a in rot])
    o = bpy.context.active_object
    o.name = name
    _skalieren(o, groesse)
    if verjuengt:  # vordere Hälfte (+Y) in x/z zusammenziehen: keilförmig
        for v in o.data.vertices:
            if v.co.y > 0:
                v.co.x *= verjuengt[0]
                v.co.z *= verjuengt[1]
    return _fertig(o, w, m, fase)


def zyl(w, name, r, tiefe, ort, rot=(0, 0, 0), m="Rahmen", ecken=16, fase=0.02, r2=None):
    if r2 is None:
        bpy.ops.mesh.primitive_cylinder_add(vertices=ecken, radius=r, depth=tiefe, location=ort,
                                            rotation=[R(a) for a in rot])
    else:
        bpy.ops.mesh.primitive_cone_add(vertices=ecken, radius1=r, radius2=r2, depth=tiefe, location=ort,
                                        rotation=[R(a) for a in rot])
    o = bpy.context.active_object
    o.name = name
    return _fertig(o, w, m, fase, glatt=True)


def kugel(w, name, r, ort, m="Leuchte", seg=16, ringe=8, streck=(1, 1, 1)):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=ringe, radius=r, location=ort)
    o = bpy.context.active_object
    o.name = name
    if streck != (1, 1, 1):
        _skalieren(o, streck)
    return _fertig(o, w, m, 0.0, glatt=True)


def ring(w, name, gross, klein, ort, rot=(0, 0, 0), m="Rahmen", seg=24):
    bpy.ops.mesh.primitive_torus_add(major_radius=gross, minor_radius=klein, major_segments=seg,
                                     minor_segments=8, location=ort, rotation=[R(a) for a in rot])
    o = bpy.context.active_object
    o.name = name
    return _fertig(o, w, m, 0.0, glatt=True)


def wurzel(name):
    o = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(o)
    return o


def spiegel(f, *args, x_index=None):
    """Baut ein Teil links und rechts (x und -x)."""
    for s in (1, -1):
        f(s)


# ---------------------------------------------------------------- Jäger
def jaeger():
    w = wurzel("jaeger")
    box(w, "Rumpf", (1.0, 1.7, 0.55), (0, 0, 0), verjuengt=(0.55, 0.7), fase=0.06)
    box(w, "Deckplatte", (0.72, 1.1, 0.08), (0, -0.05, 0.3), verjuengt=(0.6, 1.0), fase=0.03)
    box(w, "Bauchplatte", (0.8, 1.2, 0.07), (0, -0.05, -0.3), verjuengt=(0.6, 1.0), fase=0.03)
    box(w, "Augenfassung", (0.46, 0.22, 0.32), (0, 0.8, 0.03), m="Rahmen", fase=0.04)
    kugel(w, "Auge", 0.13, (0, 0.92, 0.03))
    box(w, "Finne", (0.06, 0.65, 0.38), (0, -0.48, 0.47), rot=(-18, 0, 0), m="Rahmen", fase=0.015)
    for i in range(5):
        box(w, f"Luefter{i}", (0.62, 0.045, 0.04), (0, -0.45 + i * 0.13, -0.35), m="Rahmen", fase=0)
    def seite(s):
        zyl(w, f"Gondel{s}", 0.21, 1.15, (s * 0.98, -0.1, 0), rot=(90, 0, 0), m="Panzer", fase=0.03)
        zyl(w, f"Gondelspitze{s}", 0.21, 0.32, (s * 0.98, 0.63, 0), rot=(-90, 0, 0), m="Panzer", r2=0.07)
        zyl(w, f"Duesenring{s}", 0.19, 0.14, (s * 0.98, -0.72, 0), rot=(90, 0, 0))
        zyl(w, f"Duese{s}", 0.13, 0.05, (s * 0.98, -0.8, 0), rot=(90, 0, 0), m="Duese", fase=0)
        box(w, f"Strebe{s}", (0.62, 0.38, 0.08), (s * 0.62, -0.1, 0), m="Rahmen", fase=0.02)
        zyl(w, f"Lauf{s}", 0.05, 0.62, (s * 0.27, 0.95, -0.18), rot=(90, 0, 0), ecken=10)
        zyl(w, f"Muendung{s}", 0.075, 0.08, (s * 0.27, 1.26, -0.18), rot=(90, 0, 0), m="Panzer", ecken=10)
        box(w, f"Flanke{s}", (0.06, 0.8, 0.28), (s * 0.43, -0.15, 0.0), rot=(0, 0, s * -6), fase=0.015)
    spiegel(seite)
    zyl(w, "Antenne", 0.015, 0.5, (0.3, -0.6, 0.5), ecken=6, fase=0)
    kugel(w, "Antennenlicht", 0.04, (0.3, -0.6, 0.76), seg=8, ringe=4)
    return w


# ---------------------------------------------------------------- Geschütz
def geschuetz():
    w = wurzel("geschuetz")
    kugel(w, "Huelle", 0.85, (0, 0, 0), m="Panzer", seg=24, ringe=12)
    ring(w, "Guertel", 0.87, 0.09, (0, 0, 0))
    ring(w, "Guertel2", 0.62, 0.06, (0, 0, 0.6))
    for i, a in enumerate([60, 120, 180, 240, 300]):
        x, y = math.sin(R(a)) * 0.78, math.cos(R(a)) * 0.78
        box(w, f"Platte{i}", (0.52, 0.09, 0.42), (x, y, 0.32), rot=(-28, 0, -a), fase=0.03)
        box(w, f"Platte_u{i}", (0.48, 0.09, 0.3), (x * 0.95, y * 0.95, -0.38), rot=(30, 0, -a), fase=0.03)
    box(w, "Turm", (0.62, 0.55, 0.48), (0, 0.72, -0.05), m="Rahmen", fase=0.06)
    for s in (1, -1):
        zyl(w, f"Rohr{s}", 0.07, 0.85, (s * 0.15, 1.2, -0.05), rot=(90, 0, 0), ecken=12)
        zyl(w, f"Muendung{s}", 0.095, 0.1, (s * 0.15, 1.6, -0.05), rot=(90, 0, 0), m="Panzer", ecken=12)
        zyl(w, f"Kreisel{s}", 0.26, 0.32, (s * 0.92, 0, 0), rot=(0, 90, 0))
        zyl(w, f"Kreisellicht{s}", 0.15, 0.03, (s * 1.09, 0, 0), rot=(0, 90, 0), m="Duese", fase=0)
    zyl(w, "Augenfassung", 0.22, 0.12, (0, 0.66, 0.38), rot=(90, 0, 0))
    kugel(w, "Auge", 0.16, (0, 0.72, 0.38))
    for i in range(3):
        zyl(w, f"Antenne{i}", 0.02, 0.42, (-0.15 + i * 0.15, -0.2, 0.98), ecken=6, fase=0)
    box(w, "Sensorleiste", (0.45, 0.08, 0.06), (0, -0.2, 1.2), m="Rahmen", fase=0.01)
    zyl(w, "Sporn", 0.32, 0.55, (0, 0, -0.98), rot=(180, 0, 0), r2=0.02)
    return w


# ---------------------------------------------------------------- Wächter
def waechter():
    w = wurzel("waechter")
    box(w, "Kern", (1.6, 1.5, 1.5), (0, 0, 0), fase=0.12)
    box(w, "Brustpanzer", (1.32, 0.14, 1.05), (0, 0.8, 0.05), fase=0.05)
    box(w, "Visierrahmen", (1.06, 0.1, 0.32), (0, 0.88, 0.34), m="Rahmen", fase=0.03)
    box(w, "Visier", (0.9, 0.06, 0.15), (0, 0.92, 0.34), m="Leuchte", fase=0)
    for i in range(4):
        box(w, f"Schlitz{i}", (0.22, 0.05, 0.5), (-0.45 + i * 0.3, 0.89, -0.3), m="Rahmen", fase=0.01)
    for s in (1, -1):
        box(w, f"Schulter{s}", (0.55, 1.15, 0.5), (s * 1.02, 0, 0.48), rot=(0, s * 15, 0), fase=0.08,
            verjuengt=(0.85, 0.8))
        zyl(w, f"Arm{s}", 0.21, 0.95, (s * 1.05, 0.3, -0.25), rot=(90, 0, 0))
        zyl(w, f"Kanone{s}", 0.13, 0.6, (s * 1.05, 0.95, -0.25), rot=(90, 0, 0), m="Panzer", ecken=12)
        zyl(w, f"Kanonenlicht{s}", 0.08, 0.03, (s * 1.05, 1.26, -0.25), rot=(90, 0, 0), m="Leuchte", fase=0)
        box(w, f"Seitenplatte{s}", (0.08, 1.1, 0.9), (s * 0.82, 0, -0.15), fase=0.03)
        for z in (0.35, -0.35):
            zyl(w, f"Triebwerk{s}{z}", 0.19, 0.32, (s * 0.4, -0.86, z), rot=(90, 0, 0))
            zyl(w, f"Duese{s}{z}", 0.13, 0.04, (s * 0.4, -1.03, z), rot=(90, 0, 0), m="Duese", fase=0)
        for y in (0.6, -0.6):
            zyl(w, f"Dorn{s}{y}", 0.12, 0.35, (s * 0.7, y, -0.85), rot=(180, 0, 0), r2=0.0, ecken=8)
    box(w, "Sensorblock", (0.42, 0.42, 0.16), (0, -0.2, 0.83), m="Rahmen", fase=0.03)
    for s in (1, -1):
        zyl(w, f"Antenne{s}", 0.018, 0.55, (s * 0.15, -0.3, 1.15), ecken=6, fase=0)
    return w


# ---------------------------------------------------------------- Minenleger
def minenleger():
    w = wurzel("minenleger")
    zyl(w, "Scheibe", 1.0, 0.36, (0, 0, 0), m="Panzer", ecken=24, fase=0.08)
    kugel(w, "Kuppel", 0.5, (0, 0, 0.16), m="Rahmen", seg=20, ringe=10, streck=(1, 1, 0.55))
    zyl(w, "Unterseite", 0.7, 0.2, (0, 0, -0.26), m="Rahmen", ecken=24, r2=0.45)
    for i in range(8):
        a = R(i * 45 + 22.5)
        box(w, f"Luefter{i}", (0.22, 0.08, 0.05), (math.sin(a) * 0.72, math.cos(a) * 0.72, 0.2),
            rot=(0, 0, -math.degrees(a)), m="Rahmen", fase=0)
    # Rotor: Ring mit sechs Schaufeln, ein einziges Objekt — dreht sich im Spiel
    ring(w, "Rotor", 1.18, 0.07, (0, 0, 0), m="Rahmen", seg=32)
    rotor = bpy.data.objects["Rotor"]
    teile = []
    for i in range(6):
        a = R(i * 60)
        b = box(w, f"Schaufel{i}", (0.3, 0.06, 0.16), (math.sin(a) * 1.18, math.cos(a) * 1.18, 0),
                rot=(0, 0, -i * 60), m="Panzer", fase=0.01)
        teile.append(b)
    for b in teile:
        for mod in list(b.modifiers):
            bpy.context.view_layer.objects.active = b
            bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.ops.object.select_all(action="DESELECT")
    for b in teile:
        b.select_set(True)
    rotor.select_set(True)
    bpy.context.view_layer.objects.active = rotor
    bpy.ops.object.join()
    zyl(w, "Augenfassung", 0.2, 0.14, (0, 0.92, 0.03), rot=(90, 0, 0))
    kugel(w, "Auge", 0.14, (0, 0.98, 0.03))
    box(w, "Minenschacht", (0.62, 0.42, 0.3), (0, -0.88, -0.14), m="Rahmen", fase=0.04)
    for i in range(3):
        kugel(w, f"Mine{i}", 0.12, (-0.2 + i * 0.2, -1.05, -0.18), m="Mine", seg=10, ringe=6)
    for i in range(3):
        a = R(i * 120 + 60)
        zyl(w, f"Bein{i}", 0.03, 0.6, (math.sin(a) * 0.45, math.cos(a) * 0.45, -0.55),
            rot=(math.cos(a) * 25, -math.sin(a) * 25, 0), ecken=6, fase=0)
    return w


# ---------------------------------------------------------------- Tarnroboter
def tarn():
    w = wurzel("tarn")
    zyl(w, "Rumpf", 0.55, 1.9, (0, 0.05, 0), rot=(-90, 0, 0), m="Panzer", ecken=4, r2=0.04, fase=0.02).scale = (1.35, 1.0, 0.55)
    zyl(w, "Heck", 0.42, 0.5, (0, -0.95, 0), rot=(90, 0, 0), m="Rahmen", ecken=4, r2=0.2, fase=0.02).scale = (1.35, 1.0, 0.55)
    box(w, "Auge", (0.34, 0.05, 0.06), (0, 0.42, 0.17), rot=(-15, 0, 0), m="Leuchte", fase=0)
    for s in (1, -1):
        box(w, f"Fluegel{s}", (1.3, 0.62, 0.05), (s * 0.68, -0.35, -0.02), rot=(0, s * -6, s * 22),
            verjuengt=(1.0, 1.0), fase=0.01)
        box(w, f"Spitze{s}", (0.04, 0.45, 0.32), (s * 1.28, -0.6, 0.05), rot=(0, s * 12, s * 22), m="Rahmen", fase=0.01)
        box(w, f"Leitwerk{s}", (0.04, 0.5, 0.4), (s * 0.22, -1.0, 0.25), rot=(0, s * 30, 0), m="Rahmen", fase=0.01)
        box(w, f"Kante{s}", (0.05, 1.3, 0.05), (s * 0.4, 0.0, 0.08), rot=(0, 0, s * 9), m="Rahmen", fase=0)
        zyl(w, f"Duese{s}", 0.1, 0.05, (s * 0.18, -1.22, 0), rot=(90, 0, 0), m="Duese", fase=0, ecken=10)
    return w


# ---------------------------------------------------------------- Schildträger
def schildtraeger():
    w = wurzel("schildtraeger")
    box(w, "Rumpf", (1.1, 1.2, 1.0), (0, -0.2, 0), fase=0.1)
    zyl(w, "Schild", 1.25, 0.12, (0, 0.75, 0), rot=(90, 0, 0), m="Schild", ecken=20, fase=0.03)
    ring(w, "Schildrand", 1.25, 0.07, (0, 0.75, 0), rot=(90, 0, 0), seg=32)
    for s in (1, -1):
        zyl(w, f"Emitter{s}", 0.13, 0.5, (s * 0.65, 0.35, 0), rot=(90, 0, 0))
        zyl(w, f"Kanone{s}", 0.09, 0.7, (s * 0.72, 0.2, -0.55), rot=(90, 0, 0), m="Panzer", ecken=10)
        box(w, f"Seite{s}", (0.1, 1.0, 0.8), (s * 0.6, -0.25, 0), fase=0.03)
        zyl(w, f"Duese{s}", 0.14, 0.05, (s * 0.3, -0.85, -0.2), rot=(90, 0, 0), m="Duese", fase=0)
    box(w, "Sensor", (0.3, 0.2, 0.2), (0, 0.15, 0.62), m="Rahmen", fase=0.03)
    kugel(w, "Auge", 0.1, (0, 0.27, 0.62))
    return w


# ---------------------------------------------------------------- Kamikaze
def kamikaze():
    w = wurzel("kamikaze")
    kugel(w, "Kern", 0.6, (0, 0, 0), m="Panzer", seg=16, ringe=10)
    ring(w, "Augenring", 0.62, 0.06, (0, 0.05, 0), rot=(90, 0, 0), m="Leuchte")
    for i, (x, y, z) in enumerate([(1, 0, 0), (-1, 0, 0), (0, 0, 1), (0, 0, -1), (0, 1, 0),
                                    (0.7, 0.7, 0.7), (-0.7, 0.7, 0.7), (0.7, 0.7, -0.7), (-0.7, 0.7, -0.7)]):
        l = math.sqrt(x * x + y * y + z * z)
        x, y, z = x / l, y / l, z / l
        rx = math.degrees(math.acos(max(-1, min(1, z))))
        rz = math.degrees(math.atan2(x, -y)) if (x or y) else 0
        zyl(w, f"Dorn{i}", 0.12, 0.55, (x * 0.75, y * 0.75, z * 0.75), rot=(rx, 0, rz), m="Rahmen", r2=0.0, ecken=8)
    zyl(w, "Antrieb", 0.25, 0.3, (0, -0.72, 0), rot=(90, 0, 0))
    zyl(w, "Duese", 0.18, 0.05, (0, -0.88, 0), rot=(90, 0, 0), m="Duese", fase=0)
    return w


# ---------------------------------------------------------------- Schwarmdrohne
def drohne():
    w = wurzel("drohne")
    kugel(w, "Kern", 0.25, (0, 0, 0), m="Panzer", seg=12, ringe=8)
    kugel(w, "Auge", 0.09, (0, 0.22, 0.02), seg=8, ringe=4)
    for i in range(3):
        a = R(i * 120 + 60)
        box(w, f"Fluegel{i}", (0.55, 0.16, 0.03), (math.sin(a) * 0.38, math.cos(a) * 0.38, 0),
            rot=(0, 0, -i * 120 - 60), m="Rahmen", fase=0.01)
        zyl(w, f"Duese{i}", 0.04, 0.03, (math.sin(a) * 0.62, math.cos(a) * 0.62 - 0.05, 0), rot=(90, 0, 0), m="Duese", fase=0, ecken=8)
    return w


# ---------------------------------------------------------------- Teleporter
def teleporter():
    w = wurzel("teleporter")
    kugel(w, "Kristall", 0.65, (0, 0, 0), m="Panzer", seg=4, ringe=2, streck=(1, 1, 1.5))
    ring(w, "Ring1", 0.95, 0.05, (0, 0, 0), rot=(90, 0, 0))
    ring(w, "Ring2", 0.95, 0.05, (0, 0, 0), rot=(0, 90, 0))
    kugel(w, "Auge", 0.18, (0, 0.55, 0.1), seg=10, ringe=6)
    for s in (1, -1):
        zyl(w, f"Spitze{s}", 0.12, 0.5, (0, 0, s * 1.15), rot=(0 if s > 0 else 180, 0, 0), m="Leuchte", r2=0.0, ecken=6)
    return w


# ---------------------------------------------------------------- Dieb
def dieb():
    w = wurzel("dieb")
    zyl(w, "Rumpf", 0.35, 1.5, (0, 0, 0), rot=(-90, 0, 0), m="Panzer", ecken=8, r2=0.18, fase=0.02)
    kugel(w, "Auge", 0.12, (0, 0.72, 0.1), seg=10, ringe=6)
    for s in (1, -1):
        box(w, f"Arm{s}", (0.08, 0.7, 0.08), (s * 0.4, 0.45, -0.1), rot=(0, 0, s * -20), m="Rahmen", fase=0.01)
        box(w, f"Klaue{s}a", (0.06, 0.25, 0.06), (s * 0.55, 0.85, -0.05), rot=(20, 0, s * 30), m="Rahmen", fase=0)
        box(w, f"Klaue{s}b", (0.06, 0.25, 0.06), (s * 0.55, 0.85, -0.2), rot=(-20, 0, s * 30), m="Rahmen", fase=0)
        box(w, f"Finne{s}", (0.6, 0.35, 0.04), (s * 0.4, -0.5, 0), rot=(0, s * 10, s * 15), m="Panzer", fase=0.01)
    zyl(w, "Duese", 0.15, 0.05, (0, -0.78, 0), rot=(90, 0, 0), m="Duese", fase=0)
    box(w, "Beutel", (0.4, 0.35, 0.3), (0, -0.1, -0.35), m="Mine", fase=0.05)
    return w


# ---------------------------------------------------------------- Reparierer
def reparierer():
    w = wurzel("reparierer")
    kugel(w, "Koerper", 0.6, (0, 0, 0), m="Panzer", seg=16, ringe=8, streck=(1, 1, 0.6))
    box(w, "Kreuz1", (0.6, 0.18, 0.1), (0, 0, 0.42), m="Leuchte", fase=0)
    box(w, "Kreuz2", (0.18, 0.6, 0.1), (0, 0, 0.42), m="Leuchte", fase=0)
    for i in range(4):
        a = R(i * 90 + 45)
        box(w, f"Arm{i}", (0.7, 0.1, 0.1), (math.sin(a) * 0.75, math.cos(a) * 0.75, 0), rot=(0, 0, -i * 90 - 45), m="Rahmen", fase=0.01)
        zyl(w, f"Duese{i}", 0.12, 0.2, (math.sin(a) * 1.1, math.cos(a) * 1.1, 0), m="Duese", fase=0.01)
    kugel(w, "Auge", 0.12, (0, 0.55, 0.05), seg=10, ringe=6)
    return w


# ---------------------------------------------------------------- Bosse
def boss_koloss():
    w = wurzel("boss_koloss")
    box(w, "Kern", (3.4, 3.0, 3.0), (0, 0, 0), fase=0.25)
    box(w, "Brust", (2.8, 0.25, 2.2), (0, 1.6, 0.1), fase=0.1)
    box(w, "Visierrahmen", (2.2, 0.2, 0.6), (0, 1.75, 0.75), m="Rahmen", fase=0.06)
    box(w, "Visier", (1.9, 0.1, 0.3), (0, 1.84, 0.75), m="Leuchte", fase=0)
    for i in range(6):
        box(w, f"Rippe{i}", (0.25, 0.1, 1.0), (-1.0 + i * 0.4, 1.78, -0.45), m="Rahmen", fase=0.02)
    for s in (1, -1):
        box(w, f"Schulter{s}", (1.2, 2.4, 1.1), (s * 2.2, 0, 1.0), rot=(0, s * 15, 0), fase=0.15, verjuengt=(0.85, 0.8))
        for z in (0.4, -0.5):
            zyl(w, f"Kanone{s}{z}", 0.28, 1.6, (s * 2.25, 1.3, z), rot=(90, 0, 0), m="Rahmen", ecken=14)
            zyl(w, f"Muendung{s}{z}", 0.2, 0.06, (s * 2.25, 2.12, z), rot=(90, 0, 0), m="Leuchte", fase=0)
        box(w, f"Panzerplatte{s}", (0.2, 2.2, 1.9), (s * 1.75, 0, -0.3), fase=0.05)
        for z in (0.8, 0, -0.8):
            zyl(w, f"Triebwerk{s}{z}", 0.35, 0.6, (s * 0.9, -1.8, z), rot=(90, 0, 0))
            zyl(w, f"Duese{s}{z}", 0.25, 0.05, (s * 0.9, -2.12, z), rot=(90, 0, 0), m="Duese", fase=0)
        for y in (1.1, -1.1):
            zyl(w, f"Dorn{s}{y}", 0.25, 0.8, (s * 1.4, y, -1.85), rot=(180, 0, 0), r2=0.0, ecken=8)
    box(w, "Turm", (1.0, 1.0, 0.5), (0, -0.4, 1.75), m="Rahmen", fase=0.06)
    for s in (1, -1):
        zyl(w, f"Antenne{s}", 0.04, 1.4, (s * 0.35, -0.5, 2.6), ecken=6, fase=0)
    return w


def boss_brutmutter():
    w = wurzel("boss_brutmutter")
    kugel(w, "Leib", 2.2, (0, 0, 0), m="Panzer", seg=28, ringe=14, streck=(1, 1, 0.65))
    ring(w, "Guertel", 2.25, 0.18, (0, 0, 0), seg=40)
    kugel(w, "Kuppel", 1.0, (0, 0, 1.1), m="Rahmen", seg=20, ringe=10, streck=(1, 1, 0.6))
    kugel(w, "Auge", 0.45, (0, 1.75, 0.5), seg=16, ringe=8)
    zyl(w, "Augenfassung", 0.55, 0.3, (0, 1.65, 0.5), rot=(90, 0, 0))
    for i in range(6):
        a = R(i * 60 + 30)
        x, y = math.sin(a) * 2.35, math.cos(a) * 2.35
        kugel(w, f"Brutkammer{i}", 0.55, (x, y, -0.2), m="Rahmen", seg=12, ringe=8)
        kugel(w, f"Brutlicht{i}", 0.25, (x * 1.12, y * 1.12, -0.2), m="Mine", seg=10, ringe=6)
    for i in range(4):
        a = R(i * 90)
        zyl(w, f"Bein{i}", 0.12, 1.8, (math.sin(a) * 1.3, math.cos(a) * 1.3, -1.6),
            rot=(math.cos(a) * 25, -math.sin(a) * 25, 0), ecken=8)
    return w


def boss_phantom():
    w = wurzel("boss_phantom")
    zyl(w, "Rumpf", 1.6, 4.2, (0, 0.2, 0), rot=(-90, 0, 0), m="Panzer", ecken=4, r2=0.1, fase=0.04).scale = (1.4, 1.0, 0.5)
    zyl(w, "Heck", 1.1, 1.2, (0, -2.3, 0), rot=(90, 0, 0), m="Rahmen", ecken=4, r2=0.5, fase=0.04).scale = (1.4, 1.0, 0.5)
    box(w, "Auge", (1.0, 0.1, 0.12), (0, 1.3, 0.38), rot=(-15, 0, 0), m="Leuchte", fase=0)
    ring(w, "Halo", 2.7, 0.08, (0, -0.4, 0.6), m="Leuchte", seg=48)
    for s in (1, -1):
        box(w, f"Fluegel{s}", (3.0, 1.6, 0.1), (s * 1.9, -0.9, -0.05), rot=(0, s * -8, s * 24), fase=0.02)
        box(w, f"Spitze{s}", (0.08, 1.1, 0.8), (s * 3.3, -1.5, 0.1), rot=(0, s * 15, s * 24), m="Rahmen", fase=0.01)
        box(w, f"Leitwerk{s}", (0.08, 1.2, 1.0), (s * 0.6, -2.4, 0.6), rot=(0, s * 30, 0), m="Rahmen", fase=0.01)
        for x in (0.4, 0.9):
            zyl(w, f"Duese{s}{x}", 0.2, 0.06, (s * x, -2.95, 0), rot=(90, 0, 0), m="Duese", fase=0, ecken=12)
        zyl(w, f"Lanze{s}", 0.07, 1.6, (s * 1.2, 1.2, -0.15), rot=(90, 0, 0), m="Rahmen", ecken=8)
    return w


BAUER = {"jaeger": jaeger, "geschuetz": geschuetz, "waechter": waechter, "minenleger": minenleger, "tarn": tarn,
         "schildtraeger": schildtraeger, "kamikaze": kamikaze, "drohne": drohne, "teleporter": teleporter,
         "dieb": dieb, "reparierer": reparierer,
         "boss_koloss": boss_koloss, "boss_brutmutter": boss_brutmutter, "boss_phantom": boss_phantom}
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
    dg = bpy.context.evaluated_depsgraph_get()
    dreiecke = 0
    for o in teile:
        if o.type == "MESH":
            me = o.evaluated_get(dg).to_mesh()
            dreiecke += sum(len(p.vertices) - 2 for p in me.polygons)
            o.evaluated_get(dg).to_mesh_clear()
    print(f"MODELL {name}: {len(teile) - 1} Teile, {dreiecke} Dreiecke, {os.path.getsize(pfad)} Bytes -> {pfad}")

if VORSCHAU:
    for i, (name, w) in enumerate(wurzeln.items()):
        spalte, reihe = i % 5, i // 5
        w.location = ((spalte - 2) * 5.5, 0, -reihe * 6.0)
        w.rotation_euler = (0, 0, R(-35))
    cam = bpy.data.objects.new("Kamera", bpy.data.cameras.new("Kamera"))
    bpy.context.collection.objects.link(cam)
    cam.location = (0, 34.0, 4.0)
    cam.rotation_euler = (R(80), 0, R(180))
    cam.data.lens = 34
    bpy.context.scene.camera = cam
    sz = bpy.context.scene
    sz.render.engine = "BLENDER_WORKBENCH"
    sz.display.shading.light = "STUDIO"
    sz.display.shading.color_type = "MATERIAL"
    sz.display.shading.show_cavity = True
    sz.display.shading.show_object_outline = True
    sz.render.resolution_x = 1800
    sz.render.resolution_y = 1100
    sz.render.filepath = VORSCHAU
    bpy.ops.render.render(write_still=True)
    print("VORSCHAU", VORSCHAU)
