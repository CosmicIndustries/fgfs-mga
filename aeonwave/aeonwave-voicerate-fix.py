#!/usr/bin/env python3
"""AeonWave fixes for FlightGear's ATC (Flite) voices.

1. aax_buffer.c, AAX_FREQUENCY: a buffer made with aaxBufferCreate starts with
   info.rate = MAXIMUM_CUTOFF (20000), so the old "!handle->info.rate" test was
   never true and the ring buffer stayed tagged 20000 Hz. A 48000 Hz voice then
   played 2.4x slow. Now the ring buffer follows the new rate whenever it was
   still in step with the old one.
2. C++ header aeonwave, buffer cache: the cache's deleter called aaxBufferDestroy
   and then deleted the Buffer, whose destructor destroyed the same handle again
   ("aaxBufferDestroy: Invalid or NULL handle type" at release buffer, and a read
   of freed memory). The cached Buffer now owns its handle and is destroyed once,
   and Buffer::set frees the handle it replaces instead of leaking it.

Usage: aeonwave-voicerate-fix.py <aeonwave tree or None> [header file ...]
Idempotent: a file already patched is left alone.
"""
import sys, pathlib

def patch(path, old, new, tag):
    p = pathlib.Path(path)
    s = p.read_text()
    if new in s:
        print(f"{tag}: already patched in {p}")
        return
    if s.count(old) != 1:
        sys.exit(f"{tag}: expected text not found exactly once in {p}")
    p.write_text(s.replace(old, new))
    print(f"{tag}: patched {p}")

C_OLD = """            if (rb && !handle->info.rate) {
               rb->set_paramf(rb, RB_FREQUENCY, (float)setup);
            }"""
C_NEW = """            if (rb && (!handle->info.rate ||
                       rb->get_paramf(rb, RB_FREQUENCY) == handle->info.rate)) {
               rb->set_paramf(rb, RB_FREQUENCY, (float)setup);
            }"""

H_DEL_OLD = "[](Buffer *b){ aaxBufferDestroy(*b); delete b; })),"
H_DEL_NEW = "[](Buffer *b){ delete b; })),"
H_NEW_OLD = "SharedBufferPtr buf(new Buffer(ptr, name, false, strict));"
H_NEW_NEW = "SharedBufferPtr buf(new Buffer(ptr, name, true, strict));"
H_SET_OLD = """    void set(aaxConfig c, unsigned int n, unsigned int t, enum aaxFormat f) {
        ptr = aaxBufferCreate(c, n, t, f); closefn = aaxBufferDestroy;
    }"""
H_SET_NEW = """    void set(aaxConfig c, unsigned int n, unsigned int t, enum aaxFormat f) {
        aaxBuffer old = ptr; bool owned = !!closefn;
        ptr = aaxBufferCreate(c, n, t, f); closefn = aaxBufferDestroy;
        if (old && owned && old != ptr) aaxBufferDestroy(old);
    }"""

tree = sys.argv[1] if len(sys.argv) > 1 else "None"
if tree != "None":
    patch(f"{tree}/src/aax_buffer.c", C_OLD, C_NEW, "frequency")
    patch(f"{tree}/include/aax/aeonwave", H_DEL_OLD, H_DEL_NEW, "cache-deleter")
    patch(f"{tree}/include/aax/aeonwave", H_NEW_OLD, H_NEW_NEW, "cache-owner")
    patch(f"{tree}/include/aax/aeonwave", H_SET_OLD, H_SET_NEW, "buffer-set")
for h in sys.argv[2:]:
    patch(h, H_DEL_OLD, H_DEL_NEW, "cache-deleter")
    patch(h, H_NEW_OLD, H_NEW_NEW, "cache-owner")
    patch(h, H_SET_OLD, H_SET_NEW, "buffer-set")
