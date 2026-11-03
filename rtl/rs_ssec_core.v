// =============================================================================
// rs_ssec_core.v  -  inverse-free SSEC error location + magnitude + correction
//
// Kwon et al., "A Hardware-Efficient Reed-Solomon Decoding Architecture for
// Single-Symbol Error Correcting in HBM", IEEE TVLSI 2026.
//
//  Error location (paper Eq. 3, Fig. 5):   S2 = X1 * S1
//     l_i = NOR( S2 xor (S1 * a^i) )          for each candidate position i
//     -> one-hot error-location vector L, no GF inverse needed
//  Error magnitude (paper Eq. 4, Fig. 6):  E1 = S1 * X1^-1
//     e_i = l_i ? S1 * a^-i : 0               constant multiplications only
//  Correction:  c_i = r_i xor e_i
//
// Parameters
//   NPOS    = 17 : paper baseline - only the 17 data positions are searched
//                  (2*17 = 34 constants, paper Table I)
//           = 19 : project extension - the 2 parity positions are also located,
//                  so a parity-symbol error is reported (and corrected) instead
//                  of being flagged uncorrectable; needed for the Modification-2
//                  post-correction syndrome check to be exact.
//   USE_CSE = 0  : paper mapping - every constant product is its own XOR network
//           = 1  : Modification 1 - all 2*NPOS products of S1 come from one shared
//                  common-subexpression-eliminated XOR network (gf16_cmul_bank_cse)
// Fully combinational (the paper compares non-pipelined designs).
// =============================================================================
`timescale 1ns / 1ps
module rs_ssec_core #(
    parameter NPOS    = 17,
    parameter USE_CSE = 0
)(
    input  wire [303:0] r_cw,          // received codeword
    input  wire [15:0]  s1,
    input  wire [15:0]  s2,
    output wire [303:0] c_cw,          // corrected codeword
    output wire [18:0]  loc,           // one-hot error-location vector L
    output wire [15:0]  err_mag,       // E1 of the located error (0 if none)
    output reg  [4:0]   err_pos,       // 0..18, 31 = none
    output wire         no_error,      // S1 = S2 = 0
    output wire         data_corrected,
    output wire         parity_corrected,
    output wire         uncorrectable  // syndrome != 0 but no single-symbol match
);
    `include "gf16_functions.vh"

    // ------------------------------------------------- constant products of S1
    wire [16*19-1:0] p_loc;            // S1 * a^i
    wire [16*19-1:0] p_mag;            // S1 * a^-i
    genvar g;
    generate
        if (USE_CSE != 0) begin : g_cse
            wire [16*38-1:0] bank;
            gf16_cmul_bank_cse u_bank (.s1(s1), .prod(bank));
            assign p_loc = bank[16*19-1:0];
            assign p_mag = bank[16*38-1:16*19];
        end else begin : g_paper
            for (g = 0; g < 19; g = g + 1) begin : g_c
                localparam [15:0] AL  = gf16_alpha_pow(g);
                localparam [15:0] ALI = gf16_alpha_pow(65535 - g);
                assign p_loc[16*g +: 16] = gf16_mul(s1, AL);
                assign p_mag[16*g +: 16] = gf16_mul(s1, ALI);
            end
        end
    endgenerate

    // ------------------------------------------------- error-location vector L
    wire s_zero = ~|{s1, s2};
    generate
        for (g = 0; g < 19; g = g + 1) begin : g_loc
            if (g < NPOS) begin : g_on
                // NOR of (S2 xor S1*a^i); S1 = 0 can never be a valid single error
                assign loc[g] = ~|(s2 ^ p_loc[16*g +: 16]) & (|s1);
            end else begin : g_off
                assign loc[g] = 1'b0;
            end
        end
    endgenerate

    // ------------------------------------------------- error vector + correction
    wire [303:0] e_vec;
    generate
        for (g = 0; g < 19; g = g + 1) begin : g_err
            assign e_vec[16*g +: 16] = {16{loc[g]}} & p_mag[16*g +: 16];
        end
    endgenerate
    assign c_cw = r_cw ^ e_vec;

    // magnitude of the located error (OR of the one-hot gated magnitudes)
    reg [15:0] mag_or;
    integer k;
    always @(*) begin
        mag_or  = 16'd0;
        err_pos = 5'd31;
        for (k = 0; k < 19; k = k + 1) begin
            mag_or = mag_or | e_vec[16*k +: 16];
            if (loc[k]) err_pos = k[4:0];
        end
    end
    assign err_mag = mag_or;

    wire hit_data   = |loc[16:0];
    wire hit_parity = |loc[18:17];
    assign no_error         = s_zero;
    assign data_corrected   = hit_data;
    assign parity_corrected = hit_parity;
    assign uncorrectable    = ~s_zero & ~hit_data & ~hit_parity;
endmodule
