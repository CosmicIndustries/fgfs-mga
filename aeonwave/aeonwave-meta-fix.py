#!/usr/bin/env python3
"""Fixes a double free in AeonWave (src/aax_buffer.c) in a COPY of the tree: when a buffer is read from a file, it
kept the stream's tag strings (artist, title, date...) as its own, but they belong to the file reader, which frees
them on close; the buffer then freed them again. Any WAV with text tags (a LIST/INFO chunk, as ffmpeg writes)
corrupted the heap: "free(): corrupted unsorted chunks" in FlightGear. The buffer now keeps copies.
Usage: aeonwave-meta-fix.py TREE"""
import os, re, sys
p = os.path.join(sys.argv[1], "src/aax_buffer.c")
s = open(p).read()
pat = re.compile(r"(handle->meta\.\w+ = )stream->name\(id, (\w+)\);")
n = len(pat.findall(s))
assert n >= 12, "expected the 13 meta lines, found %d" % n
s = pat.sub(r"\1_aax_buf_dupname(stream->name(id, \2));", s)
helper = ("\n/* the stream owns the strings it names; keep our own copies (freed with the buffer's meta) */\n"
          "static char *_aax_buf_dupname(const char *s) { return s ? strdup(s) : NULL; }\n")
# put the helper after the last #include
last = [m.end() for m in re.finditer(r"^#include [^\n]+\n", s, re.M)][-1]
s = s[:last] + helper + s[last:]
if "#include <string.h>" not in s:
    s = "#include <string.h>\n" + s
open(p, "w").write(s)
print("patched %d lines in %s" % (n, p))
