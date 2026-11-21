#!/usr/bin/env python3
"""Third part of the WAV LIST fix (run after aeonwave-wavlist-fix2.py), in a COPY of the AeonWave tree: a LIST chunk
that isn't INFO (adtl cue labels, as Awave/GoldWave write) was read as if it held exactly one entry, so any further
labels were then misread as top-level chunks and the 'data' size came out wrong: heap-buffer-overflow again
(FlightGear's own Sounds/engstart.wav). It now skips the whole chunk, using its own size.
Usage: aeonwave-wavlist-fix3.py TREE"""
import os, sys
p = os.path.join(sys.argv[1], "src/stream/ext_wav.c")
s = open(p).read()
start = "      else if (curr == 0x6c746461)         /* adtl */\n      {\n"
end = "      handle->io.read.size -= rv;\n      break;\n   }\n   case 0x6c706d73: // smpl\n"
i = s.index(start)
j = s.index(end, i)
assert s.count(start) == 1 and s.count(end) == 1, "anchors"
new = """      else if (!init_tag)
      {  /* adtl or another LIST type: none of it is needed, skip the whole chunk by its own size */
         size_t total = handle->io.read.blockbufpos;       /* the LIST chunk's own size */
         if (total >= sizeof(int32_t) && total - sizeof(int32_t) <= bufsize)
         {
            *step = rv = 2*sizeof(int32_t) + EVEN(total); /* "LIST", size, then the whole chunk */
         }
         else                                              /* more than is in the buffer now */
         {
            *step = 0;
            rv = __F_NEED_MORE;
         }
         handle->io.read.blockbufpos = 0;
      }
"""
s = s[:i] + new + s[j:]
open(p, "w").write(s)
print("patched", p)
