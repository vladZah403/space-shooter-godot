"""Векторные значки JS-версии (<symbol id="i-…"> в index.html) → data/icons.json для scripts/ui/icons.gd.

Запуск из папки проекта: python tools/svg_icons.py [путь к index.html JS-версии]
По умолчанию берёт ../space-shooter-game/index.html. Все значки там в поле 24×24.
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "..", "space-shooter-game", "index.html")


def main() -> None:
    html = open(SRC, encoding="utf-8").read()
    icons = {}
    for m in re.finditer(r'<symbol id="i-([\w-]+)" viewBox="([^"]+)">(.*?)</symbol>', html, re.S):
        if m.group(2) != "0 0 24 24":
            print("пропущен (другое поле):", m.group(1))
            continue
        icons[m.group(1)] = m.group(3).strip()
    out = os.path.join(ROOT, "data", "icons.json")
    with open(out, "w", encoding="utf-8", newline="\n") as f:
        json.dump(icons, f, ensure_ascii=False, indent=0)
        f.write("\n")
    print(f"{len(icons)} значков -> data/icons.json")


if __name__ == "__main__":
    main()
