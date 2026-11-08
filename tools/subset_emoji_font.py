"""Урезать контурный Noto Emoji (запасной шрифт значков, assets/fonts/NotoEmoji.ttf) до знаков, что есть в игре.

  python tools/subset_emoji_font.py

Полный шрифт лежит в tools/fonts/NotoEmoji-full.ttf (не входит в сборку). Знаки собираются из текстов игры:
scripts/**/*.gd, data/*.json, data/i18n/*.json — всё, что не латиница и не кириллица. 1.3 МБ → десятки КБ.
Перезапускать, когда в тексты добавили новый значок.
"""
import json
import re
from pathlib import Path

import sys
from fontTools import subset
from fontTools.ttLib import TTFont

sys.stdout.reconfigure(encoding="utf-8")
ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "tools" / "fonts" / "NotoEmoji-full.ttf"
DST = ROOT / "assets" / "fonts" / "NotoEmoji.ttf"

text = ""
for p in list((ROOT / "scripts").rglob("*.gd")) + list((ROOT / "data").rglob("*.json")):
    text += p.read_text(encoding="utf-8")
chars = {c for c in text if ord(c) > 0x2000 and not re.match("[А-Яа-яЁё]", c)}
font = TTFont(SRC)
cmap = font.getBestCmap()
# всё, что шрифт умеет из найденного, плюс модификаторы (вариант-селекторы, ZWJ, тона кожи, флаги)
keep = {ord(c) for c in chars if ord(c) in cmap}
keep |= {0xFE0F, 0xFE0E, 0x200D, 0x20E3} | set(range(0x1F3FB, 0x1F400)) & set(cmap)
opts = subset.Options()
opts.layout_features = ["*"]
opts.name_IDs = ["*"]
opts.notdef_outline = True
sub = subset.Subsetter(opts)
sub.populate(unicodes=sorted(keep))
sub.subset(font)
font.save(DST)
print(f"знаков в текстах: {len(chars)}, в шрифте: {len(keep)}; {SRC.stat().st_size // 1024} КБ -> {DST.stat().st_size // 1024} КБ")
