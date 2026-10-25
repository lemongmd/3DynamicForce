"""Машины для скинов -> assets/models/cars/car_<кузов>.glb + car_<кузов>.json.

Запуск из корня проекта:
    blender -b -P blender/build_car.py

Скины как в оригинале (Player + PlayerSkinPart): кузов (3 формы + секретный танк) красится
в цвет игрока, стёкла (11), рисунок (9) и колёса (4) — меняются. Модель одна на кузов:
кузов нарисован в серых тонах, цвет, стёкла, рисунок и колёса игра накладывает сама
(CarSkin, scripts/car/car_skin.gd) по карте букв из .json.

Формы кузовов — по спрайтам оригинала player-base 0..3 (вид сверху 24×16 px = 3 × 2 м):
  0 «седан» — скруглённый, с выемкой спереди (наша прежняя машина);
  1 «спорт» — вырезы под колёса спереди и сзади, низкая кабина ближе к корме;
  2 «фургон» — ровный скруглённый прямоугольник, длинная высокая кабина;
  3 «танк» — секретный (в оригинале — если зажать кнопку кузова): корпус, гусеницы, башня.

Модели чисто визуальные: логика игры от них не зависит (коллизия задаётся
в сцене scenes/car/car.tscn). Перед машины смотрит в +Y (в Godot это -Z).
Начало координат — центр машины на уровне земли.
Колёса — отдельные объекты Wheel_FL/FR/RL/RR с центром в оси (их крутит CarVisual).

.json рядом с моделью: размер атласа, участки (в пикселях), буквы атласа по строкам
(какая часть машины в каждом пикселе), чистые цвета букв и площадь верхних граней в метрах
(куда класть рисунок).
"""

import json
import os
import sys

sys.path.append(os.path.dirname(os.path.abspath(__file__)))

import common  # noqa: E402

# Кузов — в серых тонах (игра умножает на цвет скина, как set-default-color оригинала):
# R — основной, H — блик, S — тень, D — тёмная кромка.
# Стёкла G/L, шина W/V и диск M/N игра перекрашивает по скину. Остальное — как есть:
# Y — фары, T — поворотники/стопы, P — номер, K — решётка и низ.
PALETTE = {
    ".": "#00000000",
    "R": "#d4d4d4",
    "H": "#ffffff",
    "S": "#a4a4a4",
    "D": "#505050",
    "G": "#2f6fd6",
    "L": "#8fd0ff",
    "Y": "#ffe066",
    "T": "#ff9a1f",
    "P": "#e8e8e0",
    "K": "#2a2a30",
    "W": "#26262c",
    "V": "#3c3c46",
    "M": "#a0a0a8",
    "N": "#dcdce4",
    # Танк: камуфляж (тоже красится цветом скина), гусеницы, ствол.
    "A": "#6fae3c",
    "B": "#3f7a2a",
    "C": "#a8d860",
    "E": "#2e3a24",
    "X": "#4a4a50",
    "Z": "#7a7a84",
}

# Буквы по ролям (для игры, в .json).
ROLES = {
    "tint": "RHSDABCE",
    "glass": {"G": "main", "L": "light"},
    "tire": {"W": "main", "V": "tread"},
    "rim": {"M": "main", "N": "hub"},
}

# Верх кузова (капот и багажник; середину закрывает кабина). Строка 0 — перед.
BODY_TOP = ["DDDDDDDDDDDDDDDD", "DHHHHHHHHHHHHHHD"] + ["DSRRRRRRRRRRRRSD"] * 20 + [
    "DSSSSSSSSSSSSSSD",
    "DDDDDDDDDDDDDDDD",
]

BODY_SIDE = [
    "HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH",
    "RRRRRRRRRRRRRRSRRRRRRRRRRRRRRRRR",
    "RRRRRRRRRRRRRRSRRRRRRRRRRRRRRRRR",
    "SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSS",
    "DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD",
]

BODY_FRONT = [
    "HHHHHHHHHHHHHHHH",
    "RYYYRRRRRRRRYYYR",
    "RYYYRKKKKKKRYYYR",
    "SSSSSKKKKKKSSSSS",
    "DDDDDDDDDDDDDDDD",
]

BODY_BACK = [
    "HHHHHHHHHHHHHHHH",
    "RTTTRRRRRRRRTTTR",
    "RTTTRRPPPPRRTTTR",
    "SSSSSSPPPPSSSSSS",
    "DDDDDDDDDDDDDDDD",
]

GLASS = [
    "DDDDDDDDDDDDDDDD",
    "DGGGGGGGGGGLLGGD",
    "DGGGGGGGGGLLGGGD",
    "DGGGGGGGGLLGGGGD",
    "DGGGGGGGLLGGGGGD",
    "DGGGGGGLLGGGGGLD",
    "DGGGGGLLGGGGGLLD",
    "DDDDDDDDDDDDDDDD",
]

CABIN_SIDE = [
    "DDDDDDDDDDDDDDDDDDDDDDDD",
    "DGGGGGGLLGGDDGGGGGGLLGGD",
    "DGGGGGLLGGGDDGGGGGLLGGGD",
    "DGGGGLLGGGGDDGGGGLLGGGGD",
    "DGGGLLGGGGGDDGGGLLGGGGGD",
    "DGGLLGGGGGGDDGGLLGGGGGGD",
    "DGLLGGGGGGGDDGLLGGGGGGGD",
    "DDDDDDDDDDDDDDDDDDDDDDDD",
]

ROOF = ["DDDDDDDDDDDDDDDD", "DHHHHHHHHHHHHHHD"] + ["DRRRRRRRRRRRRRRD"] * 12 + [
    "DSSSSSSSSSSSSSSD",
    "DDDDDDDDDDDDDDDD",
]

TIRE = [
    "WWWWWWWW",
    "WVVWWVVW",
    "WWVVWWVV",
    "WWWVVWWV",
    "WWVVWWVV",
    "WVVWWVVW",
    "VVWWVVWW",
    "WWWWWWWW",
]

RIM = [
    "WWWWWWWW",
    "WWMMMMWW",
    "WMMMMMMW",
    "WMMNNMMW",
    "WMMNNMMW",
    "WMMMMMMW",
    "WWMMMMWW",
    "WWWWWWWW",
]

UNDERSIDE = ["KKKKKKKK"] * 8

# Танк (по спрайту player-base-003: зелёный камуфляж, серые гусеницы, башня с люком).
TANK_TOP = [
    "EEEEEEEEEEEEEEEE",
    "EAAAAAAABBBAAAAE",
    "EAABBAAAABBAAAAE",
    "EABBBAACAAAABBAE",
    "EAABAACCAAABBBAE",
    "EAAAAAAAAAAABAAE",
    "EABBAAAAABAAAAAE",
    "EBBBAAAABBBAACAE",
    "EABAAACAABAACCAE",
    "EAAAACCAAAAAAAAE",
    "EAAAAAAAAABBAAAE",
    "EAABBAAAAABBBAAE",
    "EABBBAAACAAAAAAE",
    "EAABAAAACCAAABAE",
    "EAAAAAAAAAAABBAE",
    "EEEEEEEEEEEEEEEE",
]
TANK_SIDE = [
    "CCCCCCCCCCCCCCCCCCCCCCCC",
    "AAAAAABBAAAAAAAABBBAAAAA",
    "AABBAAAAAAABBAAAAAAAABAA",
    "BBAAAAAAAAAAAAAAAAAABBBA",
    "EEEEEEEEEEEEEEEEEEEEEEEE",
]
TANK_TURRET = [
    "EEEEEEEEEEEE",
    "ECCCCCCCCCCE",
    "ECAAAAAAAACE",
    "ECAABBBBAACE",
    "ECAABXXBAACE",
    "ECAABXXBAACE",
    "ECAABBBBAACE",
    "ECAAAAAAAACE",
    "ECAAAAAAAACE",
    "ECAAAAAAAACE",
    "ECCCCCCCCCCE",
    "EEEEEEEEEEEE",
]
TRACK = [
    "XZXZXZXZ",
    "ZXXZXXZX",
    "XZXZXZXZ",
    "XXXXXXXX",
    "ZXZXZXZX",
    "XZXXZXXZ",
    "ZXZXZXZX",
    "XXXXXXXX",
]
BARREL = ["EEEE", "ZXXZ", "ZXXZ", "EEEE"]

# Колёса машин.
WHEEL_RADIUS = 0.3
WHEEL_WIDTH = 0.26
BODY_BOTTOM = 0.16

# Кузова: контур (против часовой стрелки сверху, +Y — перед), высота, кабина, колёса.
BASES = {
    "base0": {
        "body": [(-0.62, -1.5), (0.62, -1.5), (0.8, -1.32), (0.8, 1.18),
                 (0.48, 1.5), (-0.48, 1.5), (-0.8, 1.18), (-0.8, -1.32)],
        "body_top": 0.58,
        "cabin_bottom": [(-0.66, -0.95), (0.66, -0.95), (0.66, 0.45), (-0.66, 0.45)],
        "cabin_top": [(-0.56, -0.8), (0.56, -0.8), (0.56, 0.0), (-0.56, 0.0)],
        "cabin_z": 0.98,
        "wheels": (0.83, 0.95),
    },
    # Вырезы под колёса спереди и сзади (как у спрайта player-base-001).
    "base1": {
        "body": [(-0.6, -1.55), (0.6, -1.55), (0.8, -1.35), (0.8, -1.25), (0.6, -1.2),
                 (0.6, -0.7), (0.8, -0.65), (0.8, 0.65), (0.6, 0.7), (0.6, 1.2),
                 (0.8, 1.25), (0.8, 1.3), (0.5, 1.6), (-0.5, 1.6), (-0.8, 1.3),
                 (-0.8, 1.25), (-0.6, 1.2), (-0.6, 0.7), (-0.8, 0.65), (-0.8, -0.65),
                 (-0.6, -0.7), (-0.6, -1.2), (-0.8, -1.25), (-0.8, -1.35)],
        "body_top": 0.5,
        "cabin_bottom": [(-0.62, -1.0), (0.62, -1.0), (0.62, 0.2), (-0.62, 0.2)],
        "cabin_top": [(-0.5, -0.85), (0.5, -0.85), (0.5, -0.25), (-0.5, -0.25)],
        "cabin_z": 0.84,
        "wheels": (0.78, 0.95),
    },
    # Ровный скруглённый прямоугольник (как player-base-002): фургон.
    "base2": {
        "body": [(-0.6, -1.5), (0.6, -1.5), (0.8, -1.3), (0.8, 1.3),
                 (0.6, 1.5), (-0.6, 1.5), (-0.8, 1.3), (-0.8, -1.3)],
        "body_top": 0.6,
        "cabin_bottom": [(-0.74, -1.4), (0.74, -1.4), (0.74, 0.8), (-0.74, 0.8)],
        "cabin_top": [(-0.7, -1.36), (0.7, -1.36), (0.7, 0.5), (-0.7, 0.5)],
        "cabin_z": 1.3,
        "wheels": (0.83, 0.95),
    },
}


def bounds(outline):
    xs = [p[0] for p in outline]
    ys = [p[1] for p in outline]
    return [min(xs), max(xs), min(ys), max(ys)]


def letters_rows(atlas, arts):
    """Буквы всего атласа по строкам ('.' — пусто), в том же порядке, что пиксели."""
    rows = [["."] * atlas.width for _ in range(atlas.height)]
    for name, art in arts.items():
        _x, top, _w, _h = atlas.pixel_rects[name]
        for y, line in enumerate(art):
            for x, ch in enumerate(line):
                rows[top + y][x] = ch
    return ["".join(r) for r in rows]


def write_json(name, atlas, arts, areas):
    data = {
        "atlas": [atlas.width, atlas.height],
        "rects": {k: list(v) for k, v in atlas.pixel_rects.items()},
        "letters": letters_rows(atlas, arts),
        "palette": {k: v for k, v in PALETTE.items() if k != "."},
        "roles": ROLES,
        # Верхние грани (x: лево -> право, y: зад -> перед, м) — для рисунка скина.
        "areas": areas,
    }
    path = common.project_path("assets", "models", "cars", name + ".json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
    print("saved:", path)


def build_atlas(name, arts):
    atlas = common.Atlas(32)
    for seed, (region, art) in enumerate(arts.items(), start=1):
        atlas.add(region, common.pixels_from_ascii(art, PALETTE, noise=0.04, seed=seed))
    image, rects = atlas.build("car_" + name)
    material = common.make_pixel_material("car_" + name, image, roughness=0.6)
    return atlas, rects, material


def build_base(name, spec):
    common.reset_scene()
    arts = {
        "body_top": BODY_TOP, "body_side": BODY_SIDE, "body_front": BODY_FRONT,
        "body_back": BODY_BACK, "glass": GLASS, "cabin_side": CABIN_SIDE, "roof": ROOF,
        "tire": TIRE, "rim": RIM, "underside": UNDERSIDE,
    }
    atlas, rects, material = build_atlas(name, arts)

    def body_rect(kind, _normal):
        return rects[{
            "top": "body_top", "bottom": "underside", "front": "body_front",
            "back": "body_back", "side": "body_side",
        }[kind]]

    def cabin_rect(kind, _normal):
        return rects[{
            "top": "roof", "bottom": "underside", "front": "glass",
            "back": "glass", "side": "cabin_side",
        }[kind]]

    def wheel_rect(kind, _normal):
        # Торцы колеса смотрят вдоль X — это «side».
        return rects["rim" if kind == "side" else "tire"]

    common.add_prism("Body", spec["body"], spec["body"], BODY_BOTTOM, spec["body_top"], material, body_rect)
    common.add_prism("Cabin", spec["cabin_bottom"], spec["cabin_top"], spec["body_top"], spec["cabin_z"],
                     material, cabin_rect)
    wx, wy = spec["wheels"]
    for wheel, x, y in (
        ("Wheel_FL", -wx, wy),
        ("Wheel_FR", wx, wy),
        ("Wheel_RL", -wx, -wy),
        ("Wheel_RR", wx, -wy),
    ):
        common.add_cylinder_x(wheel, WHEEL_RADIUS, WHEEL_WIDTH, (x, y, WHEEL_RADIUS), material, wheel_rect)

    common.export_glb(os.path.join("assets", "models", "cars", "car_%s.glb" % name))
    write_json("car_" + name, atlas, arts, {
        "body_top": bounds(spec["body"]),
        "roof": bounds(spec["cabin_top"]),
    })


def build_tank():
    """Танк (секретный кузов): корпус, гусеницы по бокам, башня со стволом. Колёс нет."""
    common.reset_scene()
    arts = {
        "tank_top": TANK_TOP, "tank_side": TANK_SIDE, "turret": TANK_TURRET,
        "track": TRACK, "barrel": BARREL, "underside": UNDERSIDE,
    }
    atlas, rects, material = build_atlas("tank", arts)

    def hull_rect(kind, _normal):
        return rects["underside" if kind == "bottom" else "tank_top" if kind == "top" else "tank_side"]

    def track_rect(kind, _normal):
        return rects["underside" if kind == "bottom" else "track"]

    def turret_rect(kind, _normal):
        return rects["turret" if kind == "top" else "tank_side"]

    def barrel_rect(_kind, _normal):
        return rects["barrel"]

    hull = [(-0.75, -1.6), (0.75, -1.6), (0.75, 1.4), (0.55, 1.65), (-0.55, 1.65), (-0.75, 1.4)]
    common.add_prism("Hull", hull, hull, 0.25, 0.75, material, hull_rect)
    for side in (-1.0, 1.0):
        common.add_box("Track%s" % ("L" if side < 0 else "R"), (0.4, 3.5, 0.6), (side * 0.95, 0.0, 0.3),
                       material, track_rect)
    turret_bottom = [(-0.55, -0.7), (0.55, -0.7), (0.62, -0.2), (0.55, 0.4), (-0.55, 0.4), (-0.62, -0.2)]
    turret_top = [(-0.45, -0.6), (0.45, -0.6), (0.5, -0.2), (0.45, 0.3), (-0.45, 0.3), (-0.5, -0.2)]
    common.add_prism("Turret", turret_bottom, turret_top, 0.75, 1.15, material, turret_rect)
    common.add_box("Barrel", (0.18, 1.5, 0.18), (0.0, 1.1, 0.97), material, barrel_rect)

    common.export_glb(os.path.join("assets", "models", "cars", "car_tank.glb"))
    write_json("car_tank", atlas, arts, {
        "tank_top": bounds(hull),
        "turret": bounds(turret_top),
    })


for _name, _spec in BASES.items():
    build_base(_name, _spec)
build_tank()
