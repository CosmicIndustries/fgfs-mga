#!/usr/bin/env python3
"""Second part of the WAV LIST/INFO fix (run after aeonwave-wavlist-fix.py), in a COPY of the AeonWave tree:
  - the bytes to parse were taken from the position in the buffer (8) instead of the LIST chunk's own size;
  - the 4-byte "INFO" id was never counted, so after the tags the reader landed 4 bytes short of the next chunk,
    misread the 'data' header and reported a near-empty sound; the buffer was sized for that and the real audio
    then overflowed it (heap-buffer-overflow in _aaxDataMove, found with AddressSanitizer);
  - an INFO sub-tag it doesn't know now gets skipped instead of ending the whole header.
Usage: aeonwave-wavlist-fix2.py TREE"""
import os, sys
p = os.path.join(sys.argv[1], "src/stream/ext_wav.c")
s = open(p).read()

a = """      *step = 0;
      if (!init_tag)
      {
         curr = read32le(&ch, &bufsize); // size
         handle->io.read.blockbufpos = curr;
         size = ch-buf;
         size = _MIN(size, bufsize);
         *step = rv = size;
      }
"""
assert s.count(a) == 1, "LIST start anchor"
s = s.replace(a, """      *step = 0;
      rv = 0;
      if (!init_tag)
      {
         curr = read32le(&ch, &bufsize); // size of the LIST chunk
         handle->io.read.blockbufpos = curr;
         *step = rv = ch-buf;                              /* "LIST" and its size */
         size = _MIN((ssize_t)curr, (ssize_t)bufsize);   /* was ch-buf: 8, not the chunk */
      }
""")

b = """      curr = read32le(&ch, &bufsize);
      if (init_tag || curr == 0x4f464e49)   /* INFO */
      {
         char field[COMMENT_SIZE+1];
"""
assert s.count(b) == 1, "INFO anchor"
s = s.replace(b, """      curr = read32le(&ch, &bufsize);
      if (init_tag || curr == 0x4f464e49)   /* INFO */
      {
         char field[COMMENT_SIZE+1];

         size -= sizeof(int32_t);                         /* the "INFO" id itself */
         rv += sizeof(int32_t);
         *step = rv;
""")

c = """            default:            // we're done
               size = 0;
               if (head != 0x61746164) {         /* data */
                  rv = __F_EOF;
               }
               break;
"""
assert s.count(c) == 1, "default anchor"
s = s.replace(c, """            default:
               if (head == 0x61746164 || size < 2*(ssize_t)sizeof(int32_t)) { /* data, or nothing left */
                  size = 0;
                  break;
               }
               /* an INFO tag we don't know: skip it rather than end the header */
               curr = read32le(&ch, &bufsize); // size
               size -= 2*sizeof(int32_t) + EVEN(curr);
               if (size < 0) break;
               rv += 2*sizeof(int32_t) + EVEN(curr);
               *step = rv;
               {
                  size_t n = EVEN((size_t)curr);
                  if (n > bufsize) n = bufsize;
                  ch += n;
                  bufsize -= n;
               }
               break;
""")
open(p, "w").write(s)
print("patched", p)
