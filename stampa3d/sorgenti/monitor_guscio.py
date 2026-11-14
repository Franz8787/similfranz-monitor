# similFranz Monitor — guscio da monitor trasportabile per iPad mini 1 (A1432)
# Parametrico: cambia le misure qui sotto e rilancia lo script in Blender.
# Unità: 1 BU = 1 mm. Stampa: Bambu Lab A1 (256x256), PLA o PETG, senza supporti.
#
# Pezzi:
#   cornice  (frontale)  -> stampata a faccia in giù
#   scocca   (posteriore)-> stampata col fondo sul piatto
#   maniglia             -> stampata distesa (asole dadi sul piatto)
# Viteria: 8 inserti filettati a caldo M3x5x5, 4 viti M3x16 testa svasata (cornice-scocca, da davanti),
#   4 viti M3x12 (maniglia, dall'interno)
#   + pulsanti (v6: solo il pistoncino di accensione; la cornice e' chiusa sui tasti volume)

import bpy, bmesh, math, os, struct
from mathutils import Matrix, Vector

# ---------------------------------------------------------------- parametri
IPAD_W, IPAD_H, IPAD_T, IPAD_R = 200.0, 134.7, 7.2, 10.0
CLR = 0.4          # gioco per lato attorno all'iPad (dimensioni del guscio)
RIB_CLR = 0.225    # gioco per lato sulle nervature (v3: 0.275 "balla un po'"; v4: -0.05/lato = scasso piu' stretto di 0.1 totali)
GAP_L = 8.0        # spazio interno a sinistra (solo pulsante accensione)
GAP_R = 36.0       # spazio interno a destra (spina Lightning a 90°: 30 mm fino alla curva + cavo)
GAP_Y = 12.0       # spazio sopra/sotto
WALL = 2.6         # spessore pareti
OUT_R = 18.0       # raggio angoli esterni
PLATE = 2.6        # spessore frontale davanti al vetro
POCKET_EXTRA = 0.8 # gioco in profondità (pad in feltro/gomma 1 mm sui pilastrini)
REAR_D = 88.4      # profondità scocca posteriore (v3: -1 mm, recupera BTN_WALL; totale invariato 100)
TOP_FLAT = 26.0    # tratto superiore piatto dietro la cornice (attacco maniglia)
DROP = 36.0        # di quanto è più bassa la faccia posteriore (profilo a trapezio)
CHAMFER = 2.5      # smusso spigoli esterni

WIN_W, WIN_H, WIN_R, WIN_CH = 160.6, 120.7, 2.5, 1.5   # finestra display
HOME_X, HOME_D = 89.9, 13.0                            # tasto Home (a destra)

INS_D, INS_DEPTH = 4.3, 6.5   # foro per inserto filettato a caldo M3x5x5 (OD 5 mm, lungo 5 mm)
INS_EXTRA = 2.0               # foro Ø3.4 oltre l'inserto: spazio per plastica fusa e punta vite
HOLE_D = 3.4               # foro passante M3
HEAD_D = 6.2               # lamatura testa M3 (DIN 912)
BOSS_R = 4.8
CASE_SCREW_L = 16.0        # viti cornice-scocca M3x16 testa svasata (DIN 7991) da davanti, inserti nella scocca
CSK_R = 3.3                # svasatura a 90° per testa piana M3 (Ø6)
HANDLE_SCREW_L = 12.0      # viti maniglia M3x12
LIP_T, LIP_H, LIP_CLR = 1.4, 3.0, 0.25

# Pulsanti meccanici (coord. vista montata, iPad in orizzontale con Home a destra)
# edge "L" = bordo sinistro (pos = y), "T" = bordo superiore (pos = x); w = larghezza pistoncino
# quote dal disegno Apple "iPad mini with Wi-Fi" (Case Design Guidelines 2013, fig. 2-13):
#   accensione: tasto 9.3-19.4 mm dall'angolo (centro 14.35), centro a 4.5 mm dal vetro, alto 2.0
#   volume +: 32.1-42.2 mm dal bordo sx (centro 37.15), volume -: 44.4-54.5 (centro 49.45), centro a 3.8 mm dal vetro
#   il fianco è piatto per ~3.5 mm dal vetro, poi si stonda verso il dorso
BUTTONS = [("accensione", "L", IPAD_H / 2 - 14.35, 8.0),
           ("volume_su", "T", -IPAD_W / 2 + 37.15, 6.0),
           ("volume_giu", "T", -IPAD_W / 2 + 49.45, 6.0)]
# v4 (terza stampa): fasce dei tasti dal disegno Apple ufficiale (Case Design Guidelines 2014, fig. 2-17
# "iPad mini with Wi-Fi" = A1432/MD528TY-A, misurato sul raster calibrato con le quote 32.1/44.4):
# le quote 2.0/3.5 e 2.4/3.5 sono dal DORSO -> dal vetro: accensione 3.7-5.2, volumi 3.7-4.8.
# Il piede v3 (centrato a 4.87) premeva i volumi sul bordo alto del tasto: ora ogni piede e' centrato sul SUO tasto.
# v5 (quarta stampa): piede dei volumi +0.5 mm di spessore verso il dorso (3.70-5.40, dentro la fascia misurata 3.84-5.89)
BTN_FOOT = {"accensione": (3.84, 5.20), "volume_su": (3.70, 5.40), "volume_giu": (3.70, 5.40)}
BTN_DEPTH = {"accensione": 5.865, "volume_su": 4.865, "volume_giu": 4.865}   # asse corpo/canale (accensione +1 mm: il corpo sbatteva sulla scocca)
TIP_EXTRA = {"accensione": 0.0, "volume_su": 1.0, "volume_giu": 1.0}  # gamba interna dei volumi +1 mm: il click era troppo al limite
FOOT_EXTRA = {"accensione": 0.5, "volume_su": 0.5, "volume_giu": 0.5}  # v5: SOLO il piede +0.5 mm (corpo e rampa restano dove in v4)
BTN_WALL = 1.0              # v3: cornice +1 mm in profondità (parete sotto il canale), recuperato dalla scocca
BTN_T = 4.0                 # spessore pistoncino
BTN_CLR = 0.32              # gioco per lato nel CANALE della cornice (v3: con 0.2 i pistoncini si incastravano)
# v5: gioco effettivo per lato dei pistoncini (il canale resta a BTN_CLR: la cornice v4 non cambia);
#     volumi 0.25 = corpo +0.14 mm totali, "troppo gioco" con 0.32
BTN_BODY_CLR = {"accensione": BTN_CLR, "volume_su": 0.25, "volume_giu": 0.25}
BTN_CAP = 1.5               # sporgenza fuori dal guscio = corsa disponibile
BTN_CAP_EXTRA = {"accensione": 0.0, "volume_su": 0.25, "volume_giu": 0.25}   # v5: testa dei volumi +0.25 mm verso fuori
BTN_FL = 2.0                # spessore flangia di ritegno
# v6 (quinta stampa): i pistoncini del volume non hanno mai funzionato in modo affidabile (5 revisioni):
#   la cornice si chiude sui due tasti volume (niente canale ne' guida), resta solo il pistoncino di accensione.
#   Il volume si regola da iOS (Centro di Controllo / AssistiveTouch). Scocca v4 e cornice v4 restano compatibili.
BTN_ACTIVE = {"accensione": True, "volume_su": False, "volume_giu": False}

# Fori cavi sui fianchi (ECG, SpO2, NIBP, placche): (y, z) uguali a dx e sx
CABLE_D = 16.0
# Tasche laterali in TPU, pezzo unico: contenitore aperto in alto + coperchio con cerniera flessibile stampata
# (stampata coricata su un'estremità, coperchio aperto). Fissaggio: 4 viti M3x8 dall'interno della scocca
# + dadi M3 nelle sedi esagonali del dorso.
POUCH_D = 56.0              # sporgenza dal fianco (v8: 50 -> 56, "allargale di qualcosa")
POUCH_GAP = 0.0
POUCH_Y0, POUCH_Y1 = -60.0, 44.0   # fondo ~24 mm sopra il tavolo: appoggia solo il monitor
POUCH_R, POUCH_WALL, POUCH_BACK, POUCH_CH = 10.0, 2.4, 3.0, 1.2
POUCH_HOLE_D = 20.0         # passaggio cavi nella parete contro il monitor
POUCH_BOSS_T = 5.0          # spessore dorso in corrispondenza delle viti
POUCH_NUT_AF, POUCH_NUT_H = 5.6, 2.7   # sede dado M3 (stretta: il TPU lo trattiene)
POUCH_CHAMF = 8.0           # smussi verticali esterni (45°, stampabili coricati)
HINGE_T, HINGE_GAP = 0.8, 1.7   # cerniera flessibile: spessore e tratto libero
HINGE_LID_Y0 = 2.5          # il coperchio parte a 2.5 mm dal dorso (lì c'è la cerniera)
ESP_X, ESP_Z = [-80.0, -30.0], -80.0                # passanti fascette sul fondo

# Sportello sulla parte inclinata: cerniera sullo spigolo posteriore (si ribalta sul retro),
# 2 cerniere a cilindro con perno in fil di ferro (graffetta ~1 mm), chiusura con 2+2 magneti 5x2 mm
DOOR_W = 180.0              # larghezza sportello (ci entra una mano)
DOOR_TOP_MARGIN = 4.0       # distanza del bordo alto dall'inizio della parte inclinata
KNUCKLE_R = 2.6             # raggio cilindro cerniera (= spessore parete: a filo delle facce)
WIRE_HOLE_D = 1.4           # foro per graffetta da ~1 mm
WIRE_GROOVE_L = 40.0        # scanalatura per infilare la graffetta (verso il centro)
WIRE_GROOVE_W = 2.2         # larghezza scanalatura (più comoda da imboccare)
DOOR_HINGE_X = [-62.0, 62.0]   # centro delle 2 nocche dello sportello
DOOR_KN_W = 10.0            # larghezza nocca sportello
MAG_D, MAG_H = 5.2, 2.1     # sedi magneti 5x2 mm (+gioco, incollati con Attak)
DOOR_GAP = 0.4

H_SPAN, H_FOOT, H_CLEAR, H_BAR, H_DEPTH = 150.0, 20.0, 28.0, 12.0, 20.0  # maniglia
H_RECESS, H_RECESS_CLR = 2.0, 0.3   # scassi nel tetto per incassare i piedini della maniglia
TILT_DEG = 5.0              # inclinazione all'indietro dello SCHERMO (cornice ruotata, fondo piatto)
RAIL_IN = 8.0               # battute laterali sportello: quanto entrano sotto lo sportello
MAG_X_IN, MAG_T_DOWN = 4.4, 5.0     # magneti nelle battute laterali: dal bordo laterale / dal bordo alto
CURTAIN_GAP, LAYER = 0.2, 0.2       # supporto integrato sotto il bordo alto dell'apertura (strato d'aria)

# v7: scritta incisa sul bordo frontale sotto il display (sostituisce la scritta "SIM_ilFranz" fatta in BambuStudio)
# v7: i 2 fermi del fianco accensione (sx, y = ±25) diventano a "L" vera: tetto PIATTO sopra il retro dell'iPad
#   che va oltre la stondatura del dorso (dal disegno Apple ~6 mm) e appoggia sulla parte piatta, con lo stesso
#   gioco delle dita della scocca (0.8 mm = feltrino/gommino adesivo da 1 mm sotto il tetto). Montante pieno fino
#   alla parete. Solo su un lato: l'iPad si infila inclinato di ~5° col fianco accensione sotto i tetti, poi si abbassa.
#   In stampa (faccia in giù) il tetto è a sbalzo: supporto da BambuStudio solo sotto i 2 tetti.
HOOK_RY = (-25.0, 25.0)     # fermi del fianco sx che diventano a L
ROOF_U = 9.0                # quanto il tetto entra sopra il retro iPad, dal fianco (stondatura ~6 -> ~3 mm sul piatto)
ROOF_GAP = 0.8              # gioco tra tetto e retro iPad (come le dita della scocca: feltrino 1 mm)
ROOF_T = 2.5                # spessore del tetto
LABEL_TEXT = "SimilFranz Monitor"
LABEL_FONT = "/System/Library/Fonts/Supplemental/Silom.ttf"
LABEL_SIZE = 15.0           # corpo del carattere (em Blender): maiuscole ~6 mm, scritta ~82 mm
LABEL_DEPTH = 1.0           # profondità incisione nella faccia frontale (PLATE = 2.6)
LABEL_Y = -71.3             # centro della fascia piana sotto la finestra display

# v8: fermi della SCOCCA sul fianco Home/Lightning (dx), opposti ai fermi a L della cornice: due dita dalla parete dx
#   che arrivano sopra il retro dell'iPad (stesso gioco 0.8 delle altre dita = feltrino 1 mm) e lo tengono contro la cornice.
#   y scelti per evitare spina Lightning (y~0), fori cavi (y=-15), viti tasca (y=26/-45) e nervature cornice (|y| 44-60).
SIDE_FINGER_Y = (36.0, -35.5)
SIDE_FINGER_W = 10.0        # larghezza del dito
SIDE_FINGER_U = 10.0        # quanto entra sopra il retro iPad dal fianco (oltre la stondatura del dorso)
# v8: tasca posteriore in TPU, aperta in alto, avvitata al retro con 6 viti M3x8 (testa dentro la scocca) + dadi M3
#   nelle sedi esagonali della tasca. Stampata in piedi (fondo sul piatto), senza supporti.
#   Fondo allineato alle tasche laterali (POUCH_Y0); le feritoie salgono di 7 mm per restare appena sopra il bordo.
RP_L, RP_D, RP_H = 230.0, 35.0, 70.0     # lunghezza, sporgenza dal retro, altezza
RP_Y0 = POUCH_Y0                          # fondo alla stessa quota delle tasche laterali
RP_WALL, RP_BACK, RP_FLOOR = 2.8, 3.0, 2.8
RP_CHAMF = 8.0              # smussi verticali esterni a 45° (come le tasche laterali)
RP_CH = 1.2                 # smusso bordo alto e bordo basso
RP_SCREWS_P = [(X, Z) for X in (-95.0, 0.0, 95.0) for Z in (14.0, RP_H - 14.0)]   # (X lungo la tasca, Z altezza)
RP_CABLE_P = [(-48.0, RP_H / 2), (48.0, RP_H / 2)]                                # 2 passaggi cavi scocca <-> tasca
RP_HOLE_D = 20.0
VENT_Y = 22.0               # centro feritoie posteriori (v7: 15): bordo basso a 2 mm dal bordo alto della tasca

VERSION = "v8"   # v8: fermi scocca lato dx + tasca posteriore TPU + tasche laterali piu' larghe (cornice v7 invariata)
HERE = os.path.dirname(os.path.abspath(__file__)) if "__file__" in globals() else os.getcwd()
OUT_DIR = os.path.join(os.path.dirname(HERE), "stl")

# ---------------------------------------------------------------- derivate
PW, PH = IPAD_W + 2 * CLR, IPAD_H + 2 * CLR
IW, IH = PW + GAP_L + GAP_R, PH + 2 * GAP_Y
XI = (GAP_L - GAP_R) / 2                   # centro iPad rispetto al centro del guscio
OW, OH = IW + 2 * WALL, IH + 2 * WALL
IR = OUT_R - WALL
F_PAD = PLATE + IPAD_T + POCKET_EXTRA      # piano d'appoggio del retro iPad (dita scocca + feltro)
F = F_PAD + BTN_WALL                       # profondità cornice = piano di battuta (v3: +1 mm per il canale pulsanti)
ZB = -(F + REAR_D)                         # retro
OHB = OH - DROP                            # altezza faccia posteriore
YBT = -OH / 2 + OHB                        # bordo superiore della faccia posteriore
# cornice/iPad/pulsanti sono modellati nel "sistema schermo"; TS li porta nel sistema scocca (fondo piatto):
# rotazione di TILT_DEG attorno al centro del piano di battuta, abbassata finché il bordo basso tocca il fondo
TILT = math.radians(TILT_DEG)
TS = (Matrix.Translation((0, -OH / 2 * (1 - math.cos(TILT)), -F)) @ Matrix.Rotation(-TILT, 4, "X")
      @ Matrix.Translation((0, 0, F)))
_top = TS @ Vector((0, OH / 2, -F))
Y_TOP, Z_TOPF = _top.y, _top.z                 # spigolo alto del piano di battuta = inizio del tetto piatto
Z_TF = Z_TOPF - TOP_FLAT                       # fine del tetto piatto / inizio falda
H_Z_BACK = Z_TOPF - TOP_FLAT / 2 - H_DEPTH / 2 - 1.5   # faccia posteriore maniglia
POUCH_Z0, POUCH_Z1 = ZB + 3.0, -F - 2.0
POUCH_ZC = (POUCH_Z0 + POUCH_Z1) / 2       # tasca simmetrica: lo stesso pezzo va a dx e a sx
POUCH_H = POUCH_Y1 - POUCH_Y0
# riferimento della parte inclinata (piano z-y): u = in salita lungo la falda, n = normale esterna
_P0 = Vector((Z_TF, Y_TOP))                     # (z, y) inizio falda
_P1 = Vector((ZB + CHAMFER, YBT))               # (z, y) fine falda
SL_U = (_P0 - _P1).normalized()
SL_N = Vector((-SL_U.y, SL_U.x))
# asse cerniera: spigolo interno tra falda e retro (2.6 mm dentro entrambe le facce)
_az = ZB + WALL
HINGE_A = Vector((_az, _P1.y + (-WALL - SL_N.x * (_az - _P1.x)) / SL_N.y))
DOOR_T_TOP = (_P0 - HINGE_A).dot(SL_U) - DOOR_TOP_MARGIN
DOOR_T_BOT = KNUCKLE_R + 0.6


def _edge_z():
    """bordo alto dell'apertura sportello: piano z = cost. (orizzontale in stampa, allineato agli strati)."""
    t = DOOR_T_TOP + DOOR_GAP
    z = HINGE_A.x + SL_U.x * t - SL_N.x * (-WALL)
    return ZB + round((z - ZB) / LAYER) * LAYER
Z_EDGE = _edge_z()


def web_pts(x, y, r):
    """colonna vite unita all'angolo interno: cerchio + raccordo pieno verso le due pareti."""
    sx, sy = math.copysign(1, x), math.copysign(1, y)
    X, Y = sx * (OW / 2 - 1.0), sy * (OH / 2 - 1.0)
    return [(x + px, y + py) for px, py in circle(r, 32)] + [(x - sx * r, Y), (X, Y), (X, y - sy * r)]


def slope_frame():
    """coord. locali (x, t, k): t lungo la falda dall'asse cerniera, k verso l'INTERNO (k=0 faccia interna parete)."""
    A, u, n = HINGE_A, SL_U, SL_N
    return Matrix(((1, 0, 0, 0), (0, u.y, -n.y, A.y), (0, u.x, -n.x, A.x), (0, 0, 0, 1)))
# posizioni in coord. tasca (X = profondità, Z = altezza); lontane dal "tetto" interno all'estremità +X
POUCH_SCREWS_P = [(X, Z) for X in (-32.0, 10.0) for Z in (15.0, POUCH_H - 18.0)]
POUCH_CABLE_P = [(-20.0, -15.0 - POUCH_Y0), (0.0, -15.0 - POUCH_Y0)]


def pouch_to_shell(sx, X, Z):
    """(X, Z) tasca -> (y, z) scocca. Tasca dx: z = ZC + X; tasca sx (stesso pezzo ruotato): z = ZC - X."""
    return POUCH_Y0 + Z, POUCH_ZC + sx * X

# viti cornice-scocca (evitano spina Lightning a dx-centro e tasti volume)
SCREWS = [(sx * (IW / 2 - 13.9), sy * (IH / 2 - 6.95), (0, 0)) for sx in (1, -1) for sy in (1, -1)]   # 4 viti agli angoli
HANDLE_SCREWS_X = [-69.0, -61.0, 61.0, 69.0]

COLL = "similFranz_Guscio"
REF = "similFranz_Riferimento"


# ---------------------------------------------------------------- utilità
def rr_loop(w, h, r, seg=12, dx=0.0, dy=0.0):
    if dx or dy:
        return [(x + dx, y + dy) for x, y in rr_loop(w, h, r, seg)]
    r = max(min(r, w / 2 - 0.01, h / 2 - 0.01), 0.01)
    cx, cy = w / 2 - r, h / 2 - r
    pts = []
    for sx, sy, a0 in ((1, 1, 0), (-1, 1, 90), (-1, -1, 180), (1, -1, 270)):
        for i in range(seg + 1):
            a = math.radians(a0 + 90 * i / seg)
            pts.append((sx * cx + r * math.cos(a), sy * cy + r * math.sin(a)))
    return pts


def circle(r, seg=40):
    return [(r * math.cos(2 * math.pi * i / seg), r * math.sin(2 * math.pi * i / seg)) for i in range(seg)]


def hexagon(af, vertex_on_x):
    rc = af / math.sqrt(3)
    off = 0 if vertex_on_x else 30
    return [(rc * math.cos(math.radians(off + 60 * i)), rc * math.sin(math.radians(off + 60 * i))) for i in range(6)]


def rect(x0, x1, y0, y1):
    return [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]


def new_obj(name, bm, coll):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    coll.objects.link(ob)
    return ob


def loop3(pts, z, M=None):
    v = [Vector((x, y, z)) for x, y in pts]
    return [M @ p for p in v] if M is not None else v


def hull(name, loops, coll, M=None, pts3=()):
    """loops: [(pts2d, z), ...] (+ punti 3D liberi) -> solido convesso."""
    bm = bmesh.new()
    for pts, z in loops:
        for x, y in pts:
            bm.verts.new((x, y, z))
    for p in pts3:
        bm.verts.new(p)
    res = bmesh.ops.convex_hull(bm, input=bm.verts[:])
    junk = list({g for g in res["geom_interior"] + res["geom_unused"] if isinstance(g, bmesh.types.BMVert)})
    if junk:
        bmesh.ops.delete(bm, geom=junk, context="VERTS")
    bmesh.ops.dissolve_limit(bm, angle_limit=0.0005, verts=bm.verts[:], edges=bm.edges[:])
    if M is not None:
        bmesh.ops.transform(bm, matrix=M, verts=bm.verts[:])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return new_obj(name, bm, coll)


def prism(name, pts, z0, z1, coll, M=None):
    return hull(name, [(pts, z0), (pts, z1)], coll, M)


def poly_prism(name, pts, z0, z1, coll):
    """prisma da poligono anche non convesso (pts in senso antiorario)."""
    bm = bmesh.new()
    b = [bm.verts.new((x, y, z0)) for x, y in pts]
    t = [bm.verts.new((x, y, z1)) for x, y in pts]
    bm.faces.new(list(reversed(b)))
    bm.faces.new(t)
    n = len(pts)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((b[i], b[j], t[j], t[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return new_obj(name, bm, coll)


def cyl(name, p0, p1, r, coll, seg=40):
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    M = Matrix.Translation(p0) @ Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix().to_4x4()
    return hull(name, [(circle(r, seg), 0.0), (circle(r, seg), d.length)], coll, M)


def box(name, x0, x1, y0, y1, z0, z1, coll):
    return prism(name, rect(x0, x1, y0, y1), z0, z1, coll)


def bake(ob):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg)
    me = bpy.data.meshes.new_from_object(ev)
    old = ob.data
    ob.modifiers.clear()
    ob.data = me
    bpy.data.meshes.remove(old)


def boolean(target, tools, op):
    if not isinstance(tools, (list, tuple)):
        tools = [tools]
    for tool in tools:
        m = target.modifiers.new("bool", "BOOLEAN")
        m.operation = op
        m.object = tool
        try:
            m.solver = "MANIFOLD"
        except TypeError:
            m.solver = "EXACT"
        bake(target)
        me = tool.data
        bpy.data.objects.remove(tool)
        bpy.data.meshes.remove(me)


def material(name, rgb, rough=0.5):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (*rgb, 1)
        bsdf.inputs["Roughness"].default_value = rough
    mat.diffuse_color = (*rgb, 1)
    return mat


def check(ob):
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bad = sum(1 for e in bm.edges if not e.is_manifold)
    vol = bm.calc_volume()
    bm.free()
    return bad, vol


def write_stl(obs, path, M):
    tris = []
    for ob in obs:
        me = ob.data
        me.calc_loop_triangles()
        tris += [[M @ me.vertices[i].co for i in t.vertices] for t in me.loop_triangles]
    with open(path, "wb") as f:
        f.write(b"similFranz guscio".ljust(80, b" "))
        f.write(struct.pack("<I", len(tris)))
        for v in tris:
            n = (v[1] - v[0]).cross(v[2] - v[0])
            if n.length > 0:
                n.normalize()
            f.write(struct.pack("<12fH", n.x, n.y, n.z, *v[0], *v[1], *v[2], 0))


# ---------------------------------------------------------------- pezzi
def edge_frame(edge):
    """matrice da coord. bordo (u = verso l'esterno, v = lungo il bordo, z) a coord. guscio,
    + (Ui parete interna, Up bordo iPad con gioco, lunghezza guida)."""
    if edge == "L":
        M = Matrix(((-1, 0, 0, XI), (0, -1, 0, 0), (0, 0, 1, 0), (0, 0, 0, 1)))  # u=-x, v=-y
        return M, PW / 2 + GAP_L, PW / 2, GAP_L / 2
    M = Matrix(((0, 1, 0, XI), (1, 0, 0, 0), (0, 0, -1, 0), (0, 0, 0, 1)))       # u=y, v=x (z specchiato)
    return M, IH / 2, PH / 2, GAP_Y / 2 - 0.5


def btn_v(edge, pos):
    return -pos if edge == "L" else pos


def btn_z(edge, name):
    z = -PLATE - BTN_DEPTH[name]
    return z if edge == "L" else -z


def btn_section(w, t):
    """sezione squadrata del pistoncino (angoli raccordati 1 mm), nel piano (v, z). v3: via l'ovale, si incastrava."""
    return rr_loop(w, t, 1.0, 6)


def btn_foot_band(edge, name):
    """fascia del piede in coordinate locali b (profondita' dal vetro -> offset dall'asse del corpo)."""
    d0, d1 = BTN_FOOT[name]
    if edge == "L":
        return BTN_DEPTH[name] - d1, BTN_DEPTH[name] - d0
    return d0 - BTN_DEPTH[name], d1 - BTN_DEPTH[name]


def btn_axis(v, zl):
    """(a, b, c) -> coord. bordo (u = c, v = v + a, z = zl + b): per estrudere sezioni lungo u."""
    return Matrix(((0, 0, 1, 0), (1, 0, 0, v), (0, 1, 0, zl), (0, 0, 0, 1)))


def active_buttons():
    """pulsanti con pistoncino (v6: solo accensione); gli altri hanno la cornice chiusa."""
    return [b for b in BUTTONS if BTN_ACTIVE[b[0]]]


def build_label(c):
    """scritta come solido (da sottrarre): da -LABEL_DEPTH a +1 mm sulla faccia frontale, centrata sotto il display."""
    cu = bpy.data.curves.new("label_cu", "FONT")
    cu.body = LABEL_TEXT
    cu.font = bpy.data.fonts.load(LABEL_FONT, check_existing=True)
    cu.size = LABEL_SIZE
    cu.align_x, cu.align_y = "CENTER", "CENTER"
    cu.extrude = (LABEL_DEPTH + 1.0) / 2
    cu.fill_mode = "BOTH"
    cu.resolution_u = 4
    tmp = bpy.data.objects.new("label_tmp", cu)
    c.objects.link(tmp)
    tmp.location = (XI, LABEL_Y, (1.0 - LABEL_DEPTH) / 2)
    bpy.context.view_layer.update()
    me = bpy.data.meshes.new_from_object(tmp.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    me.transform(tmp.matrix_world)
    bpy.data.objects.remove(tmp)
    bpy.data.curves.remove(cu)
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bpy.data.meshes.remove(me)
    return new_obj("t", bm, c)


def build_cornice(c):
    body = hull("cornice", [(rr_loop(OW - 2 * CHAMFER, OH - 2 * CHAMFER, OUT_R - CHAMFER), 0.0),
                            (rr_loop(OW, OH, OUT_R), -CHAMFER),
                            (rr_loop(OW, OH, OUT_R), -F)], c)
    boolean(body, prism("t", rr_loop(IW, IH, IR), -F - 1, -PLATE, c), "DIFFERENCE")

    # labbro di centraggio che entra nella scocca
    lo, li = LIP_CLR, LIP_CLR + LIP_T
    # v2: il labbro era staccato 0.25 mm dalla parete (galleggiava in stampa): ora la parete è ispessita
    # verso l'interno per tutta l'altezza e il labbro ne è la continuazione
    lip = prism("lip", rr_loop(IW - 2 * lo, IH - 2 * lo, IR - lo), -F - LIP_H, -F + 0.02, c)
    lcuts = [prism("t", rr_loop(IW - 2 * li, IH - 2 * li, IR - li), -F - LIP_H - 1, -F + 1, c)]
    for x, y, _ in SCREWS:                               # tacche per le colonne (unite alle pareti) della scocca
        lcuts.append(prism("t", web_pts(x, y, BOSS_R + 0.5), -F - LIP_H - 1, -F, c))
    boolean(lip, lcuts, "DIFFERENCE")
    ring = prism("t", rr_loop(IW + 0.4, IH + 0.4, IR + 0.2), -F, -PLATE + 0.05, c)
    boolean(ring, prism("t", rr_loop(IW - 2 * li, IH - 2 * li, IR - li), -F - 1, 1, c), "DIFFERENCE")
    adds = [lip, ring]
    # torrette viti
    for x, y, _ in SCREWS:
        adds.append(cyl("t", (x, y, -F), (x, y, -PLATE + 0.05), BOSS_R, c))
    # nervature di centraggio iPad (evitano tasti volume/accensione e Lightning)
    rib_t, rib_l, rz0, rz1 = 2.0, 16.0, -F + 0.6, -PLATE + 0.05
    RW, RH = IPAD_W / 2 + RIB_CLR, IPAD_H / 2 + RIB_CLR
    for rx in (-15.0, 15.0):
        adds.append(box("t", XI + rx - rib_l / 2, XI + rx + rib_l / 2, RH, PH / 2 + rib_t, rz0, rz1, c))
    for rx in (-70.0, -15.0, 15.0, 70.0):
        adds.append(box("t", XI + rx - rib_l / 2, XI + rx + rib_l / 2, -PH / 2 - rib_t, -RH, rz0, rz1, c))
    for ry in (-25.0, 25.0):
        adds.append(box("t", XI - PW / 2 - rib_t, XI - RW, ry - rib_l / 2, ry + rib_l / 2, rz0, rz1, c))
        if ry in HOOK_RY:                                # v7: fermo a L con tetto piatto
            xs = XI - IPAD_W / 2                         # fianco iPad
            xw = -IW / 2 + LIP_CLR                       # filo interno del labbro (oltre -F non tocca la scocca)
            d0, d1 = IPAD_T + ROOF_GAP, IPAD_T + ROOF_GAP + ROOF_T
            adds.append(box("t", xw, XI - RW, ry - rib_l / 2, ry + rib_l / 2, -PLATE - d1, rz1, c))      # montante pieno
            adds.append(box("t", xw, xs + ROOF_U, ry - rib_l / 2, ry + rib_l / 2, -PLATE - d1, -PLATE - d0, c))  # tetto
    for ry in (-52.0, 52.0):
        adds.append(box("t", XI + RW, XI + PW / 2 + rib_t, ry - rib_l / 2, ry + rib_l / 2, rz0, rz1, c))
    for name, edge, pos, w in active_buttons():             # guide pulsanti (v6: solo accensione)
        M, Ui, Up, GL = edge_frame(edge)
        v, zl = btn_v(edge, pos), btn_z(edge, name)
        g0, g1 = sorted(((-PLATE + 0.05), (-F + 0.6)))
        if edge == "T":
            g0, g1 = -g1, -g0
        adds.append(prism("t", rect(Ui - GL, Ui + 0.05, v - w / 2 - 2.2, v + w / 2 + 2.2), g0, g1, c, M))
    boolean(body, adds, "UNION")

    cuts = []
    for name, edge, pos, w in active_buttons():             # canali pulsanti (v6: solo accensione)
        M, Ui, Up, GL = edge_frame(edge)
        v, zl = btn_v(edge, pos), btn_z(edge, name)
        cuts.append(hull("t", [(btn_section(w + 2 * BTN_CLR, BTN_T + 2 * BTN_CLR), Ui - GL - 1),
                               (btn_section(w + 2 * BTN_CLR, BTN_T + 2 * BTN_CLR), Ui + WALL + 1)], c,
                         M @ btn_axis(v, zl)))
    # finestra display con smusso 45°
    cuts.append(hull("t", [(rr_loop(WIN_W, WIN_H, WIN_R), -PLATE - 1),
                           (rr_loop(WIN_W, WIN_H, WIN_R), -WIN_CH),
                           (rr_loop(WIN_W + 2 * (WIN_CH + 1), WIN_H + 2 * (WIN_CH + 1), WIN_R + WIN_CH + 1), 1.0)], c,
                     Matrix.Translation((XI, 0, 0))))
    cuts.append(build_label(c))                          # v7: scritta "SimilFranz Monitor" incisa
    # tasto Home raggiungibile
    hr = HOME_D / 2
    cuts.append(hull("t", [(circle(hr, 48), -PLATE - 1), (circle(hr, 48), -0.8),
                           (circle(hr + 1.8, 48), 1.0)], c, Matrix.Translation((XI + HOME_X, 0, 0))))
    # fori passanti con svasatura a 90°: viti M3 a testa piana avvitate da davanti
    for x, y, _ in SCREWS:
        cuts.append(cyl("t", (x, y, -F - 1), (x, y, 1.0), HOLE_D / 2, c, 24))
        cuts.append(hull("t", [(circle(HOLE_D / 2, 32), -(CSK_R - HOLE_D / 2) - 0.01), (circle(CSK_R, 32), 0.01),
                               (circle(CSK_R + 1.0, 32), 1.01)], c, Matrix.Translation((x, y, 0))))
    # griglia altoparlanti (lato dx, davanti agli speaker dell'iPad)
    for sgn in (1, -1):
        for k in range(7):
            yc = sgn * (14.0 + 4.0 * k)
            cuts.append(box("t", IW / 2 - 2.5, OW / 2 + 1, yc - 1.0, yc + 1.0, -F + 1.6, -PLATE - 0.8, c))
    boolean(body, cuts, "DIFFERENCE")
    return body


def teardrop(r):
    """profilo a goccia (u, v): punta verso -v, stampabile senza supporti."""
    return circle(r, 40) + [(0.0, -r * math.sqrt(2))]


def build_scocca(c):
    yb = -OH / 2 + OHB / 2
    HT = Y_TOP + OH / 2                                  # altezza al tetto piatto
    outer_p = (loop3(rr_loop(OW - 2 * CHAMFER, OHB - 2 * CHAMFER, OUT_R - CHAMFER, dy=yb), ZB)
               + loop3(rr_loop(OW, OHB, OUT_R, dy=yb), ZB + CHAMFER)
               + loop3(rr_loop(OW, HT, OUT_R, dy=-OH / 2 + HT / 2), Z_TF)
               + loop3(rr_loop(OW, OH, OUT_R), -F, TS))  # piano di battuta inclinato
    outer = lambda: hull("t", [], c, pts3=outer_p)
    body = hull("scocca", [], c, pts3=outer_p)

    floor = ZB + WALL                                    # retro chiuso (stampato sul piatto)
    IHB = OHB - 2 * WALL - 0.8
    HTI = Y_TOP - WALL + IH / 2
    boolean(body, [hull("t", [], c, pts3=loop3(rr_loop(IW, IHB, IR, dy=-IH / 2 + IHB / 2), floor)
                        + loop3(rr_loop(IW, HTI, IR, dy=-IH / 2 + HTI / 2), Z_TF - 0.4)
                        + loop3(rr_loop(IW, IH, IR), -F + 1, TS)),
                   prism("t", rr_loop(IW, IH, IR), -F - LIP_H - 1, -F + 1, c, TS)], "DIFFERENCE")  # sede labbro

    adds = []
    for x, y, _ in SCREWS:                               # colonne viti
        adds.append(prism("t", web_pts(x, y, BOSS_R), -F - 120, -F, c, TS))   # unite all'angolo (niente fessura)
    # "dita" che tengono l'iPad (dalle pareti alta e bassa, evitano il labbro della cornice)
    yi, yw2, yw = PH / 2 - 8.0, IH / 2 - 2.0, IH / 2 + 0.5
    for fx, sy in ((-20.0, 1), (20.0, 1), (XI - 70.0, -1), (XI + 70.0, -1)):
        if True:
            kc = 1.0 if sy > 0 else 1.8                  # in basso smusso più ripido: con lo schermo inclinato resta <= 45° in stampa
            prof1 = [(yi, -F_PAD), (yw2, -F_PAD), (yw2, -F - 14 - (yw2 - yi) * kc), (yi, -F - 14)]   # v3: la faccia col feltro resta a 0.8 dal retro iPad
            prof2 = [(yw2 - 0.5, -F - 3.5), (yw, -F - 3.5), (yw, -F - 14 - (yw - yi) * kc), (yw2 - 0.5, -F - 14 - (yw2 - 0.5 - yi) * kc)]
            for prof in (prof1, prof2):
                pts = [TS @ Vector((fx + dx, sy * py, pz)) for py, pz in prof for dx in (-6.0, 6.0)]
                if sy > 0 and prof is prof2:             # in alto: prolungati in verticale fino al tetto (dietro il labbro)
                    pts += [Vector((p.x, Y_TOP + 1.0, p.z)) for p, (py, pz) in zip(pts, [q for q in prof for _ in (0, 1)])
                            if pz <= -F - 5.0]
                bm = bmesh.new()
                for v in pts:
                    bm.verts.new(v)
                bmesh.ops.convex_hull(bm, input=bm.verts[:])
                bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
                adds.append(new_obj("t", bm, c))
    # v8: dita dalla parete dx (lato Home/Lightning), opposte ai fermi a L della cornice
    xi, xw2, xw = XI + PW / 2 - SIDE_FINGER_U, IW / 2 - 2.0, IW / 2 + 0.5
    for fy in SIDE_FINGER_Y:
        prof1 = [(xi, -F_PAD), (xw2, -F_PAD), (xw2, -F - 14 - (xw2 - xi)), (xi, -F - 14)]
        prof2 = [(xw2 - 0.5, -F - 3.5), (xw, -F - 3.5), (xw, -F - 14 - (xw - xi)), (xw2 - 0.5, -F - 14 - (xw2 - 0.5 - xi))]
        for prof in (prof1, prof2):
            bm = bmesh.new()
            for px, pz in prof:
                for dy in (-SIDE_FINGER_W / 2, SIDE_FINGER_W / 2):
                    bm.verts.new(TS @ Vector((px, fy + dy, pz)))
            bmesh.ops.convex_hull(bm, input=bm.verts[:])
            bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
            adds.append(new_obj("t", bm, c))
    for sx in (1, -1):                                   # rinforzi attacco maniglia (smusso 45° verso il fronte)
        x0, x1 = sorted((sx * (H_SPAN / 2 - H_FOOT - 2.0), sx * (H_SPAN / 2 + 2.0)))
        Yi = Y_TOP - WALL
        prof = [(Yi + 0.5, Z_TOPF - 3.5), (Yi - 3.5, Z_TOPF - 7.5), (Yi - 3.5, H_Z_BACK + 2.5), (Yi + 0.5, H_Z_BACK - 1.5)]
        bm = bmesh.new()
        for x in (x0, x1):
            for y, z in prof:
                bm.verts.new((x, y, z))
        bmesh.ops.convex_hull(bm, input=bm.verts[:])
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        adds.append(new_obj("t", bm, c))
    for x in ESP_X:                                      # passanti fascette ESP32 (sul fondo)
        adds.append(hull("t", [(rect(x - 4, x + 4, -IH / 2 - 0.5, -IH / 2 + 0.5), ESP_Z - 10),
                               (rect(x - 4, x + 4, -IH / 2 - 0.5, -IH / 2 + 4.5), ESP_Z - 5),
                               (rect(x - 4, x + 4, -IH / 2 - 0.5, -IH / 2 + 4.5), ESP_Z + 5)], c))
    boolean(body, adds, "UNION")
    boolean(body, outer(), "INTERSECT")      # rifila tutto ciò che sporge


    # ---- sportello sulla falda: apertura, spigolo arrotondato, cilindro cerniera, battute, rinforzi
    Ms = slope_frame()
    A = HINGE_A
    xo = DOOR_W / 2 + DOOR_GAP
    # taglio passante: la parete inclinata verso il retro è più spessa di WALL, quindi si taglia fino a 4 mm dentro
    open_cut = prism("t", rect(-xo, xo, 0.0, DOOR_T_TOP + 12.0), -WALL - 1.0, 4.0, c, Ms)
    boolean(open_cut, box("t", -xo - 1, xo + 1, -OH, OH, ZB - 50, Z_EDGE, c), "INTERSECT")   # bordo alto: piano orizzontale in stampa
    arc = []
    a0 = math.atan2(SL_N.y, SL_N.x); a1 = math.atan2(0.0, -1.0)
    for i in range(13):                                  # settore tra normale falda e normale retro
        a = a0 + (a1 - a0) * i / 12
        arc.append((A.x + 4.6 * math.cos(a), A.y + 4.6 * math.sin(a)))
    sector = [Vector((z, y)) for z, y in [(A.x, A.y)] + arc]
    bm = bmesh.new()
    for x in (-xo, xo):
        for v in sector:
            bm.verts.new((x, v.y, v.x))
    bmesh.ops.convex_hull(bm, input=bm.verts[:]); bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    boolean(body, [open_cut, new_obj("t", bm, c)], "DIFFERENCE")
    adds = [cyl("t", (-xo, A.y, A.x), (xo, A.y, A.x), KNUCKLE_R, c, 40)]          # cilindro cerniera
    for sx in (1, -1):                                   # rinforzo interno dello spigolo fuori dall'apertura
        x0, x1 = sorted((sx * (xo - 0.5), sx * (OW / 2)))
        prof = [(A.x + 1.6 * math.cos(2 * math.pi * i / 16), A.y + 1.6 * math.sin(2 * math.pi * i / 16)) for i in range(16)]
        prof += [(A.x + 8 * SL_U.x, A.y + 8 * SL_U.y), (A.x, A.y - 8.0)]
        bm = bmesh.new()
        for x in (x0, x1):
            for z, y in prof:
                bm.verts.new((x, y, z))
        bmesh.ops.convex_hull(bm, input=bm.verts[:]); bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        adds.append(new_obj("t", bm, c))
    tt = DOOR_T_TOP
    k0, k1 = 0.1, 3.0                                    # battute sotto i bordi laterali dello sportello
    def ledge(x0, x1, ta, tb, ka=k0):                    # battuta a cuneo: bordo basso a 45° in stampa
        bm = bmesh.new()
        for x in (x0, x1):
            for t, k in ((ta, ka), (ta + 6.0, k1), (tb, k1), (tb, ka)):
                bm.verts.new(Ms @ Vector((x, t, k)))
        bmesh.ops.convex_hull(bm, input=bm.verts[:]); bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        return new_obj("t", bm, c)
    # v2: niente battuta alta né appoggi magneti sospesi (in stampa partivano nel vuoto); le battute laterali
    # ora entrano 1 mm nella parete (prima restavano staccate di 0.1 mm) e portano i magneti
    for sx in (1, -1):
        x0, x1 = sorted((sx * (xo - RAIL_IN), sx * (xo + 3.0)))
        adds.append(ledge(x0, x1, KNUCKLE_R + 1.0, tt + 3.0))
        x0, x1 = sorted((sx * xo, sx * (xo + 3.0)))
        adds.append(ledge(x0, x1, KNUCKLE_R + 1.0, tt + 3.0, -1.0))
    boolean(body, adds, "UNION")
    boolean(body, outer(), "INTERSECT")

    cuts = []
    for x, y, _ in SCREWS:
        cuts.append(cyl("t", TS @ Vector((x, y, -F - INS_DEPTH)), TS @ Vector((x, y, -F + 1)), INS_D / 2, c, 32))   # inserto
        cuts.append(cyl("t", TS @ Vector((x, y, -F - INS_DEPTH - INS_EXTRA)), TS @ Vector((x, y, -F - INS_DEPTH + 0.1)),
                        HOLE_D / 2, c, 24))
    for x in ESP_X:
        cuts.append(box("t", x - 2.5, x + 2.5, -IH / 2 - 1, -IH / 2 + 2.5, ESP_Z - 6, ESP_Z + 6, c))
    for k in range(16):                                  # feritoie posteriori
        cuts.append(prism("t", rr_loop(3.0, 20.0, 1.4, 6), ZB - 1, floor + 0.01, c,
                          Matrix.Translation((-60.0 + 8.0 * k, VENT_Y, 0))))
    # v8: tasca posteriore: 6 fori vite M3 + 2 passaggi cavi a goccia (punta in alto) nel retro
    for X, Z in RP_SCREWS_P:
        cuts.append(cyl("t", (X, RP_Y0 + Z, ZB - 1), (X, RP_Y0 + Z, floor + 1), HOLE_D / 2, c, 24))
    for X, Z in RP_CABLE_P:
        cuts.append(prism("t", [(u, -v) for u, v in reversed(teardrop(RP_HOLE_D / 2))], ZB - 1, floor + 1, c,
                          Matrix.Translation((X, RP_Y0 + Z, 0))))
    # uscita cavo Lightning: tacca nel fondo, vicino al retro
    cuts.append(box("t", IW / 2 - 10.0, IW / 2 - 6.0, -OH / 2 - 2, -IH / 2 + 1, ZB - 1, ZB + 8, c))
    # fori laterali per cavi ECG / SpO2 / NIBP / placche (a goccia)
    Mside = Matrix(((0, 0, 1, 0), (1, 0, 0, 0), (0, -1, 0, 0), (0, 0, 0, 1)))   # (u,v,w) -> (x=w, y=u, z=-v): punta verso il fronte (= in alto in stampa)
    for sx in (1, -1):
        for y, z in [pouch_to_shell(sx, X, Z) for X, Z in POUCH_CABLE_P]:
            x0, x1 = sorted((sx * (OW / 2 + 1), sx * (IW / 2 - 1)))
            cuts.append(prism("t", teardrop(CABLE_D / 2), x0, x1, c,
                              Matrix.Translation((0, y, z)) @ Mside))
    # fori viti tasche nei fianchi (testa vite all'interno della scocca)
    for sx in (1, -1):
        for y, z in [pouch_to_shell(sx, X, Z) for X, Z in POUCH_SCREWS_P]:
            cuts.append(cyl("t", (sx * (IW / 2 - 1), y, z), (sx * (OW / 2 + 1), y, z), HOLE_D / 2, c, 24))
    # sportello: sedi nocche, fori graffetta (dal fianco), sedi magneti, incavo per il dito
    for xc in DOOR_HINGE_X:
        h = DOOR_KN_W / 2 + DOOR_GAP
        cuts.append(cyl("t", (xc - h, A.y, A.x), (xc + h, A.y, A.x), KNUCKLE_R + 0.4, c, 40))
        sx = math.copysign(1, xc)
        x_in = xc - sx * (h + 5.0)                       # imbocco verso il centro
        x_o0 = xc + sx * (h + 5.0)                       # v2: esce anche sul lato esterno (per fare l'asola)
        x_o1 = sx * min(abs(x_o0) + 15.0, xo - 1.5)
        cuts.append(cyl("t", (x_o0 + sx * 0.5, A.y, A.x), (x_in - sx * 0.5, A.y, A.x), WIRE_HOLE_D / 2, c, 16))
        # scanalature d'infilaggio, aperte verso l'INTERNO della scocca (non si vedono)
        b = (SL_U + Vector((0.0, -1.0))).normalized()      # bisettrice verso il vano interno (z, y)
        pb = Vector((-b.y, b.x))
        wq = WIRE_GROOVE_W / 2
        prof = [A + pb * wq, A - pb * wq, A + b * (KNUCKLE_R + 1.0) - pb * wq, A + b * (KNUCKLE_R + 1.0) + pb * wq]
        for g0, g1 in (sorted((x_in, x_in - sx * WIRE_GROOVE_L)), sorted((x_o0, x_o1))):
            bm = bmesh.new()
            for x in (g0, g1):
                for v in prof:
                    bm.verts.new((x, v.y, v.x))
            bmesh.ops.convex_hull(bm, input=bm.verts[:]); bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
            cuts.append(new_obj("t", bm, c))
            cuts.append(cyl("t", (g0, A.y, A.x), (g1, A.y, A.x), WIRE_HOLE_D / 2, c, 16))
    for sx in (1, -1):
        mx = sx * (DOOR_W / 2 - MAG_X_IN)                # magneti nelle battute laterali
        p = Ms @ Vector((mx, DOOR_T_TOP - MAG_T_DOWN, 0.0))
        q = Ms @ Vector((mx, DOOR_T_TOP - MAG_T_DOWN, k0 + MAG_H))
        cuts.append(cyl("t", tuple(p - (q - p).normalized() * 0.5), tuple(q), MAG_D / 2, c, 32))
    # incavo per il dito sopra il bordo alto dello sportello (2 mm, fondo a 45° verso l'alto)
    cuts.append(hull("t", [(rect(-15, 15, DOOR_T_TOP + DOOR_GAP - 0.01, DOOR_T_TOP + 7.0), -WALL - 1.0),
                           (rect(-15, 15, DOOR_T_TOP + DOOR_GAP - 0.01, DOOR_T_TOP + 5.0), -WALL + 2.0)], c, Ms))
    # scassi per incassare i piedini della maniglia (v2)
    for sx in (1, -1):
        x0, x1 = sorted((sx * (H_SPAN / 2 - H_FOOT - H_RECESS_CLR), sx * (H_SPAN / 2 + H_RECESS_CLR)))
        cuts.append(box("t", x0, x1, Y_TOP - H_RECESS, Y_TOP + 1, H_Z_BACK - H_RECESS_CLR,
                        H_Z_BACK + H_DEPTH + H_RECESS_CLR, c))
    # fori maniglia nella parete superiore
    zc = H_Z_BACK + H_DEPTH / 2
    for x in HANDLE_SCREWS_X:
        cuts.append(cyl("t", (x, Y_TOP - WALL - 6, zc), (x, Y_TOP + 2, zc), HOLE_D / 2, c, 24))
    boolean(body, cuts, "DIFFERENCE")
    return body


def build_supporto(c):
    """supporto integrato (si stacca a mano) sotto il bordo alto dell'apertura sportello:
    lama verticale dal piatto fino a 1 strato sotto il bordo + contrafforti. Esportato nello STL della scocca."""
    def y_at(k):
        t = (Z_EDGE - HINGE_A.x + SL_N.x * k) / SL_U.x
        return HINGE_A.y + SL_U.y * t - SL_N.y * k
    y_in, y_out = y_at(0.0) + 0.25, y_at(-WALL) - 0.25
    xs = DOOR_W / 2 + DOOR_GAP - RAIL_IN - 0.6
    zt = Z_EDGE - CURTAIN_GAP
    sup = box("supporto_sportello", -xs, xs, y_in, y_out, ZB, zt, c)
    hz = ZB + 0.6 * (zt - ZB)
    adds = []
    for x in (-xs + 0.6, -45.0, 0.0, 45.0, xs - 0.6):
        for y0, y1 in ((y_in + 0.5, y_in - 12.0), (y_out - 0.5, y_out + 12.0)):
            bm = bmesh.new()
            for dx in (-0.6, 0.6):
                for y, z in ((y0, ZB), (y1, ZB), (y0, hz)):
                    bm.verts.new((x + dx, y, z))
            bmesh.ops.convex_hull(bm, input=bm.verts[:]); bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
            adds.append(new_obj("t", bm, c))
    boolean(sup, adds, "UNION")
    return sup


def offset_poly(pts, ds):
    """sposta ogni lato di un poligono convesso (antiorario) verso l'esterno di ds[i] (numero o lista)."""
    n = len(pts)
    if not isinstance(ds, (list, tuple)):
        ds = [ds] * n
    lines = []
    for i in range(n):
        p, q = Vector(pts[i]), Vector(pts[(i + 1) % n])
        e = (q - p).normalized()
        nrm = Vector((e.y, -e.x))
        lines.append((p + nrm * ds[i], e))
    out = []
    for i in range(n):
        (p1, e1), (p2, e2) = lines[i - 1], lines[i]
        den = e1.x * e2.y - e1.y * e2.x
        t = ((p2.x - p1.x) * e2.y - (p2.y - p1.y) * e2.x) / den
        out.append(tuple(p1 + e1 * t))
    return out


def pouch_dims():
    return POUCH_Z1 - POUCH_Z0, POUCH_H


def pouch_outer():
    A, D, c = POUCH_Z1 - POUCH_Z0, POUCH_D, POUCH_CHAMF
    return [(-A / 2, 0), (A / 2, 0), (A / 2, D - c), (A / 2 - c, D), (-A / 2 + c, D), (-A / 2, D - c)]


def pouch_cavity():
    """vano interno: all'estremità +X un 'tetto' a 45° (soffitto stampabile quando la tasca è coricata)."""
    A, D, Wt, BT = POUCH_Z1 - POUCH_Z0, POUCH_D, POUCH_WALL, POUCH_BACK
    xe, y0, y1 = A / 2 - Wt, BT, D - Wt
    g, ym, ci = (y1 - y0) / 2, (y0 + y1) / 2, POUCH_CHAMF - Wt * (math.sqrt(2) - 1)
    return [(-xe, y0), (xe - g, y0), (xe, ym), (xe - g, y1), (-xe + ci, y1), (-xe, y1 - ci)]


def build_tasca(c):
    """coord. tasca: X = profondità (centrata), Y = verso l'esterno (0 = dorso), Z = altezza."""
    A, H = pouch_dims()
    Wt, BT, CH = POUCH_WALL, POUCH_BACK, POUCH_CH
    fo = pouch_outer()
    top = offset_poly(fo, [0] + [-CH] * 5)                # smusso sul bordo alto (non sul dorso: lì c'è la cerniera)
    body = hull("tasca", [(fo, 0.0), (fo, H - CH), (top, H)], c)
    cav = pouch_cavity()
    cuts = [prism("t", cav, Wt, H + 1, c)]
    cuts.append(hull("t", [(cav, H - 5.5), (offset_poly(cav, 0.8), H - 4.7), (offset_poly(cav, 0.8), H - 3.5),
                           (cav, H - 3.5)], c))           # scanalatura per lo scatto del coperchio
    # (u,v,w) -> (X=-v, Y=w, Z=-u): gocce ed esagoni con la punta verso +X (= in alto in stampa)
    Mt = Matrix(((0, -1, 0, 0), (0, 0, 1, 0), (-1, 0, 0, 0), (0, 0, 0, 1)))
    for X, Z in POUCH_CABLE_P:
        cuts.append(prism("t", teardrop(POUCH_HOLE_D / 2), -1.0, BT + 1.0, c, Matrix.Translation((X, 0, Z)) @ Mt))
    boolean(body, cuts, "DIFFERENCE")
    boolean(body, [prism("t", teardrop(5.0), BT - 0.1, POUCH_BOSS_T, c, Matrix.Translation((X, 0, Z)) @ Mt)
                   for X, Z in POUCH_SCREWS_P], "UNION")
    cuts = []
    for X, Z in POUCH_SCREWS_P:
        cuts.append(cyl("t", (X, -1, Z), (X, POUCH_BOSS_T + 1, Z), HOLE_D / 2, c, 24))
        cuts.append(prism("t", hexagon(POUCH_NUT_AF, vertex_on_x=False), POUCH_BOSS_T - POUCH_NUT_H, POUCH_BOSS_T + 1, c,
                          Matrix.Translation((X, 0, Z)) @ Mt))
    boolean(body, cuts, "DIFFERENCE")
    return body


def build_coperchio(c):
    """coperchio in posizione CHIUSA (coord. tasca)."""
    A, H = pouch_dims()
    Wt, BT, CH = POUCH_WALL, POUCH_BACK, POUCH_CH
    fo = pouch_outer()
    p0 = offset_poly(fo, [-HINGE_LID_Y0] + [-CH] * 5)
    p1 = offset_poly(fo, [-HINGE_LID_Y0] + [-CH - 1.0] * 5)
    plate = hull("coperchio", [(p0, H), (p0, H + 1.0), (p1, H + 2.0)], c)
    cav = pouch_cavity()
    sk, ski = offset_poly(cav, -0.3), offset_poly(cav, -1.9)
    skirt = prism("t", sk, H - 6.5, H + 0.5, c)
    boolean(skirt, hull("t", [(sk, H - 5.4), (offset_poly(cav, 0.3), H - 4.7), (offset_poly(cav, 0.3), H - 4.1),
                              (sk, H - 3.4)], c), "UNION")
    xe = A / 2 - Wt
    boolean(skirt, [prism("t", ski, H - 7.5, H + 0.6, c),
                    box("t", -A, A, -1.0, BT + 2.2, H - 8, H + 1, c),          # niente bordino lato cerniera
                    box("t", -A, -xe + 2.2, -1.0, POUCH_D + 1, H - 8, H + 1, c)], "DIFFERENCE")   # né sull'estremità -X
    tab = prism("t", rr_loop(18.0, 10.0, 3.0, dy=POUCH_D - CH + 1.0), H, H + 2.0, c)
    boolean(plate, [skirt, tab], "UNION")
    return plate


def lid_open_matrix():
    """dal coperchio chiuso a quello aperto di 90° (come esce dalla stampa), asse cerniera lungo X."""
    H = POUCH_H
    return (Matrix.Translation((0, HINGE_T, H)) @ Matrix.Rotation(math.radians(90), 4, "X")
            @ Matrix.Translation((0, -HINGE_T, -H)))


def build_tasca_stampa(c, tasca, coperchio):
    """pezzo unico da stampare: tasca + coperchio aperto + cerniera flessibile."""
    A, H = pouch_dims()
    me = tasca.data.copy()
    one = bpy.data.objects.new("tasca_stampa", me)
    c.objects.link(one)
    lid = bpy.data.objects.new("t", coperchio.data.copy())
    c.objects.link(lid)
    lid.data.transform(lid_open_matrix())
    xe = A / 2 - POUCH_WALL - 1.0
    web = box("t", -xe, xe, 0.0, HINGE_T, H - 2.0, H + HINGE_LID_Y0 - HINGE_T + 1.0, c)
    boolean(one, [lid, web], "UNION")
    return one


def rp_outer():
    L, D, ch = RP_L, RP_D, RP_CHAMF
    return [(-L / 2, 0), (L / 2, 0), (L / 2, D - ch), (L / 2 - ch, D), (-L / 2 + ch, D), (-L / 2, D - ch)]


def build_tasca_post(c):
    """tasca posteriore, coord. tasca: X = lungo il retro (centrata), Y = verso l'esterno (0 = dorso), Z = altezza.
    Si stampa cosi' com'e' (fondo sul piatto): gocce, rinforzi ed esagoni hanno la punta verso +Z."""
    H, CH, BT = RP_H, RP_CH, RP_BACK
    fo = rp_outer()
    inn = offset_poly(fo, [0] + [-CH] * 5)                # smussi su bordo basso e alto (non sul dorso)
    body = hull("tasca_posteriore", [(inn, 0.0), (fo, CH), (fo, H - CH), (inn, H)], c)
    cav = offset_poly(fo, [-BT] + [-RP_WALL] * 5)
    cav0 = offset_poly(cav, -1.5)                         # raccordo a 45° tra fondo e pareti (piu' rigido, si pulisce meglio)
    boolean(body, hull("t", [(cav0, RP_FLOOR), (cav, RP_FLOOR + 1.5), (cav, H + 1)], c), "DIFFERENCE")
    # (u, v, w) -> (X = u, Y = w, Z = v): profili nel piano del dorso, estrusi verso l'esterno
    Mb = Matrix(((1, 0, 0, 0), (0, 0, 1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
    r = 5.0
    boss = circle(r, 40) + [(0.0, r * math.sqrt(2)), (0.0, -r * math.sqrt(2))]   # rombo arrotondato: niente sbalzi
    boolean(body, [hull("t", [(boss, BT - 0.1), (boss, POUCH_BOSS_T)], c, Matrix.Translation((X, 0, Z)) @ Mb)
                   for X, Z in RP_SCREWS_P], "UNION")
    cuts = []
    for X, Z in RP_SCREWS_P:
        cuts.append(cyl("t", (X, -1, Z), (X, POUCH_BOSS_T + 1, Z), HOLE_D / 2, c, 24))
        cuts.append(prism("t", hexagon(POUCH_NUT_AF, vertex_on_x=False), POUCH_BOSS_T - POUCH_NUT_H, POUCH_BOSS_T + 1, c,
                          Matrix.Translation((X, 0, Z)) @ Mb))            # vertice dell'esagono verso l'alto
    for X, Z in RP_CABLE_P:
        cuts.append(prism("t", [(u, -v) for u, v in teardrop(RP_HOLE_D / 2)], -1.0, BT + 1.0, c,
                          Matrix.Translation((X, 0, Z)) @ Mb))
    boolean(body, cuts, "DIFFERENCE")
    return body


def build_sportello(c):
    """sportello a filo della falda (coord. guscio)."""
    Ms = slope_frame()
    A = HINGE_A
    hw = DOOR_W / 2
    tb, tt = DOOR_T_BOT, DOOR_T_TOP
    door = prism("sportello", rr_loop(DOOR_W, tt + 2.0 - tb, 4.0, dy=(tt + 2.0 + tb) / 2), -WALL, 0.0, c, Ms)
    boolean(door, box("t", -hw - 1, hw + 1, -OH, OH, ZB - 50, Z_EDGE - DOOR_GAP, c), "INTERSECT")
    adds = []
    for xc in DOOR_HINGE_X:
        h = DOOR_KN_W / 2
        adds.append(cyl("t", (xc - h, A.y, A.x), (xc + h, A.y, A.x), KNUCKLE_R, c, 40))
        adds.append(prism("t", rect(xc - h, xc + h, 0.0, tb + 1.0), -WALL, 0.0, c, Ms))
    boolean(door, adds, "UNION")
    cuts = []
    for xc in DOOR_HINGE_X:
        h = DOOR_KN_W / 2
        cuts.append(cyl("t", (xc - h - 1, A.y, A.x), (xc + h + 1, A.y, A.x), WIRE_HOLE_D / 2, c, 16))
    for sx in (1, -1):                                   # sedi magneti sulla faccia interna
        mx = sx * (hw - MAG_X_IN)
        p = Ms @ Vector((mx, tt - MAG_T_DOWN, 0.5))
        q = Ms @ Vector((mx, tt - MAG_T_DOWN, -MAG_H))
        cuts.append(cyl("t", tuple(p), tuple(q), MAG_D / 2, c, 32))
    boolean(door, cuts, "DIFFERENCE")
    return door


def build_maniglia(c):
    s, f, cl, bar = H_SPAN / 2, H_FOOT, H_CLEAR, H_BAR
    top = cl + bar
    ro, ri, seg = 10.0, 7.0, 10
    pts = [(-s, 0.0), (-s + f, 0.0)]
    # apertura interna
    ix = s - f
    for i in range(seg + 1):                                  # angolo interno sx
        a = math.radians(180 - 90 * i / seg)
        pts.append((-ix + ri + ri * math.cos(a), cl - ri + ri * math.sin(a)))
    for i in range(seg + 1):                                  # angolo interno dx
        a = math.radians(90 - 90 * i / seg)
        pts.append((ix - ri + ri * math.cos(a), cl - ri + ri * math.sin(a)))
    pts += [(s - f, 0.0), (s, 0.0)]
    for i in range(seg + 1):                                  # angolo esterno dx
        a = math.radians(0 + 90 * i / seg)
        pts.append((s - ro + ro * math.cos(a), top - ro + ro * math.sin(a)))
    for i in range(seg + 1):                                  # angolo esterno sx
        a = math.radians(90 + 90 * i / seg)
        pts.append((-s + ro + ro * math.cos(a), top - ro + ro * math.sin(a)))
    body = poly_prism("maniglia", pts, 0.0, H_DEPTH, c)
    bv = body.modifiers.new("bevel", "BEVEL")
    bv.width, bv.segments, bv.limit_method, bv.angle_limit = 2.5, 3, "ANGLE", math.radians(40)
    bake(body)

    cuts, zc = [], H_DEPTH / 2
    for x in HANDLE_SCREWS_X:                            # inserti a caldo dal fondo dei piedini
        cuts.append(cyl("t", (x, -1, zc), (x, INS_DEPTH, zc), INS_D / 2, c, 32))
        cuts.append(cyl("t", (x, INS_DEPTH - 0.1, zc), (x, INS_DEPTH + INS_EXTRA, zc), HOLE_D / 2, c, 24))
    boolean(body, cuts, "DIFFERENCE")
    return body


def build_pulsanti(c):
    """pistoncini montati (in posizione di riposo) nelle coordinate del guscio."""
    obs = []
    for name, edge, pos, w in active_buttons():
        M, Ui, Up, GL = edge_frame(edge)
        v, zl = btn_v(edge, pos), btn_z(edge, name)
        u_tip, u_fl, u_cap = Up + 0.2 - TIP_EXTRA[name] - FOOT_EXTRA[name], Ui - GL - BTN_FL, Ui + WALL + BTN_CAP + BTN_CAP_EXTRA[name]
        u_step = u_tip + FOOT_EXTRA[name] + BTN_CAP + 1.0   # v3: il corpo pieno si ferma qui; oltre resta solo il piede
        ov = 2 * (BTN_CLR - BTN_BODY_CLR[name])         # v5: sovrametallo del corpo (canale invariato)
        wb, tb = w + ov, BTN_T + ov
        h = tb / 2
        A = M @ btn_axis(v, zl)
        sec = btn_section(wb, tb)
        cap = [(rr_loop(wb - 2 * (1 - math.cos(math.radians(a))) * 1.2, tb - 2 * (1 - math.cos(math.radians(a))) * 1.2,
                        max(0.25, 1.0 - (1 - math.cos(math.radians(a))) * 1.2), 10), u_cap - 1.2 + 1.2 * math.sin(math.radians(a)))
               for a in (0, 30, 60, 85)]                 # testa bombata (raggio 1.2)
        sh = hull("p_" + name, [(sec, u_step)] + cap, c, A)
        # piede "spingibottone" (v3): preme solo nella fascia BTN_FOOT dal vetro, sotto la stondatura dell'iPad.
        # Tratto a sezione piena -> rastremazione >=45° (stampabile coricato) -> fascia esatta negli ultimi 1.6 mm
        b0, b1 = btn_foot_band(edge, name)
        band = rr_loop(w, b1 - b0, 0.5, 8, dy=(b0 + b1) / 2)
        # due solidi convessi separati: hull() è uno scafo convesso e in un pezzo solo "mangerebbe" il gradino
        gamba = hull("t", [(band, u_tip), (band, u_step + 0.3 - 0.95)], c, A)            # fascia costante
        rampa = hull("t", [(band, u_step + 0.3 - 0.95), (sec, u_step + 0.3)], c, A)      # raccordo 45.7°
        boolean(sh, [gamba, rampa], "UNION")
        fl = prism("t", rect(u_fl, u_fl + BTN_FL, v - w / 2 - 1.5, v + w / 2 + 1.5), zl - h, zl + h, c, M)
        boolean(sh, fl, "UNION")
        obs.append(sh)
    return obs


def build_ipad(c):
    T = Matrix.Translation((XI, 0, 0))
    ip = hull("iPad_mini1_rif", [(rr_loop(IPAD_W, IPAD_H, IPAD_R), -PLATE - IPAD_T), (rr_loop(IPAD_W, IPAD_H, IPAD_R), -PLATE)], c, T)
    scr = hull("display_rif", [(rr_loop(159.6, 119.7, 0.5), -PLATE - 0.3), (rr_loop(159.6, 119.7, 0.5), -PLATE + 0.02)], c, T)
    home = hull("home_rif", [(circle(5.5), -PLATE - 0.5), (circle(5.5), -PLATE + 0.02)], c, Matrix.Translation((XI + HOME_X, 0, 0)))
    return ip, scr, home


# ---------------------------------------------------------------- main
def get_coll(name, clear=True):
    c = bpy.data.collections.get(name)
    if c is None:
        c = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(c)
    elif clear:
        for ob in list(c.objects):
            me = ob.data
            bpy.data.objects.remove(ob)
            if me and me.users == 0:
                bpy.data.meshes.remove(me)
    return c


def main(export=True, parts=None):
    """parts: insieme di nomi (cornice, scocca, maniglia, sportello, pulsanti, tasca, tasche_x2, tasca_posteriore)
    da esportare; None = tutti."""
    sc = bpy.context.scene
    sc.unit_settings.system = "METRIC"
    sc.unit_settings.scale_length = 0.001
    sc.unit_settings.length_unit = "MILLIMETERS"
    cube = bpy.data.objects.get("Cube")
    if cube and cube.type == "MESH" and len(cube.data.vertices) == 8:
        bpy.data.objects.remove(cube)

    c, r = get_coll(COLL), get_coll(REF)
    W = Matrix.Translation((0, 0, OH / 2)) @ Matrix.Rotation(math.radians(90), 4, "X")  # vista montata, fondo sul piano
    H_LOC = Matrix.Translation((0, Y_TOP - H_RECESS, H_Z_BACK))

    cornice = build_cornice(c)
    scocca = build_scocca(c)
    maniglia = build_maniglia(c)
    sportello = build_sportello(c)
    ipad, scr, home = build_ipad(r)
    pulsanti = build_pulsanti(c)
    tasca = build_tasca(c)
    coperchio = build_coperchio(c)
    tasca_stampa = build_tasca_stampa(c, tasca, coperchio)
    tasca_stampa.hide_set(True)
    tasca_stampa.hide_render = True
    tasca_post = build_tasca_post(c)
    M_B = Matrix(((1, 0, 0, 0), (0, 0, 1, RP_Y0), (0, -1, 0, ZB), (0, 0, 0, 1)))   # (X, Y, Z) tasca -> scocca
    xo = OW / 2 + POUCH_GAP
    M_R = Matrix(((0, 1, 0, xo), (0, 0, 1, POUCH_Y0), (1, 0, 0, POUCH_ZC), (0, 0, 0, 1)))
    M_L = Matrix(((0, -1, 0, -xo), (0, 0, 1, POUCH_Y0), (-1, 0, 0, POUCH_ZC), (0, 0, 0, 1)))
    m_tpu = material("SF_grigio_scuro", (0.16, 0.17, 0.19), 0.6)      # stesso colore della maniglia
    pouch_obs = []
    for base in (tasca, coperchio):
        base.data.materials.clear()
        base.data.materials.append(m_tpu)
        twin = bpy.data.objects.new(base.name + "_sx", base.data)
        c.objects.link(twin)
        base.name = base.name + "_dx"
        base.matrix_world = W @ M_R
        twin.matrix_world = W @ M_L
        pouch_obs += [base, twin]
    tasca_post.data.materials.clear()
    tasca_post.data.materials.append(m_tpu)
    tasca_post.matrix_world = W @ M_B

    mats = {cornice: material("SF_bianco", (0.85, 0.86, 0.88), 0.45),
            scocca: material("SF_grigio_chiaro", (0.62, 0.64, 0.67), 0.5),
            maniglia: material("SF_grigio_scuro", (0.16, 0.17, 0.19), 0.6),
            sportello: material("SF_grigio_chiaro", (0.62, 0.64, 0.67), 0.5),
            ipad: material("SF_ipad", (0.02, 0.02, 0.025), 0.3),
            scr: material("SF_display", (0.03, 0.10, 0.12), 0.15),
            home: material("SF_home", (0.06, 0.06, 0.07), 0.4)}
    for ob, m in mats.items():
        ob.data.materials.clear()
        ob.data.materials.append(m)
        ob.matrix_world = W
    maniglia.matrix_world = W @ H_LOC
    for ob in (cornice, ipad, scr, home):               # sistema schermo -> inclinato
        ob.matrix_world = W @ TS
    m_puls = material("SF_grigio_scuro", (0.16, 0.17, 0.19), 0.6)
    for ob in pulsanti:
        ob.data.materials.clear()
        ob.data.materials.append(m_puls)
        ob.matrix_world = W @ TS

    report = {}
    prints = {
        cornice: Matrix.Rotation(math.pi, 4, "X"),
        scocca: Matrix.Translation((0, 0, -ZB)),             # retro sul piatto
        maniglia: Matrix.Identity(4),
        sportello: Matrix.Translation((0, 0, WALL)) @ slope_frame().inverted(),   # faccia esterna sul piatto
    }
    os.makedirs(OUT_DIR, exist_ok=True)
    for ob, M in prints.items():
        bad, vol = check(ob)
        bb = [M @ v.co for v in ob.data.vertices]
        size = [round(max(p[i] for p in bb) - min(p[i] for p in bb), 1) for i in range(3)]
        path = os.path.join(OUT_DIR, f"monitor_{ob.name}_{VERSION}.stl")
        if export and (parts is None or ob.name in parts):
            write_stl([ob], path, M)      # v3: niente supporto integrato, i supporti li fa BambuStudio
        report[ob.name] = dict(non_manifold_edges=bad, volume_cm3=round(vol / 1000, 1),
                               print_size_mm=size, stl=path if export else None)
    # pistoncini: un unico STL, distesi sul piatto uno accanto all'altro
    if export and (parts is None or "pulsanti" in parts):
        path = os.path.join(OUT_DIR, f"monitor_pulsanti_{VERSION}.stl")
        with open(path, "wb") as f:
            tris = []
            for i, (ob, (name, edge, pos, w)) in enumerate(zip(pulsanti, active_buttons())):
                Me, Ui, Up, GL = edge_frame(edge)
                v, zl = btn_v(edge, pos), btn_z(edge, name)
                hb = BTN_T / 2 + BTN_CLR - BTN_BODY_CLR[name]      # v5: il corpo con sovrametallo appoggia sul piatto
                P = Matrix.Translation((0, i * 16.0, hb)) @ Matrix.Translation((0, -v, -zl)) @ Me.inverted()
                me = ob.data
                me.calc_loop_triangles()
                for t in me.loop_triangles:
                    tris.append([P @ me.vertices[k].co for k in t.vertices])
            f.write(b"similFranz pulsanti".ljust(80, b" "))
            f.write(struct.pack("<I", len(tris)))
            for vv in tris:
                n = (vv[1] - vv[0]).cross(vv[2] - vv[0])
                if n.length > 0:
                    n.normalize()
                f.write(struct.pack("<12fH", n.x, n.y, n.z, *vv[0], *vv[1], *vv[2], 0))
        report["pulsanti"] = dict(non_manifold_edges=sum(check(o)[0] for o in pulsanti), stl=path)
    # tasche TPU: stesso pezzo per dx e sx (stampare 2 + 2)
    A_ = POUCH_Z1 - POUCH_Z0
    P_pouch = Matrix(((0, 0, 1, 0), (0, -1, 0, 0), (1, 0, 0, A_ / 2), (0, 0, 0, 1)))   # coricata sull'estremità -X
    # v8: piatto con le 2 tasche laterali affiancate (stesso pezzo, la seconda traslata in y)
    bbp = [P_pouch @ v.co for v in tasca_stampa.data.vertices]
    dy2 = max(p.y for p in bbp) - min(p.y for p in bbp) + 6.0
    path2 = os.path.join(OUT_DIR, f"monitor_tasche_x2_{VERSION}.stl")
    if export and (parts is None or "tasche_x2" in parts):
        T0 = Matrix.Translation((0, 0, -min(p.z for p in bbp)))
        me2 = tasca_stampa.data
        me2.calc_loop_triangles()
        tris = [[Mi @ me2.vertices[k].co for k in t.vertices] for Mi in (T0 @ P_pouch, Matrix.Translation((0, dy2, 0)) @ T0 @ P_pouch)
                for t in me2.loop_triangles]
        with open(path2, "wb") as f:
            f.write(b"similFranz tasche x2".ljust(80, b" "))
            f.write(struct.pack("<I", len(tris)))
            for vv in tris:
                n = (vv[1] - vv[0]).cross(vv[2] - vv[0])
                if n.length > 0:
                    n.normalize()
                f.write(struct.pack("<12fH", n.x, n.y, n.z, *vv[0], *vv[1], *vv[2], 0))
    report["tasche_x2"] = dict(print_size_mm=[round(max(p.x for p in bbp) - min(p.x for p in bbp), 1), round(2 * dy2 - 6.0, 1),
                                              round(max(p.z for p in bbp) - min(p.z for p in bbp), 1)],
                               stl=path2 if export else None)
    for ob, M, fname in ((tasca_stampa, P_pouch, "tasca"), (tasca_post, Matrix.Identity(4), "tasca_posteriore")):
        bad, vol = check(ob)
        bb = [M @ Vector(v) for v in ob.bound_box]
        size = [round(max(p[i] for p in bb) - min(p[i] for p in bb), 1) for i in range(3)]
        path = os.path.join(OUT_DIR, f"monitor_{fname}_{VERSION}.stl")
        if export and (parts is None or fname in parts):
            write_stl([ob], path, M)
        report[fname] = dict(non_manifold_edges=bad, volume_cm3=round(vol / 1000, 1), print_size_mm=size,
                             stl=path if export else None)
    return report


if __name__ == "__main__":
    RESULT = main()
    print(RESULT)
