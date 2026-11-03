"""GF(2^16) arithmetic and RS(19,17) SSEC golden model (HBM3 configuration).

Field   : GF(2^16), primitive polynomial p(x) = x^16 + x^12 + x^3 + x + 1  (0x1100B)
Code    : RS(19,17), 16-bit symbols, generator g(x) = (x + a)(x + a^2)
Layout  : symbol i (i = 0..18) is the coefficient of x^i
          i = 0..16  -> data symbols  (272 data bits)
          i = 17,18  -> parity symbols (32 parity bits)
          codeword bits [16*i+15 : 16*i] hold symbol i  (304 bits total)
Syndromes: S1 = r(a),  S2 = r(a^2).   Single error E at position i:
          S1 = E*a^i, S2 = E*a^(2i)  ->  X1 = a^i = S2/S1,  E1 = S1 * a^(-i)   (paper Eq. 1-4)
"""
POLY = 0x1100B
M = 16
Q = 1 << M
N, K = 19, 17

def gmul(a, b):
    r = 0
    while b:
        if b & 1:
            r ^= a
        b >>= 1
        a <<= 1
        if a & Q:
            a ^= POLY
    return r

EXP = [0] * (2 * Q)
LOG = [0] * Q
x = 1
for i in range(Q - 1):
    EXP[i] = x
    LOG[x] = i
    x = gmul(x, 2)
assert x == 1, "polynomial is not primitive"
for i in range(Q - 1, 2 * Q):
    EXP[i] = EXP[i - (Q - 1)]
# primitivity: the order of alpha must be exactly 2^16-1
assert len(set(EXP[:Q - 1])) == Q - 1

def apow(e):
    return EXP[e % (Q - 1)]

def ginv(a):
    assert a
    return EXP[(Q - 1 - LOG[a]) % (Q - 1)]

def syndromes(cw):
    s1 = s2 = 0
    for i, s in enumerate(cw):
        s1 ^= gmul(s, apow(i))
        s2 ^= gmul(s, apow(2 * i))
    return s1, s2

# parity solve: p17*a^17 + p18*a^18 = A ; p17*a^34 + p18*a^36 = B
DET = apow(53) ^ apow(52)
DI = ginv(DET)
C_P17_A, C_P17_B = gmul(apow(36), DI), gmul(apow(18), DI)
C_P18_A, C_P18_B = gmul(apow(34), DI), gmul(apow(17), DI)

def encode(data):
    assert len(data) == K
    A = B = 0
    for i, d in enumerate(data):
        A ^= gmul(d, apow(i))
        B ^= gmul(d, apow(2 * i))
    p17 = gmul(A, C_P17_A) ^ gmul(B, C_P17_B)
    p18 = gmul(A, C_P18_A) ^ gmul(B, C_P18_B)
    cw = list(data) + [p17, p18]
    assert syndromes(cw) == (0, 0)
    return cw

def decode(cw, npos=19):
    """Returns (corrected_cw, status, pos) with status in
    'none' | 'data' | 'parity' | 'uncorrectable'."""
    s1, s2 = syndromes(cw)
    if s1 == 0 and s2 == 0:
        return list(cw), "none", 31
    for i in range(npos):                    # 0..16 data, 17..18 parity
        if s1 and gmul(s1, apow(i)) == s2:
            e = gmul(s1, apow(-i))
            out = list(cw); out[i] ^= e
            return out, ("data" if i < K else "parity"), i
    return list(cw), "uncorrectable", 31

def pack(cw):
    v = 0
    for i, s in enumerate(cw):
        v |= s << (16 * i)
    return v

def const_matrix(c):
    """16x16 GF(2) matrix of y = x*c : row r = set of input bits feeding output bit r."""
    rows = [set() for _ in range(M)]
    for j in range(M):
        p = gmul(1 << j, c)
        for r in range(M):
            if (p >> r) & 1:
                rows[r].add(j)
    return rows

if __name__ == "__main__":
    print("alpha^16 =", hex(apow(16)), " det =", hex(DET))
    print("parity constants", [hex(v) for v in (C_P17_A, C_P17_B, C_P18_A, C_P18_B)])
