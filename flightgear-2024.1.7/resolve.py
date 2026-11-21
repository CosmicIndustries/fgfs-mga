#!/usr/bin/env python3
"""Resolve the two 2024.1.7 conflicts: start from 2024.1.7's file, re-apply the MGA changes."""
import re, subprocess, os
os.chdir(os.path.expanduser("~/builds/flightgear-2024.1.7"))
def head(path):
    return subprocess.run(["git", "show", "HEAD:" + path], capture_output=True, text=True, check=True).stdout
def mga(path):  # the MGA version on 2024.1.1
    return subprocess.run(["git", "-C", os.path.expanduser("~/builds/flightgear"), "show", ":" + path],
                          capture_output=True, text=True).stdout or open(os.path.expanduser("~/builds/flightgear/" + path)).read()

# resources.qrc: the region map in the "/" section, Training.qml in the new "/qt" section next to Summary.qml
q = head("src/GUI/resources.qrc")
a = '        <file alias="spinner">assets/spinner.gif</file>\n'
assert a in q and "mga-region-map" not in q
q = q.replace(a, a + '        <file alias="mga-region-map.svg">assets/mga-region-map.svg</file>\n', 1)
b = '        <file>qml/Summary.qml</file>\n'
assert b in q
q = q.replace(b, b + '        <file>qml/Training.qml</file>\n', 1)
open("src/GUI/resources.qrc", "w").write(q)

# Style.qml: 2024.1.7's file with the MGA colours and sizes for every property both files have
new = head("src/GUI/qml/Style.qml")
old = open(os.path.expanduser("~/builds/flightgear/src/GUI/qml/Style.qml")).read()
pat = re.compile(r'^(\s*readonly property \S+ (\w+):\s*)(.+)$', re.M)
vals = {m.group(2): m.group(3) for m in pat.finditer(old)}
changed, missing = [], []
def sub(m):
    n = m.group(2)
    if n in vals and vals[n] != m.group(3):
        changed.append(n); return m.group(1) + vals[n]
    return m.group(0)
out = pat.sub(sub, new)
have = {m.group(2) for m in pat.finditer(new)}
missing = [n for n in vals if n not in have]
if "MGA Flight Operations" not in out:
    out = out.replace("QtObject\n{\n", "QtObject\n{\n    // MGA Flight Operations visual system: black enamel, antique brass,\n    // warm instrument white and restrained signal red.\n", 1)
open("src/GUI/qml/Style.qml", "w").write(out)
print("Style.qml changed:", changed)
print("Style.qml MGA properties not in 2024.1.7:", missing)
subprocess.run(["git", "add", "src/GUI/resources.qrc", "src/GUI/qml/Style.qml"], check=True)
print(subprocess.run(["git", "status", "--short"], capture_output=True, text=True).stdout)
