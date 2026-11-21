#!/usr/bin/env python3
"""Fixes AeonWave's WAV LIST/INFO tag parser (src/stream/ext_wav.c) in a COPY of the tree: after a tag's text it
moved on by the text length, not by the length padded to an even byte count as RIFF requires, and did not count the
text against the bytes left. An odd-length tag (like a date of 11 bytes) threw the rest of the header off and AeonWave
then corrupted the heap ("free(): corrupted unsorted chunks" in FlightGear with the PA-28's rain.wav).
Usage: aeonwave-wavlist-fix.py TREE"""
import os, sys
p = os.path.join(sys.argv[1], "src/stream/ext_wav.c")
s = open(p).read()
a = """               clen = COMMENT_SIZE;
               readstr(&ch, field, curr, &clen);
               switch(head)
"""
assert s.count(a) == 1, "LIST tag anchor"
s = s.replace(a, """               {  /* copy at most COMMENT_SIZE bytes, then skip the whole even-padded field */
                  size_t n = EVEN((size_t)curr);
                  size_t c = _MIN((size_t)curr, (size_t)COMMENT_SIZE);
                  if (n > bufsize) n = bufsize;
                  if (c > n) c = n;
                  memcpy(field, ch, c);
                  field[c] = '\\0';
                  ch += n;
                  bufsize -= n;
                  (void)clen;
               }
               switch(head)
""")
if "#include <string.h>" not in s:
    s = "#include <string.h>\n" + s
open(p, "w").write(s)
print("patched", p)
