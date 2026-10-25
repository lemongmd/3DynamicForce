"""Временные пиксельные текстуры уровней -> assets/textures/*.png.

Запуск из корня проекта:
    blender -b -P blender/build_textures.py

Дорога, кирпич и фоны трасс теперь берутся из ассетов оригинала
(assets/original, см. scripts/tools/import_original_assets.ps1). Здесь остались
только текстуры тестовой площадки, травы и шахматки старта.
"""

import os
import random
import sys

sys.path.append(os.path.dirname(os.path.abspath(__file__)))

import common  # noqa: E402


def grass_blades():
    """Трава 16x16: яркий фон и короткие диагональные травинки."""
    rng = random.Random(22)
    base = common.hex_to_rgba("#4cb02a")
    rows = [[common.shade(base, 1.0 + rng.uniform(-0.06, 0.06)) for _ in range(16)] for _ in range(16)]
    blade_light = common.hex_to_rgba("#7ee04a")
    blade_dark = common.hex_to_rgba("#36901c")
    for i in range(14):
        x = rng.randrange(16)
        y = rng.randrange(16)
        color = blade_light if i % 2 == 0 else blade_dark
        for k in range(3):
            rows[(y - k) % 16][(x + k // 2) % 16] = color
    return rows


def checker():
    """Шахматка 8x8 (клетки 4x4) для стартовой линии и арки."""
    white = common.hex_to_rgba("#f0f0f0")
    black = common.hex_to_rgba("#202024")
    return [[white if ((x // 4) + (y // 4)) % 2 == 0 else black for x in range(8)] for y in range(8)]


def build():
    common.reset_scene()
    out = common.project_path("assets", "textures")

    # Асфальт тестовой площадки: плитка 32x32 с заметной сеткой (видно скорость).
    common.save_png(
        common.tile_pixels(32, "#4a4d55", border="#555862", noise=0.08, seed=10),
        os.path.join(out, "asphalt.png"),
    )

    common.save_png(grass_blades(), os.path.join(out, "grass.png"))
    common.save_png(checker(), os.path.join(out, "checker.png"))

    # Ящик-препятствие.
    common.save_png(
        common.pixels_from_ascii(
            [
                "DDDDDDDDDDDDDDDD",
                "DLLLLLLLLLLLLLLD",
                "DLDDDDDDDDDDDDLD",
                "DLDWWWWWWWWWDDLD",
                "DLDDWWWWWWWWWDLD",
                "DLDWDWWWWWWWWDLD",
                "DLDWWDWWWWWWWDLD",
                "DLDWWWDWWWWWWDLD",
                "DLDWWWWDWWWWWDLD",
                "DLDWWWWWDWWWWDLD",
                "DLDWWWWWWDWWWDLD",
                "DLDWWWWWWWDWWDLD",
                "DLDWWWWWWWWDWDLD",
                "DLDDDDDDDDDDDDLD",
                "DLLLLLLLLLLLLLLD",
                "DDDDDDDDDDDDDDDD",
            ],
            {"D": "#5a3a1e", "L": "#a8763e", "W": "#8a5c2c"},
        ),
        os.path.join(out, "crate.png"),
    )

    # Жёлто-чёрная «опасность» для пандусов и бортов.
    rows = []
    for y in range(16):
        row = []
        for x in range(16):
            row.append(common.hex_to_rgba("#f2c230" if ((x + y) // 4) % 2 == 0 else "#222226"))
        rows.append(row)
    common.save_png(rows, os.path.join(out, "hazard.png"))

    build_fx(os.path.join(out, "fx"))


# Палитра спрайтов эффектов: белые с серыми тенями — цвет задаёт частица
# (дым серый, огонь жёлто-красный, искры жёлтые), «.» — прозрачно.
FX_PALETTE = {".": "#00000000", "W": "#ffffff", "L": "#dcdcdc", "G": "#a8a8a8", "D": "#7c7c7c"}


def build_fx(out):
    """Спрайты эффектов: дым, огонь, искра, звезда удара, кольцо."""
    os.makedirs(out, exist_ok=True)
    sprites = {
        # Клуб дыма 8x8: круглый, светлый сверху-слева, тень снизу-справа.
        "puff": [
            "..WWWW..",
            ".WWWWLL.",
            "WWWWWLLG",
            "WWWWLLLG",
            "WWWLLLGG",
            "WLLLLGGG",
            ".LLGGGD.",
            "..GGDD..",
        ],
        # Язык пламени 8x8 (окрашивается от жёлтого к красному).
        "flame": [
            "...W....",
            "...WW...",
            "..WWW...",
            "..WWWL..",
            ".WWWWL..",
            ".WWWLLG.",
            ".WWLLLG.",
            "..LLGG..",
        ],
        # Искра 4x4.
        "spark": [
            ".W..",
            "WWWL",
            ".WL.",
            ".L..",
        ],
        # Звезда удара 8x8 (как «бонк» в мультиках).
        "star": [
            "...W....",
            "...WW...",
            "WWWWWWWL",
            ".WWWWWL.",
            "..WWWL..",
            ".WWLWWL.",
            ".WL..WL.",
            "W.....L.",
        ],
        # Кольцо ударной волны 16x16 (лежит на земле).
        "ring": [
            ".....WWWWWW.....",
            "...WWLLLLLLWW...",
            "..WLL......LLW..",
            ".WL..........LW.",
            ".WL..........LW.",
            "WL............LW",
            "WL............LG",
            "WL............LG",
            "WL............LG",
            "WL............LG",
            "GL............LG",
            ".GL..........LG.",
            ".GL..........LG.",
            "..GLL......LLG..",
            "...GGLLLLLLGG...",
            ".....GGGGGG.....",
        ],
    }
    for name, art in sprites.items():
        common.save_png(common.pixels_from_ascii(art, FX_PALETTE), os.path.join(out, "fx_%s.png" % name))


build()
