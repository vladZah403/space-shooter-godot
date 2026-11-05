"""Проверочная копия Godot-проекта: недостающие автозагрузки заменяются заглушками,
чтобы Godot мог разобрать и проверить типы уже перенесённых скриптов.
Использование: python mkcheck.py <project_dir> <out_dir>"""
import re, shutil, sys
from pathlib import Path

src, out = Path(sys.argv[1]), Path(sys.argv[2])
if out.exists():
    shutil.rmtree(out)
for d in ("scripts", "data", "assets"):
    if (src / d).exists():
        shutil.copytree(src / d, out / d, ignore=shutil.ignore_patterns("*.import"))
shutil.copy(src / "project.godot", out / "project.godot")
# прототип (scripts/*.gd) заменяется портом; его class_name Hud мешает заглушке
for p in [out / "scripts" / f"{n}.gd" for n in ("boss", "bullet", "enemy", "fx_sprite", "hud", "player", "main", "starfield")]:
    p.unlink()

REAL = {"Game": "res://scripts/game/game.gd", "E": "res://scripts/game/enemies.gd", "B": "res://scripts/game/bosses.gd"}
STUBS = ["Foes", "Skills", "Comp", "RunMap", "Events", "Scenes", "Intro", "Bg", "M", "A", "Haptic", "Bus", "Ui", "Main", "Hud"]
code = "\n".join(p.read_text(encoding="utf-8") for p in (src / "scripts").rglob("*.gd"))
stubdir = out / "scripts" / "_stubs"
stubdir.mkdir(parents=True)
autoload = []
RET = {"top_inset": "120.0", "bottomInset": "20.0", "topInset": "120.0"}
for name, path in REAL.items():
    if (out / path[6:]).exists():
        autoload.append(f'{name}="*{path}"')
for name in STUBS:
    if (out / "scripts" / "game" / f"{name.lower()}.gd").exists():
        continue
    meth, prop = set(), set()
    for m in re.finditer(rf"\b{name}\.([A-Za-z_]\w*)\s*(\()?", code):
        (meth if m.group(2) else prop).add(m.group(1))
    lines = ["extends Node", "## заглушка для проверки типов"]
    for p in sorted(prop - meth):
        lines.append(f"var {p}" + (" = 2" if p == "quality" else ""))
    for f in sorted(meth):
        lines.append(f"func {f}(_a = null, _b = null, _c = null, _d = null, _e = null, _f = null, _g = null) -> Variant:\n\treturn " + RET.get(f, "null"))
    (stubdir / f"{name}.gd").write_text("\n".join(lines) + "\n", encoding="utf-8")
    autoload.append(f'{name}="*res://scripts/_stubs/{name}.gd"')

pg = (out / "project.godot").read_text(encoding="utf-8")
pg = re.sub(r"(\[autoload\]\n\n(?:.*\n)*?)(\n\[)", lambda m: m.group(1) + "\n".join(autoload) + "\n" + m.group(2), pg, count=1)
(out / "project.godot").write_text(pg, encoding="utf-8")
print("autoloads:", ", ".join(a.split("=")[0] for a in autoload))
