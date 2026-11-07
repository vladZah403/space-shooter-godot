"""Спрайты, нарисованные уже для Godot-версии (их нет в атласах JS): листы Влада из art/ → атласы в assets/
и кадры в data/extra_frames.json (G подмешивает их к кадрам JS-атласов).

Запуск из папки проекта: python tools/extra_sprites.py
  art/medals.png (4×3) → assets/medals.png, кадры ach_<группа>: kills, boss, combo, score, wave, hard, survive,
                          aim, evo, arsenal, fleet, pilot — порядок по строкам, как на листе (M.ACH_MEDAL)
  art/debris.png (3×2) → assets/debris.png, кадры db_1…db_6: обшивка, балка, солнечная панель, спутник,
                          бочка, антенна (враг «Обломок», событие «Космический мусор»)
Фон листов прозрачный; полупрозрачная дымка вокруг рисунков (альфа < 24) срезается. В art/ лежит .gdignore —
исходники в игру не попадают.
"""
import json
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MEDALS = ["kills", "boss", "combo", "score", "wave", "hard", "survive", "aim", "evo", "arsenal", "fleet", "pilot"]
SHEETS = [
    # исходник, атлас, столбцов, строк, ячейка атласа, имена кадров, индекс листа в G
    ("medals.png", "medals.png", 4, 3, 128, ["ach_" + m for m in MEDALS], 2),
    ("debris.png", "debris.png", 3, 2, 160, ["db_%d" % i for i in range(1, 7)], 3),
]


def cut(src_name, out_name, cols, rows, cell, names, sheet, frames):
    src = Image.open(os.path.join(ROOT, "art", src_name)).convert("RGBA")
    a = src.getchannel("A").point(lambda v: v if v >= 24 else 0)
    src.putalpha(a)
    w, h = src.size
    out = Image.new("RGBA", (cols * cell, rows * cell), (0, 0, 0, 0))
    for i, name in enumerate(names):
        r, c = divmod(i, cols)
        part = src.crop((c * w // cols, r * h // rows, (c + 1) * w // cols, (r + 1) * h // rows))
        box = part.getchannel("A").getbbox()
        if not box:
            raise SystemExit(f"{src_name}: пустая ячейка {r},{c}")
        m = part.crop(box)
        k = (cell - 4) / max(m.size)
        m = m.resize((max(1, round(m.size[0] * k)), max(1, round(m.size[1] * k))), Image.LANCZOS)
        x, y = c * cell + (cell - m.size[0]) // 2, r * cell + (cell - m.size[1]) // 2
        out.alpha_composite(m, (x, y))
        # значки-медали — квадратная ячейка целиком (ровно стоят в строке), обломки — по рисунку
        frames[name] = [c * cell, r * cell, cell, cell, 0, sheet] if name.startswith("ach_") else [x, y, m.size[0], m.size[1], 0, sheet]
    out.save(os.path.join(ROOT, "assets", out_name), optimize=True)
    print(f"{len(names)} -> assets/{out_name}")


def main() -> None:
    frames = {}
    for s in SHEETS:
        cut(*s, frames)
    with open(os.path.join(ROOT, "data", "extra_frames.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump({"sheets": ["res://assets/" + s[1] for s in SHEETS], "frames": frames}, f, indent=0)
        f.write("\n")
    print("data/extra_frames.json")


if __name__ == "__main__":
    main()
