"""Перевод игры (Lang, scripts/core/lang.gd).

  python tools/i18n.py wrap     — обернуть русские строки в коде в Lang.t("…") (один раз; повторный запуск ничего не меняет)
  python tools/i18n.py extract  — собрать все русские строки (код + data/game_data.json) в data/i18n/en.json:
                                  новые ключи получают пустой перевод, пропавшие из игры удаляются; печатает, сколько без перевода
  python tools/i18n.py missing  — вывести ключи без перевода (JSON) — их нужно перевести и вписать в en.json

Ключ перевода — сама русская строка (как в игре после разбора экранирования \\n, \\"). Строки форматирования
("ВОЛНА %d") переводятся целиком, с теми же %d/%s в том же порядке.
Не оборачиваются: комментарии, print/push_error/push_warning, строки в const (их переводит Ctx.fill_text и
автоперевод надписей Godot), ключи словарей, &"StringName", ^"NodePath", строки в тройных кавычках.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CYR = re.compile("[А-Яа-яЁё]")
SKIP_CALLS = ("print(", "print_debug(", "printerr(", "push_error(", "push_warning(", "prints(")
EN = ROOT / "data" / "i18n" / "en.json"


def unescape(s):
    out = []
    i = 0
    while i < len(s):
        c = s[i]
        if c == "\\" and i + 1 < len(s):
            n = s[i + 1]
            out.append({"n": "\n", "t": "\t", "r": "\r", '"': '"', "'": "'", "\\": "\\"}.get(n, "\\" + n))
            i += 2
            continue
        out.append(c)
        i += 1
    return "".join(out)


def scan(src):
    """Лексер GDScript: список строковых литералов {start, end, quote, body, wrap(bool), why}"""
    lits = []
    i = 0
    n = len(src)
    depth = 0
    stmt_kind = ""        # первое слово оператора (const / var / ...), пока скобки не закрыты
    line_start = True
    while i < n:
        c = src[i]
        if line_start:
            j = i
            while j < n and src[j] in " \t":
                j += 1
            if depth == 0:
                m = re.match(r"(static\s+)?(const|var|func|match|print|prints|printerr|print_debug|push_error|push_warning)\b", src[j:j + 20])
                stmt_kind = m.group(2) if m else ""
                if stmt_kind.startswith(("print", "push_")):
                    stmt_kind = "print"
            line_start = False
        if c == "\n":
            line_start = True
            i += 1
            continue
        if c == "#":
            while i < n and src[i] != "\n":
                i += 1
            continue
        if src.startswith('"""', i) or src.startswith("'''", i):
            q = src[i:i + 3]
            e = src.find(q, i + 3)
            i = e + 3
            continue
        if c in "\"'":
            prefix = src[i - 1] if i > 0 else ""
            j = i + 1
            while j < n and src[j] != c:
                if src[j] == "\\":
                    j += 1
                j += 1
            body = src[i + 1:j]
            if CYR.search(body):
                ls = src.rfind("\n", 0, i) + 1
                le = src.find("\n", j)
                line = src[ls:le if le >= 0 else n]
                after = src[j + 1:j + 40].lstrip(" \t")
                before = src[max(0, i - 8):i]
                why = ""
                if prefix in "&^r" and prefix != "":
                    why = "prefix"
                elif stmt_kind == "print" or any(k in line for k in SKIP_CALLS):
                    why = "print"
                elif stmt_kind == "const":
                    why = "const"
                elif after.startswith(":") and not after.startswith(":="):
                    why = "key"
                elif before.endswith("Lang.t("):
                    why = "done"
                lits.append({"start": i, "end": j + 1, "q": c, "body": body, "why": why})
            i = j + 1
            continue
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth = max(0, depth - 1)
        i += 1
    return lits


def gd_files():
    return sorted(p for p in (ROOT / "scripts").rglob("*.gd"))


def cmd_wrap():
    total = 0
    for p in gd_files():
        src = p.read_text(encoding="utf-8")
        lits = scan(src)
        todo = [l for l in lits if l["why"] == ""]
        for l in lits:
            if l["why"] == "key":
                ln = src.count("\n", 0, l["start"]) + 1
                print(f"  ключ словаря, оставлен: {p.relative_to(ROOT)}:{ln} {l['body'][:40]}")
        if not todo:
            continue
        out = src
        for l in reversed(todo):
            out = out[:l["start"]] + "Lang.t(" + out[l["start"]:l["end"]] + ")" + out[l["end"]:]
        p.write_text(out, encoding="utf-8", newline="\n")
        print(f"{p.relative_to(ROOT)}: {len(todo)}")
        total += len(todo)
    print("обёрнуто строк:", total)


def walk_data(x, out):
    if isinstance(x, str):
        if CYR.search(x):
            out.append(x)
    elif isinstance(x, dict):
        for v in x.values():
            walk_data(v, out)
    elif isinstance(x, list):
        for v in x:
            walk_data(v, out)


def all_keys():
    keys = []
    for p in gd_files():
        for l in scan(p.read_text(encoding="utf-8")):
            if l["why"] in ("print", "prefix"):
                continue
            keys.append(unescape(l["body"]))
    data = json.loads((ROOT / "data" / "game_data.json").read_text(encoding="utf-8"))
    walk_data(data, keys)
    # названия стилей музыки (настройки)
    audio = json.loads((ROOT / "assets" / "audio" / "audio.json").read_text(encoding="utf-8"))
    walk_data([v.get("name", "") for v in audio.get("music", {}).values()], keys)
    seen = {}
    for k in keys:
        seen.setdefault(k, True)
    return list(seen)


def load_en():
    if EN.exists():
        return json.loads(EN.read_text(encoding="utf-8"))
    return {}


def save_en(d):
    EN.parent.mkdir(parents=True, exist_ok=True)
    EN.write_text(json.dumps(d, ensure_ascii=False, indent=1) + "\n", encoding="utf-8", newline="\n")


def cmd_extract():
    keys = all_keys()
    old = load_en()
    new = {k: old.get(k, "") for k in keys}
    gone = [k for k in old if k not in new]
    save_en(new)
    miss = sum(1 for v in new.values() if v == "")
    print(f"ключей {len(new)}, без перевода {miss}, удалено устаревших {len(gone)}")


def cmd_missing():
    d = load_en()
    miss = {k: "" for k, v in d.items() if v == ""}
    sys.stdout.reconfigure(encoding="utf-8")
    print(json.dumps(miss, ensure_ascii=False, indent=1))


def cmd_merge(path):
    """влить готовые переводы из JSON-файла {ru: en} в en.json"""
    add = json.loads(Path(path).read_text(encoding="utf-8"))
    d = load_en()
    bad = [k for k in add if k not in d]
    for k, v in add.items():
        if k in d:
            d[k] = v
    save_en(d)
    print(f"влито {len(add) - len(bad)}, неизвестных ключей {len(bad)}")
    for k in bad[:20]:
        print("  нет ключа:", k[:60])


def cmd_check():
    """переводы сохраняют %d/%s/{…} и переносы строк"""
    d = load_en()
    ph = re.compile(r"%[-+0-9.]*[dsfxX%]|\{[a-zA-Z_0-9]*\}")
    bad = 0
    for k, v in d.items():
        if v == "":
            continue
        if sorted(ph.findall(k)) != sorted(ph.findall(v)):
            print("заполнители:", repr(k[:60]), "→", repr(v[:60]))
            bad += 1
        if CYR.search(v) and v != k:
            print("кириллица в переводе:", repr(v[:60]))
            bad += 1
    print("проблем:", bad)


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "wrap":
        cmd_wrap()
    elif cmd == "extract":
        cmd_extract()
    elif cmd == "missing":
        cmd_missing()
    elif cmd == "merge":
        cmd_merge(sys.argv[2])
    elif cmd == "check":
        cmd_check()
    else:
        print(__doc__)
