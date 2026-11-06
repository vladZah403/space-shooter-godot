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

# автозагрузка → файл в scripts/game/: перенесённый модуль подключается сам, остальные — заглушки
MODULES = {"Game": "game", "E": "enemies", "B": "bosses", "Foes": "foes", "Sectors": "sectors", "Skills": "skills",
           "Comp": "companion", "RunMap": "map", "Events": "events", "Scenes": "scenes", "Intro": "intro", "Bg": "bg",
           "M": "store", "A": "audio", "Haptic": "haptic", "Bus": "bus", "Ui": "ui", "Main": "main", "Hud": "hud"}
code = "\n".join(p.read_text(encoding="utf-8") for p in (src / "scripts").rglob("*.gd"))
stubdir = out / "scripts" / "_stubs"
stubdir.mkdir(parents=True)
autoload = []
RET = {"top_inset": "120.0", "bottomInset": "20.0", "topInset": "120.0"}
for name, stem in MODULES.items():
    if (out / "scripts" / "game" / f"{stem}.gd").exists():
        autoload.append(f'{name}="*res://scripts/game/{stem}.gd"')
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
