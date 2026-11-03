// =============================================================================
// rs_ssec_robust_decoder.v  -  modified decoder: Mod 1 + Mod 2 + Mod 3
//
//   Original : RS(19,17) decoder -> error correction -> output
//   Enhanced : RS decoder -> GF optimisation (Mod 1, USE_CSE) -> error correction
//              -> fault checking (Mod 2) -> re-decode if fault (Mod 3)
//              -> verified output
//
// Modification 2 - syndrome-based checker after correction
//   The syndromes S1', S2' of the corrected codeword are recomputed and compared
//   with what the decoder claimed:
//     claimed no-error / corrected  ->  S1' = S2' = 0 must hold
//     claimed uncorrectable         ->  S1', S2' must stay non-zero
//                                      (no correction was applied)
//   Any mismatch is a decoder fault (fault_detected). Checking consistency, not
//   only S' = 0, also catches a fault that makes a clean word look uncorrectable.
//
// Modification 3 - recovery by re-decoding
//   On a detected fault the temporary decoder state (syndrome and correction
//   registers) is cleared and the buffered codeword is decoded again; the result
//   is output only if the second attempt is consistent and correctable.
//   A word reported uncorrectable is also re-decoded once, so a transient fault
//   cannot turn a correctable word into a false "uncorrectable".
//   Final status:
//     verified          : output passed the check (data can be used)
//     recovered         : 1st attempt failed or was uncorrectable, 2nd passed
//     uncorrectable     : genuine multi-symbol error (consistent on both tries)
//     recovery_fail     : fault still present on the 2nd attempt (permanent)
//
// Pipeline / FSM (one codeword in flight):
//   IDLE --in_valid--> SYN (S1,S2 -> syn_r) --> COR (correction -> cor_r)
//        --> CHK (S1',S2' of cor_r) --ok--> output
//                     --fault or uncorrectable, attempt 0--> CLR --> SYN (retry)
//                     --attempt 1--> output with final status
//   Latency: 4 clocks normally, 8 clocks with one re-decode.
//
// Fault-injection test ports (tie to 0 in a product):
//   inj_en / inj_mask : XOR inj_mask into the syndrome register when it is
//                       written (models an SEU in decoder state)
//   inj_persistent    : 0 = only on the first attempt (transient fault)
//                       1 = on every attempt           (permanent fault)
// =============================================================================
`timescale 1ns / 1ps
module rs_ssec_robust_decoder #(
    parameter USE_CSE      = 1,      // Modification 1
    parameter ENABLE_CHECK = 1,      // Modification 2
    parameter ENABLE_RETRY = 1       // Modification 3
)(
    input  wire         clk,
    input  wire         rst_n,
    // input
    input  wire         in_valid,
    output wire         in_ready,
    input  wire [303:0] in_cw,
    // output
    output reg          out_valid,
    output reg  [271:0] out_data,
    output reg  [303:0] out_cw,
    output reg  [4:0]   out_err_pos,      // 0..16 data, 17..18 parity, 31 none
    output reg          out_no_error,
    output reg          out_data_corrected,
    output reg          out_parity_corrected,
    output reg          out_uncorrectable, // genuine multi-symbol error
    output reg          out_fault_detected,// Mod 2: an inconsistent result was seen
    output reg          out_recovered,     // Mod 3: re-decode produced a good result
    output reg          out_recovery_fail, // Mod 3: still inconsistent after re-decode
    output reg          out_verified,      // output passed the check, data usable
    // fault injection (test only)
    input  wire         inj_en,
    input  wire [31:0]  inj_mask,
    input  wire         inj_persistent,
    // statistics
    output reg  [31:0]  cnt_words,
    output reg  [31:0]  cnt_faults,         // words with a detected decoder fault
    output reg  [31:0]  cnt_recovered
);
    localparam S_IDLE = 3'd0, S_SYN = 3'd1, S_COR = 3'd2, S_CHK = 3'd3, S_CLR = 3'd4;
    reg [2:0]   state;
    reg         attempt;
    reg         fault_seen;             // a check failed on the 1st attempt
    reg         first_bad;              // 1st attempt was re-decoded
    reg [303:0] buf_cw;                 // input buffer kept for re-decoding

    assign in_ready = (state == S_IDLE);

    // ---------------------------------------------------- stage 1: syndrome
    wire [15:0] s1_c, s2_c;
    rs_syndrome u_syn (.cw(buf_cw), .s1(s1_c), .s2(s2_c));
    reg  [31:0] syn_r;                  // {S2, S1}
    wire inj_now = inj_en & (inj_persistent | ~attempt);

    // ---------------------------------------------------- stage 2: correction
    wire [303:0] c_cw;
    wire [18:0]  loc;
    wire [15:0]  mag;
    wire [4:0]   pos;
    wire         ne, dc, pc, ue;
    rs_ssec_core #(.NPOS(19), .USE_CSE(USE_CSE)) u_core (
        .r_cw(buf_cw), .s1(syn_r[15:0]), .s2(syn_r[31:16]), .c_cw(c_cw), .loc(loc),
        .err_mag(mag), .err_pos(pos), .no_error(ne), .data_corrected(dc),
        .parity_corrected(pc), .uncorrectable(ue));
    reg [303:0] cor_r;
    reg [4:0]   pos_r;
    reg         ne_r, dc_r, pc_r, ue_r;

    // ---------------------------------------------------- stage 3: checker (Mod 2)
    wire [15:0] cs1, cs2;
    rs_syndrome u_chk (.cw(cor_r), .s1(cs1), .s2(cs2));
    wire s_prime_zero = ~|{cs1, cs2};
    // consistency between the decoder's claim and the recomputed syndrome
    wire consistent   = (ENABLE_CHECK == 0) ? 1'b1 : (ue_r ? ~s_prime_zero : s_prime_zero);
    wire final_ok     = consistent & ~ue_r;   // data may be used
    wire need_retry   = (ENABLE_RETRY != 0) && !attempt && (!consistent || ue_r);

    // ---------------------------------------------------- control
    always @(posedge clk) begin
        if (!rst_n) begin
            state <= S_IDLE; attempt <= 1'b0; fault_seen <= 1'b0; first_bad <= 1'b0;
            buf_cw <= 304'd0; syn_r <= 32'd0; cor_r <= 304'd0; pos_r <= 5'd31;
            {ne_r, dc_r, pc_r, ue_r} <= 4'b0;
            out_valid <= 1'b0; out_data <= 272'd0; out_cw <= 304'd0; out_err_pos <= 5'd31;
            {out_no_error, out_data_corrected, out_parity_corrected, out_uncorrectable} <= 4'b0;
            {out_fault_detected, out_recovered, out_recovery_fail, out_verified} <= 4'b0;
            cnt_words <= 32'd0; cnt_faults <= 32'd0; cnt_recovered <= 32'd0;
        end else begin
            out_valid <= 1'b0;
            case (state)
            S_IDLE: begin
                if (in_valid) begin
                    buf_cw <= in_cw; attempt <= 1'b0; fault_seen <= 1'b0; first_bad <= 1'b0;
                    state <= S_SYN;
                end
            end
            S_SYN: begin
                syn_r <= {s2_c, s1_c} ^ (inj_now ? inj_mask : 32'd0);
                state <= S_COR;
            end
            S_COR: begin
                cor_r <= c_cw; pos_r <= pos;
                {ne_r, dc_r, pc_r, ue_r} <= {ne, dc, pc, ue};
                state <= S_CHK;
            end
            S_CHK: begin
                if (need_retry) begin
                    // Mod 3: fault (or suspicious uncorrectable) -> clear and re-decode
                    fault_seen <= ~consistent;
                    first_bad  <= 1'b1;
                    attempt    <= 1'b1;
                    if (!consistent) cnt_faults <= cnt_faults + 1'b1;
                    state      <= S_CLR;
                end else begin
                    out_valid            <= 1'b1;
                    out_cw               <= cor_r;
                    out_data             <= cor_r[271:0];
                    out_err_pos          <= pos_r;
                    out_no_error         <= ne_r;
                    out_data_corrected   <= dc_r;
                    out_parity_corrected <= pc_r;
                    out_uncorrectable    <= ue_r & consistent;
                    out_verified         <= final_ok;
                    out_fault_detected   <= fault_seen | ~consistent;
                    out_recovered        <= first_bad & final_ok;
                    out_recovery_fail    <= ~consistent;
                    cnt_words            <= cnt_words + 1'b1;
                    if (first_bad & final_ok) cnt_recovered <= cnt_recovered + 1'b1;
                    state <= S_IDLE;
                end
            end
            S_CLR: begin
                syn_r <= 32'd0; cor_r <= 304'd0; pos_r <= 5'd31;
                {ne_r, dc_r, pc_r, ue_r} <= 4'b0;
                state <= S_SYN;
            end
            default: state <= S_IDLE;
            endcase
        end
    end
endmodule
