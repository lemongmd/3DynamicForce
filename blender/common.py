"""Общие помощники для генерации моделей и текстур 3Dynamic Force.

Запуск скриптов (из корня проекта):
    blender -b -P blender/build_car.py
    blender -b -P blender/build_textures.py

Стиль: простые 3D-формы (призмы, цилиндры) с пиксель-арт текстурами,
как 3D-фигуры в Construct 3 у оригинала, но в настоящем 3D.

Соглашения:
  * Перед модели смотрит в +Y в Blender. При экспорте в glTF это становится -Z,
    то есть «вперёд» в Godot.
  * Все текстуры — маленькие пиксельные картинки, интерполяция Closest
    (в glTF уходит как фильтр NEAREST).
  * Картинки одной модели собираются в атлас (одна текстура и один материал на модель).
    Каждая грань получает свой участок атласа целиком, по типу грани:
    top / bottom / front / back / side.
"""

import math
import os
import random
import tempfile

import bmesh
import bpy

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
_TMP_DIR = tempfile.mkdtemp(prefix="3df_blender_")


def is_hand_drawn(path):
    """Картинка из списка assets/hand_drawn.txt (перерисована вручную) — не перезаписывать."""
    list_path = os.path.join(PROJECT_ROOT, "assets", "hand_drawn.txt")
    if not os.path.exists(list_path):
        return False
    relative = os.path.relpath(os.path.abspath(path), PROJECT_ROOT).replace(os.sep, "/")
    with open(list_path, encoding="utf-8") as f:
        return any(line.strip() == relative for line in f)


def project_path(*parts):
    """Абсолютный путь внутри проекта Godot."""
    return os.path.join(PROJECT_ROOT, *parts)


def reset_scene():
    """Полностью пустая сцена без куба, камеры и света по умолчанию."""
    bpy.ops.wm.read_factory_settings(use_empty=True)


# --------------------------------------------------------------------------
# Пиксели
# --------------------------------------------------------------------------

def hex_to_rgba(value):
    """'#rrggbb' или '#rrggbbaa' -> кортеж float 0..1 (значения sRGB как есть)."""
    value = value.lstrip("#")
    r = int(value[0:2], 16) / 255.0
    g = int(value[2:4], 16) / 255.0
    b = int(value[4:6], 16) / 255.0
    a = int(value[6:8], 16) / 255.0 if len(value) >= 8 else 1.0
    return (r, g, b, a)


def shade(rgba, factor):
    """Осветлить (>1) или затемнить (<1) цвет."""
    return (
        min(1.0, rgba[0] * factor),
        min(1.0, rgba[1] * factor),
        min(1.0, rgba[2] * factor),
        rgba[3],
    )


def rect_pixels(width, height, base, border=None, noise=0.0, seed=0, border_width=1):
    """Пиксельный прямоугольник: базовый цвет, лёгкий шум и рамка.

    Возвращает список строк пикселей [y][x] (y=0 — верх картинки) из RGBA.
    """
    rng = random.Random(seed)
    base_rgba = hex_to_rgba(base)
    border_rgba = hex_to_rgba(border) if border else None
    rows = []
    for y in range(height):
        row = []
        for x in range(width):
            on_border = border_rgba is not None and (
                x < border_width or y < border_width
                or x >= width - border_width or y >= height - border_width
            )
            if on_border:
                row.append(border_rgba)
            elif noise > 0.0:
                row.append(shade(base_rgba, 1.0 + rng.uniform(-noise, noise)))
            else:
                row.append(base_rgba)
        rows.append(row)
    return rows


def tile_pixels(size, base, border=None, noise=0.0, seed=0, border_width=1):
    """Квадратная плитка (см. rect_pixels)."""
    return rect_pixels(size, size, base, border, noise, seed, border_width)


def pixels_from_ascii(art, palette, noise=0.0, seed=0):
    """ASCII-арт -> пиксели. art: строки одинаковой длины, palette: символ -> '#hex'.

    noise > 0 слегка «шумит» яркость непрозрачных пикселей (живее выглядит).
    """
    rng = random.Random(seed)
    rows = []
    for line in art:
        row = []
        for ch in line:
            rgba = hex_to_rgba(palette[ch])
            if noise > 0.0 and rgba[3] > 0.0:
                rgba = shade(rgba, 1.0 + rng.uniform(-noise, noise))
            row.append(rgba)
        rows.append(row)
    return rows


def pixels_from_png(path):
    """PNG-файл -> пиксели [y][x] (y=0 — верх), например картинки граней из оригинала."""
    image = bpy.data.images.load(path, check_existing=False)
    width, height = image.size
    flat = list(image.pixels)
    rows = []
    # В Blender строка 0 — низ картинки.
    for y in range(height - 1, -1, -1):
        row = []
        for x in range(width):
            i = (y * width + x) * 4
            row.append((flat[i], flat[i + 1], flat[i + 2], flat[i + 3]))
        rows.append(row)
    bpy.data.images.remove(image)
    return rows


def _flat_pixels(rows):
    """[y][x] (y=0 — верх) -> плоский список RGBA в порядке Blender (строка 0 — низ)."""
    flat = []
    for y in range(len(rows) - 1, -1, -1):
        for x in range(len(rows[0])):
            flat.extend(rows[y][x])
    return flat


def make_image(name, rows):
    """Картинка Blender из пикселей [y][x]; упакована, чтобы glTF-экспорт её встроил."""
    image = bpy.data.images.new(name, width=len(rows[0]), height=len(rows), alpha=True)
    image.pixels.foreach_set(_flat_pixels(rows))
    image.filepath_raw = os.path.join(_TMP_DIR, name + ".png")
    image.file_format = "PNG"
    image.save()
    image.pack()
    return image


def save_png(rows, path):
    """Сохраняет пиксели [y][x] в PNG-файл (для текстур, которые Godot грузит напрямую)."""
    if is_hand_drawn(path):
        print("skipped (hand drawn, assets/hand_drawn.txt):", path)
        return
    os.makedirs(os.path.dirname(path), exist_ok=True)
    name = "tmp_" + os.path.splitext(os.path.basename(path))[0]
    image = bpy.data.images.new(name, width=len(rows[0]), height=len(rows), alpha=True)
    image.pixels.foreach_set(_flat_pixels(rows))
    image.filepath_raw = path
    image.file_format = "PNG"
    image.save()
    bpy.data.images.remove(image)
    print("saved texture:", path)


# --------------------------------------------------------------------------
# Атлас и материал
# --------------------------------------------------------------------------

class Atlas:
    """Складывает пиксельные картинки столбиком в одну текстуру.

    Высота каждого участка выравнивается до 8 пикселей, чтобы мипмапы
    (до 1/8) не смешивали соседние участки.
    """

    ALIGN = 8
    # Отступ UV внутрь участка (в текселях), чтобы Nearest не цеплял соседа.
    INSET = 0.02

    def __init__(self, width):
        self.width = width
        self._items = []  # (имя, пиксели)

    def add(self, name, rows):
        if len(rows[0]) > self.width:
            raise ValueError("Atlas: '%s' шире атласа (%d > %d)" % (name, len(rows[0]), self.width))
        self._items.append((name, rows))

    def build(self, image_name, hand_drawn_path=None):
        """Возвращает (картинка Blender, {имя: (u0, v0, u1, v1)}).

        hand_drawn_path — файл атласа, который Godot извлекает из .glb: если он в списке
        assets/hand_drawn.txt (перерисован вручную) и того же размера, пиксели берутся из него.
        """
        transparent = (0.0, 0.0, 0.0, 0.0)
        placed = []
        total = 0
        for name, rows in self._items:
            placed.append((name, rows, total))
            total += -(-len(rows) // self.ALIGN) * self.ALIGN
        atlas_rows = [[transparent] * self.width for _ in range(total)]
        rects = {}
        # Участки в пикселях (x, y, ширина, высота; y=0 — верх) — для скинов (build_car.py).
        self.pixel_rects = {}
        self.height = total
        for name, rows, top in placed:
            self.pixel_rects[name] = (0, top, len(rows[0]), len(rows))
            h, w = len(rows), len(rows[0])
            for y in range(h):
                atlas_rows[top + y][:w] = rows[y]
            du = self.INSET / self.width
            dv = self.INSET / total
            rects[name] = (
                du,
                1.0 - (top + h) / total + dv,
                w / self.width - du,
                1.0 - top / total - dv,
            )
        if hand_drawn_path and is_hand_drawn(hand_drawn_path):
            drawn = pixels_from_png(hand_drawn_path)
            if len(drawn) == total and len(drawn[0]) == self.width:
                print("atlas from hand drawn:", hand_drawn_path)
                atlas_rows = drawn
            else:
                print("WARNING: hand drawn atlas size differs, generated one used:", hand_drawn_path)
        return make_image(image_name, atlas_rows), rects


def make_pixel_material(name, image, roughness=0.8, metallic=0.0):
    """Материал Principled BSDF с пиксельной текстурой (интерполяция Closest)."""
    mat = bpy.data.materials.new(name)
    if mat.node_tree is None:
        mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    bsdf = None
    for node in nodes:
        if node.type == "BSDF_PRINCIPLED":
            bsdf = node
            break
    if bsdf is None:
        for node in list(nodes):
            nodes.remove(node)
        bsdf = nodes.new("ShaderNodeBsdfPrincipled")
        output = nodes.new("ShaderNodeOutputMaterial")
        links.new(bsdf.outputs["BSDF"], output.inputs["Surface"])
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = image
    tex.interpolation = "Closest"
    links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    return mat


# --------------------------------------------------------------------------
# Геометрия
# --------------------------------------------------------------------------

def face_kind(normal):
    """Тип грани по нормали: top / bottom / front / back / side."""
    ax, ay, az = abs(normal.x), abs(normal.y), abs(normal.z)
    if az >= ax and az >= ay:
        return "top" if normal.z > 0.0 else "bottom"
    if ay > ax + 0.1:
        return "front" if normal.y > 0.0 else "back"
    return "side"


def apply_atlas_uvs(obj, rect_for_face):
    """Каждой грани — участок атласа целиком.

    rect_for_face(kind, normal) -> (u0, v0, u1, v1). Грань проецируется на свою
    плоскость и растягивается на участок; картинка читается правильно (не зеркально),
    если смотреть на грань снаружи. Верх: перед машины (+Y) — верх картинки.
    """
    mesh = obj.data
    bm = bmesh.new()
    bm.from_mesh(mesh)
    uv_layer = bm.loops.layers.uv.verify()
    for face in bm.faces:
        n = face.normal
        kind = face_kind(n)
        u0, v0, u1, v1 = rect_for_face(kind, n)
        ax, ay, az = abs(n.x), abs(n.y), abs(n.z)
        if az >= ax and az >= ay:
            ia, ib, flip_a = 0, 1, n.z < 0.0
        elif ay > ax + 0.1:
            ia, ib, flip_a = 0, 2, n.y > 0.0
        else:
            ia, ib, flip_a = 1, 2, n.x < 0.0
        coords = [(loop.vert.co[ia], loop.vert.co[ib]) for loop in face.loops]
        min_a = min(c[0] for c in coords)
        max_a = max(c[0] for c in coords)
        min_b = min(c[1] for c in coords)
        max_b = max(c[1] for c in coords)
        span_a = max(max_a - min_a, 1e-6)
        span_b = max(max_b - min_b, 1e-6)
        for loop, (a, b) in zip(face.loops, coords):
            ta = (a - min_a) / span_a
            if flip_a:
                ta = 1.0 - ta
            tb = (b - min_b) / span_b
            loop[uv_layer].uv = (u0 + ta * (u1 - u0), v0 + tb * (v1 - v0))
    bm.to_mesh(mesh)
    bm.free()


def add_prism(name, bottom, top, z0, z1, material, rect_for_face, location=(0.0, 0.0, 0.0)):
    """Призма: многоугольник bottom (на высоте z0) соединён с многоугольником top (на z1).

    bottom/top — списки (x, y) одинаковой длины, обход против часовой стрелки
    (если смотреть сверху). Если top меньше bottom — получаются скошенные стенки
    (например, лобовое стекло).
    """
    if len(bottom) != len(top):
        raise ValueError("add_prism(%s): у низа и верха разное число вершин" % name)
    bm = bmesh.new()
    vb = [bm.verts.new((x, y, z0)) for x, y in bottom]
    vt = [bm.verts.new((x, y, z1)) for x, y in top]
    count = len(bottom)
    bm.faces.new(vt)
    bm.faces.new(list(reversed(vb)))
    for i in range(count):
        j = (i + 1) % count
        bm.faces.new([vb[i], vb[j], vt[j], vt[i]])
    bm.normal_update()
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(material)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = location
    apply_atlas_uvs(obj, rect_for_face)
    return obj


def add_polyhedron(name, verts, faces, material, rect_for_face, location=(0.0, 0.0, 0.0)):
    """Многогранник по вершинам и граням (индексы вершин, обход против часовой стрелки,
    если смотреть снаружи). UV — участки атласа по типу грани, как у add_prism."""
    bm = bmesh.new()
    bverts = [bm.verts.new(v) for v in verts]
    for face in faces:
        bm.faces.new([bverts[i] for i in face])
    bm.normal_update()
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(material)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = location
    apply_atlas_uvs(obj, rect_for_face)
    return obj


def add_wedge(name, width, length, height, material, rect_for_face):
    """Клин-трамплин: основание width × length, подъём к +Y до высоты height.
    Начало координат — центр основания. Грани: низ, наклонный верх (top), торец (front), бока."""
    hw, hl = width / 2.0, length / 2.0
    verts = [
        (-hw, -hl, 0.0), (hw, -hl, 0.0), (hw, hl, 0.0), (-hw, hl, 0.0),
        (-hw, hl, height), (hw, hl, height),
    ]
    faces = [(0, 3, 2, 1), (0, 1, 5, 4), (3, 4, 5, 2), (0, 4, 3), (1, 2, 5)]
    return add_polyhedron(name, verts, faces, material, rect_for_face)


def add_box(name, size, center, material, rect_for_face):
    """Параллелепипед size=(x, y, z) с центром center (через add_prism)."""
    hx, hy, hz = size[0] / 2.0, size[1] / 2.0, size[2] / 2.0
    rect = [(-hx, -hy), (hx, -hy), (hx, hy), (-hx, hy)]
    return add_prism(name, rect, rect, -hz, hz, material, rect_for_face, location=center)


def add_cylinder_x(name, radius, width, location, material, rect_for_face, vertices=10):
    """Цилиндр с осью вдоль X (колесо). Начало координат — центр цилиндра."""
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices, radius=radius, depth=width, location=location, rotation=(0.0, 1.5707963, 0.0)
    )
    obj = bpy.context.active_object
    obj.name = name
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    obj.data.materials.append(material)
    apply_atlas_uvs(obj, rect_for_face)
    return obj


def add_cylinder_z(name, radius, height, segments, material, rects, wraps=1):
    """Вертикальный цилиндр (бочка), начало координат — центр основания.

    rects: {"side", "top", "bottom"} -> участок атласа (u0, v0, u1, v1). Бок — картинка
    side, обёрнутая wraps раз по кругу (не зеркалится, если смотреть снаружи), низ участка —
    низ цилиндра; крышки — картинки top/bottom, спроецированные сверху на круг (перед +Y —
    верх картинки, как у apply_atlas_uvs).
    """

    mesh = bpy.data.meshes.new(name)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new()
    ring = [(math.cos(2.0 * math.pi * i / segments) * radius, math.sin(2.0 * math.pi * i / segments) * radius)
            for i in range(segments)]
    low = [bm.verts.new((x, y, 0.0)) for x, y in ring]
    high = [bm.verts.new((x, y, height)) for x, y in ring]
    u0, v0, u1, v1 = rects["side"]
    for i in range(segments):
        j = (i + 1) % segments
        face = bm.faces.new((low[i], low[j], high[j], high[i]))
        # Доля картинки: wraps раз на круг; угол растёт против часовой (вид сверху) —
        # снаружи это движение вправо, поэтому u растёт вместе с ним.
        a = (i * wraps / segments) % 1.0
        b = a + wraps / segments
        coords = [(a, 0.0), (b, 0.0), (b, 1.0), (a, 1.0)]
        for loop, (tu, tv) in zip(face.loops, coords):
            loop[uv_layer].uv = (u0 + tu * (u1 - u0), v0 + tv * (v1 - v0))
    for kind, verts, flip in (("top", high, False), ("bottom", list(reversed(low)), True)):
        c0, d0, c1, d1 = rects[kind]
        face = bm.faces.new(verts)
        for loop in face.loops:
            x, y = loop.vert.co.x, loop.vert.co.y
            tu = (x / radius + 1.0) * 0.5
            if flip:
                tu = 1.0 - tu
            tv = (y / radius + 1.0) * 0.5
            loop[uv_layer].uv = (c0 + tu * (c1 - c0), d0 + tv * (d1 - d0))
    bm.normal_update()
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(material)
    # Плоские грани — пиксельный стиль, как у остальных моделей.
    for poly in mesh.polygons:
        poly.use_smooth = False
    return obj


def export_glb(relative_path):
    """Экспорт всей сцены в .glb внутри проекта."""
    path = project_path(relative_path)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_apply=True)
    print("exported:", path)
