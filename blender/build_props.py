"""Препятствия и детали трасс -> assets/models/props/*.glb.

Запуск из корня проекта (после scripts/tools/import_original_assets.ps1):
    blender -b -P blender/build_props.py

Объекты оригинала (бочка, колонна, коробка предметов) — «3D shape» Construct: коробка с картинкой
на каждой грани; здесь то же самое, грани берут участки атласа из картинок
оригинала (assets/original/textures/...).
Трамплин — наш объект (в оригинале его нет), нарисован в том же стиле:
бока — кирпич оригинала, сверху — свои стрелки, торец — жёлто-чёрные полосы.
Масштаб: 8 px оригинала = 1 м.
"""

import os
import sys

sys.path.append(os.path.dirname(os.path.abspath(__file__)))

import common  # noqa: E402

PIXELS_PER_METER = 8.0
TEXTURES = common.project_path("assets", "original", "textures")


def original(category, name):
    return common.pixels_from_png(os.path.join(TEXTURES, category, name + ".png"))


def build_box_prop(file_name, size_px, z_height_px, faces):
    """Коробка как Shape3D оригинала. faces: тип грани (top/bottom/side/front/back) -> пиксели.
    Начало координат — центр основания."""
    common.reset_scene()
    material = _atlas_material(file_name, faces)

    def rect_for_face(kind, _normal):
        return material[1][kind if kind in material[1] else "side"]

    w = size_px[0] / PIXELS_PER_METER
    d = size_px[1] / PIXELS_PER_METER
    h = z_height_px / PIXELS_PER_METER
    common.add_box(file_name.capitalize(), (w, d, h), (0.0, 0.0, h / 2.0), material[0], rect_for_face)
    common.export_glb(os.path.join("assets", "models", "props", file_name + ".glb"))


def _atlas_material(name, faces):
    atlas = common.Atlas(max(len(rows[0]) for rows in faces.values()))
    for kind, rows in faces.items():
        atlas.add(kind, rows)
    image, rects = atlas.build(name, common.project_path("assets", "models", "props", "%s_%s.png" % (name, name)))
    return common.make_pixel_material(name, image, roughness=0.9), rects


def ramp_top():
    """Верх трамплина 16x24: тёмная дорога, жёлтые края, белые стрелки вверх по склону."""
    art = []
    for y in range(24):
        row = ""
        for x in range(16):
            if x in (0, 15):
                row += "Y"
            elif x in (1, 14):
                row += "K"
            else:
                # Стрелка «^» каждые 8 строк: вершина в центре, плечи расходятся вниз.
                k = y % 8
                if k < 5 and abs(x - 7.5) <= k + 0.5 and abs(x - 7.5) >= k - 1.5:
                    row += "W"
                else:
                    row += "R"
        art.append(row)
    return common.pixels_from_ascii(art, {"Y": "#f2c230", "K": "#222226", "W": "#f0f0f0", "R": "#3d4150"},
                                    noise=0.05, seed=31)


def hazard_stripes(width, height):
    rows = []
    for y in range(height):
        row = []
        for x in range(width):
            row.append(common.hex_to_rgba("#f2c230" if ((x + y) // 3) % 2 == 0 else "#222226"))
        rows.append(row)
    return rows


def build_ramp():
    """Трамплин 6 × 8 м, высота 1.8 м (≈ 13°), подъём к +Y (в Godot — к -Z)."""
    common.reset_scene()
    material, rects = _atlas_material("ramp", {
        "top": ramp_top(),
        "front": hazard_stripes(16, 8),
        "side": original("tiles", "tile_00"),
        "bottom": original("tiles", "tile_00"),
    })

    def rect_for_face(kind, _normal):
        return rects[kind if kind in rects else "side"]

    common.add_wedge("Ramp", 6.0, 8.0, 1.8, material, rect_for_face)
    common.export_glb(os.path.join("assets", "models", "props", "ramp.glb"))


# Бочка (Barrel): 16×16 px, высота 24 px; кадр 1 — крышка, 0 — дно, 2..5 — бока.
build_box_prop("barrel", (16, 16), 24, {
    "top": original("levelobj", "barrel-001"),
    "bottom": original("levelobj", "barrel-000"),
    "side": original("levelobj", "barrel-002"),
})

# Колонна эстакады (Сolumn): 16×16 px, высота 48 px (6 м); бока 8×32, торцы 8×8.
build_box_prop("column", (16, 16), 48, {
    "top": original("levelobj", "column-000"),
    "bottom": original("levelobj", "column-001"),
    "side": original("levelobj", "column-002"),
})

build_ramp()

# Коробка предметов (ItemBox): куб 16 px (2 м); на всех гранях радужный «?» (кадры 1..5
# одинаковые, кадр 0 — пустой). Полупрозрачность и вращение — в сцене Godot.
build_box_prop("item_box", (16, 16), 16, {
    "top": original("objects", "itembox-001"),
    "bottom": original("objects", "itembox-001"),
    "side": original("objects", "itembox-001"),
})
