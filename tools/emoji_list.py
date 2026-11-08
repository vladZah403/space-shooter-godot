"""Список эмодзи из текстов игры → data/emoji.json (для цветных иконок в браузере, scripts/ui/web_emoji.gd).

Запуск из папки проекта: python tools/emoji_list.py
Перезапускать, когда в тексты (scripts/**/*.gd, data/game_data.json) добавили новый значок.
Каждый символ записывается так, как он стоит в тексте: если где-то есть «X» + U+FE0F (эмодзи-вид) —
с FE0F, иначе без. Два списка: color — эмодзи (цветные картинки), text — значки, которые по Юникоду рисуются
цветом текста (▶ ★ ● ◆ без FE0F). Какие эмодзи браузер действительно нарисует цветными, решает игра при запуске.
"""
import glob
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VS16 = "️"


def wanted(cp: int) -> bool:
    # стрелки, техзнаки, геометрия, символы, дингбаты, эмодзи; без типографики и рамок
    if 0x2190 <= cp <= 0x21FF or 0x2300 <= cp <= 0x23FF or 0x25A0 <= cp <= 0x27BF or 0x2B00 <= cp <= 0x2BFF:
        return True
    return cp in (0x203C, 0x2049, 0x2122, 0x2139, 0x3030, 0x303D) or cp >= 0x1F000


# символы до U+1F000, которые по Юникоду сами по себе — картинка-эмодзи (Emoji_Presentation=Yes).
# Остальные (▶ ★ ● ← ✓ …) без U+FE0F — обычные значки цветом текста: их рисует контурный Noto Emoji
EMOJI_BMP = {0x231A, 0x231B, 0x23E9, 0x23EA, 0x23EB, 0x23EC, 0x23F0, 0x23F3, 0x25FD, 0x25FE, 0x2614, 0x2615,
             *range(0x2648, 0x2654), 0x267F, 0x2693, 0x26A1, 0x26AA, 0x26AB, 0x26BD, 0x26BE, 0x26C4, 0x26C5, 0x26CE,
             0x26D4, 0x26EA, 0x26F2, 0x26F3, 0x26F5, 0x26FA, 0x26FD, 0x2705, 0x270A, 0x270B, 0x2728, 0x274C, 0x274E,
             0x2753, 0x2754, 0x2755, 0x2757, 0x2795, 0x2796, 0x2797, 0x27B0, 0x27BF, 0x2B1B, 0x2B1C, 0x2B50, 0x2B55}


def colored(cp: int, vs: bool) -> bool:
    return vs or cp >= 0x1F000 or cp in EMOJI_BMP


def _strings(v) -> list:
    if isinstance(v, str):
        return [v]
    if isinstance(v, dict):
        return [s for k, x in v.items() for s in _strings(k) + _strings(x)]
    if isinstance(v, list):
        return [s for x in v for s in _strings(x)]
    return []


def main() -> None:
    files = glob.glob(os.path.join(ROOT, "scripts", "**", "*.gd"), recursive=True)
    files += [os.path.join(ROOT, "data", "game_data.json")]
    found: dict[int, bool] = {}
    for p in files:
        text = open(p, encoding="utf-8").read()
        if p.endswith(".json"):
            text = "\n".join(_strings(json.loads(text)))  # в JSON эмодзи могут быть записаны escape-кодами
        for i, ch in enumerate(text):
            cp = ord(ch)
            if not wanted(cp):
                continue
            vs = i + 1 < len(text) and text[i + 1] == VS16
            found[cp] = found.get(cp, False) or vs
    items = {"color": [], "text": []}
    for cp, vs in sorted(found.items()):
        items["color" if colored(cp, vs) else "text"].append(chr(cp) + (VS16 if vs else ""))
    out = os.path.join(ROOT, "data", "emoji.json")
    with open(out, "w", encoding="utf-8", newline="\n") as f:
        json.dump(items, f, ensure_ascii=False)
        f.write("\n")
    print(f"{len(items['color'])} emoji + {len(items['text'])} symbols -> data/emoji.json")


if __name__ == "__main__":
    main()
