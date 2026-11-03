// =============================================================================
// rs_syndrome.v  -  fully parallel syndrome calculator for RS(19,17)
//
//   S1 = r(a)   = sum_{i=0}^{18} r_i a^i
//   S2 = r(a^2) = sum_{i=0}^{18} r_i a^(2i)
// Each term is a constant GF multiplication (an XOR network); the whole block is
// one combinational XOR tree (equivalent to the unrolled Horner evaluation used
// as the common syndrome block in the paper, Sec. IV-A).
// The same module is reused by the post-correction checker (Modification 2).
// =============================================================================
`timescale 1ns / 1ps
module rs_syndrome (
    input  wire [303:0] cw,
    output reg  [15:0]  s1,
    output reg  [15:0]  s2
);
    `include "gf16_functions.vh"
    integer i;
    always @(*) begin
        s1 = 16'd0; s2 = 16'd0;
        for (i = 0; i < 19; i = i + 1) begin
            s1 = s1 ^ gf16_mul(cw[16*i +: 16], gf16_alpha_pow(i));
            s2 = s2 ^ gf16_mul(cw[16*i +: 16], gf16_alpha_pow(2 * i));
        end
    end
endmodule
