#!/usr/bin/env python3
"""check_readmes.py: every module README under src/ lists exactly the files
it covers - no file missing from its table, none named that is not there.

A README covers the files of its folder and of every subfolder without a
README of its own; its "## Files" table names them (backticked, in the first
column, relative to the README's folder). A folder with files and no README
covering it is an error too. Exits 1 on any difference."""
import os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "src")


def covered(folder):
    """the files this README covers, relative to its folder"""
    out = set()
    for d, dirs, files in os.walk(folder):
        if d != folder and os.path.exists(os.path.join(d, "README.md")):
            dirs[:] = []
            continue
        for f in files:
            if f != "README.md":
                out.add(os.path.relpath(os.path.join(d, f), folder).replace("\\", "/"))
    return out


def listed(readme):
    """the files the README's "## Files" table names"""
    text = open(readme, encoding="utf-8").read()
    m = re.search(r"^## Files\b.*?$(.*?)(?=^## |\Z)", text, re.M | re.S)
    if not m:
        return None
    names = set()
    for line in m.group(1).splitlines():
        if not line.startswith("|") or set(line) <= set("|- "):
            continue
        first = line.split("|")[1]
        names.update(n for n in re.findall(r"`([^`]+)`", first) if "." in n)
    return names


def main():
    bad = 0
    readmes = []
    for d, dirs, files in os.walk(SRC):
        dirs.sort()
        if "README.md" in files:
            readmes.append(d)
        elif files and not any(d.startswith(r + os.sep) for r in readmes):
            print("no README covers %s" % os.path.relpath(d, ROOT))
            bad += 1
    for d in readmes:
        rel = os.path.relpath(d, ROOT).replace("\\", "/")
        have = covered(d)
        names = listed(os.path.join(d, "README.md"))
        if names is None:
            if have:
                print("%s/README.md: no Files table, but it covers %s" % (rel, ", ".join(sorted(have))))
                bad += 1
            continue
        for f in sorted(have - names):
            print("%s/README.md: %s is not in its Files table" % (rel, f))
            bad += 1
        for f in sorted(names - have):
            print("%s/README.md: its Files table names %s, which is not there" % (rel, f))
            bad += 1
    print("module READMEs: %d checked, %d problem(s)" % (len(readmes), bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
