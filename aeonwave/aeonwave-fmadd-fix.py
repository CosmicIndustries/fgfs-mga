#!/usr/bin/env python3
"""Fixes AeonWave's NEON _batch_fmadd (src/software/cpu/arch2d_neon_template.c) in a COPY of the tree:
  1. constant volume: samples were multiplied by vstep (~0) instead of the volume v, so every sound below
     full volume (all of FlightGear's positioned sounds) was mixed in silent;
  2. changing volume: the start ramp was v + i*vstep*vstep (vstep squared) instead of v + i*vstep;
  3. changing volume: the second 4 samples of each 8 used the first 4's volumes.
Usage: aeonwave-fmadd-fix.py TREE"""
import os, sys
p = os.path.join(sys.argv[1], "src/software/cpu/arch2d_neon_template.c")
s = open(p).read()

a1 = """         float32x4_t tv;

         tv = vdupq_n_f32(vstep);
"""
assert s.count(a1) == 1, "constant-volume anchor"
s = s.replace(a1, """         float32x4_t tv;

         tv = vdupq_n_f32(v);             /* the volume; was vstep, which is ~0 here: silence */
""")

a2 = """         float32x4_t dv, tv, dvstep;

         dvstep = vld1q_f32(fact);
         dvstep = vmulq_f32(dvstep, vdupq_n_f32(vstep));

         dv = vdupq_n_f32(vstep*step);
         tv = vmlaq_f32(vdupq_n_f32(v), dvstep, vdupq_n_f32(vstep));
"""
assert s.count(a2) == 1, "ramp anchor"
s = s.replace(a2, """         float32x4_t dv, tv, tv2, dvstep;

         dvstep = vld1q_f32(fact);
         dvstep = vmulq_f32(dvstep, vdupq_n_f32(vstep));

         dv = vdupq_n_f32(vstep*step);
         tv = vaddq_f32(vdupq_n_f32(v), dvstep);          /* v + i*vstep (was v + i*vstep*vstep) */
         tv2 = vaddq_f32(tv, vdupq_n_f32(4.0f*vstep));     /* volumes for samples 4..7 */
""")

a3 = """            xtmp2 = vmulq_f32(tv, vld1q_f32((const float*)&xsptr[1]));
"""
assert s.count(a3) == 1, "second-half anchor"
s = s.replace(a3, """            xtmp2 = vmulq_f32(tv2, vld1q_f32((const float*)&xsptr[1]));
""")
a4 = """            tv = vaddq_f32(tv, dv);

            xsptr += 2;
"""
assert s.count(a4) == 1, "ramp step anchor"
s = s.replace(a4, """            tv = vaddq_f32(tv, dv);
            tv2 = vaddq_f32(tv2, dv);

            xsptr += 2;
""")
open(p, "w").write(s)
print("patched", p)
