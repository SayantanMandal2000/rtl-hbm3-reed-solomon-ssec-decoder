// =============================================================================
// gf16_functions.vh  -  GF(2^16) helper functions (include inside a module)
//
// Field  : GF(2^16), primitive polynomial p(x) = x^16 + x^12 + x^3 + x + 1
//          (0x1100B). alpha = x = 16'h0002.
// Usage  : gf16_mul(a, b)       general multiplication (combinational logic,
//                               or folded to an XOR network when b is constant)
//          gf16_alpha_pow(e)    alpha^e, e in 0..65534 (elaboration-time constant)
//          gf16_inv(a)          a^(2^16 - 2)            (elaboration-time constant)
// All loops are bounded by 16/32 iterations so Vivado's loop limit is never hit.
// =============================================================================
localparam [16:0] GF16_POLY = 17'h1100B;

function [15:0] gf16_mul;
    input [15:0] a;
    input [15:0] b;
    reg   [15:0] p, aa;
    integer k;
    begin
        p  = 16'd0;
        aa = a;
        for (k = 0; k < 16; k = k + 1) begin
            if (b[k]) p = p ^ aa;
            aa = aa[15] ? ((aa << 1) ^ GF16_POLY[15:0]) : (aa << 1);
        end
        gf16_mul = p;
    end
endfunction

// alpha^e by square-and-multiply (e taken modulo 2^16-1 by the caller)
function [15:0] gf16_alpha_pow;
    input integer e;
    reg   [15:0] r, base;
    integer k, ee;
    begin
        ee   = e % 65535;
        if (ee < 0) ee = ee + 65535;
        r    = 16'd1;
        base = 16'd2;
        for (k = 0; k < 16; k = k + 1) begin
            if (ee & (1 << k)) r = gf16_mul(r, base);
            base = gf16_mul(base, base);
        end
        gf16_alpha_pow = r;
    end
endfunction

// multiplicative inverse a^(65534) by square-and-multiply
function [15:0] gf16_inv;
    input [15:0] a;
    reg   [15:0] r, base;
    integer k;
    begin
        r    = 16'd1;
        base = a;
        for (k = 0; k < 16; k = k + 1) begin
            if (k != 0) r = gf16_mul(r, base);   // 65534 = 0xFFFE : bits 1..15 set
            base = gf16_mul(base, base);
        end
        gf16_inv = r;
    end
endfunction
