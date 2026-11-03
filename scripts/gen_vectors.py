#!/usr/bin/env python3
"""Golden test vectors for tb_rs_core.v
Each line (hex, 1232+16 bits):  {exp17_status[3:0], exp17_pos[4:0]?...}
Layout (MSB..LSB), one hex word per line:
  [1247:1240] code17 = {status17[1:0], pos17[4:0], 1'b0}
  [1239:1232] code19 = {status19[1:0], pos19[4:0], 1'b0}
  [1231: 928] clean codeword (encoder reference)
  [ 927: 624] received codeword (with injected errors)
  [ 623: 320] expected corrected codeword, NPOS = 19 (extended decoder)
  [ 319:  16] expected corrected codeword, NPOS = 17 (paper decoder)
  [  15:   0] category id
status: 0 none, 1 data corrected, 2 parity corrected, 3 uncorrectable
"""
import random, sys
import gf16
ST = {"none": 0, "data": 1, "parity": 2, "uncorrectable": 3}
random.seed(2026)
vecs = []
def add(data, errs, cat):
    cw = gf16.encode(data); r = list(cw)
    for pos, e in errs:
        r[pos] ^= e
    c19, s19, p19 = gf16.decode(r, 19)
    c17, s17, p17 = gf16.decode(r, 17)
    code17 = (ST[s17] << 6) | (p17 << 1)
    code19 = (ST[s19] << 6) | (p19 << 1)
    v = (code17 << 1240) | (code19 << 1232) | (gf16.pack(cw) << 928) | (gf16.pack(r) << 624) \
        | (gf16.pack(c19) << 320) | (gf16.pack(c17) << 16) | cat
    vecs.append(v)
rd = lambda: [random.randrange(65536) for _ in range(17)]
for _ in range(40): add(rd(), [], 0)                                         # no error
add([0] * 17, [], 0); add([0xFFFF] * 17, [], 0)
for pos in range(19):                                                        # every position
    for e in [1, 0x8000, 0xFFFF, 0x00FF, 0xFF00] + [random.randrange(1, 65536) for _ in range(15)]:
        add(rd(), [(pos, e)], 1 if pos < 17 else 2)
for pos in range(17):                                                        # single-bit faults
    for b in range(16):
        add(rd(), [(pos, 1 << b)], 3)
for _ in range(300):                                                         # double symbol errors
    p = random.sample(range(19), 2)
    add(rd(), [(p[0], random.randrange(1, 65536)), (p[1], random.randrange(1, 65536))], 4)
for _ in range(100):                                                         # triple symbol errors
    p = random.sample(range(19), 3)
    add(rd(), [(q, random.randrange(1, 65536)) for q in p], 5)
with open(sys.argv[1] if len(sys.argv) > 1 else "rs_vectors.mem", "w") as f:
    for v in vecs:
        f.write("%0312x\n" % v)
from collections import Counter
print(len(vecs), "vectors")
