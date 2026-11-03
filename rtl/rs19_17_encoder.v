// =============================================================================
// rs19_17_encoder.v  -  systematic RS(19,17) encoder, 16-bit symbols (HBM3)
//
// codeword symbol i = bits [16*i+15 : 16*i]
//   i = 0..16 : data symbols   (data[271:0] copied unchanged)
//   i = 17,18 : parity symbols
// Generator roots a and a^2, i.e. c(a) = c(a^2) = 0:
//   A = sum d_i a^i ,  B = sum d_i a^(2i)
//   p17 = A*c1 + B*c2 ,  p18 = A*c3 + B*c4      (c1..c4 elaboration-time constants)
// Fully combinational; all multiplications are by constants (XOR networks).
// =============================================================================
`timescale 1ns / 1ps
module rs19_17_encoder (
    input  wire [271:0] data,
    output wire [303:0] codeword
);
    `include "gf16_functions.vh"

    localparam [15:0] DET  = gf16_alpha_pow(53) ^ gf16_alpha_pow(52);
    localparam [15:0] DINV = gf16_inv(DET);
    localparam [15:0] C1   = gf16_mul(gf16_alpha_pow(36), DINV);
    localparam [15:0] C2   = gf16_mul(gf16_alpha_pow(18), DINV);
    localparam [15:0] C3   = gf16_mul(gf16_alpha_pow(34), DINV);
    localparam [15:0] C4   = gf16_mul(gf16_alpha_pow(17), DINV);

    reg [15:0] A, B;
    integer i;
    always @(*) begin
        A = 16'd0; B = 16'd0;
        for (i = 0; i < 17; i = i + 1) begin
            A = A ^ gf16_mul(data[16*i +: 16], gf16_alpha_pow(i));
            B = B ^ gf16_mul(data[16*i +: 16], gf16_alpha_pow(2 * i));
        end
    end

    wire [15:0] p17 = gf16_mul(A, C1) ^ gf16_mul(B, C2);
    wire [15:0] p18 = gf16_mul(A, C3) ^ gf16_mul(B, C4);

    assign codeword = {p18, p17, data};
endmodule
