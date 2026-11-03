// =============================================================================
// rs_hbm_ecc_top.v  -  top module: HBM3 on-die ECC path with RS(19,17) SSEC
//
//   write path : wr_data (272 b) --encoder--> wr_cw (304 b)  -> to DRAM array
//   read path  : rd_cw (304 b from DRAM) --robust SSEC decoder--> rd_data (272 b)
//
// The read path uses the modified decoder (Mod 1 CSE constant-GF bank, Mod 2
// post-correction syndrome check, Mod 3 re-decode recovery). Fault-injection
// ports are exposed for verification; tie them to 0 in a product.
// =============================================================================
`timescale 1ns / 1ps
module rs_hbm_ecc_top #(
    parameter USE_CSE      = 1,
    parameter ENABLE_CHECK = 1,
    parameter ENABLE_RETRY = 1
)(
    input  wire         clk,
    input  wire         rst_n,
    // write path (registered encoder)
    input  wire         wr_valid,
    input  wire [271:0] wr_data,
    output reg          wr_cw_valid,
    output reg  [303:0] wr_cw,
    // read path
    input  wire         rd_valid,
    output wire         rd_ready,
    input  wire [303:0] rd_cw,
    output wire         rd_out_valid,
    output wire [271:0] rd_data,
    output wire [303:0] rd_corrected_cw,
    output wire [4:0]   rd_err_pos,
    output wire         rd_no_error,
    output wire         rd_data_corrected,
    output wire         rd_parity_corrected,
    output wire         rd_uncorrectable,
    output wire         rd_fault_detected,
    output wire         rd_recovered,
    output wire         rd_recovery_fail,
    output wire         rd_verified,
    // fault injection (test only)
    input  wire         inj_en,
    input  wire [31:0]  inj_mask,
    input  wire         inj_persistent,
    // statistics
    output wire [31:0]  cnt_words,
    output wire [31:0]  cnt_faults,
    output wire [31:0]  cnt_recovered
);
    // ---------------- write path
    wire [303:0] enc_cw;
    rs19_17_encoder u_enc (.data(wr_data), .codeword(enc_cw));
    always @(posedge clk) begin
        if (!rst_n) begin wr_cw_valid <= 1'b0; wr_cw <= 304'd0; end
        else begin
            wr_cw_valid <= wr_valid;
            if (wr_valid) wr_cw <= enc_cw;
        end
    end

    // ---------------- read path
    rs_ssec_robust_decoder #(.USE_CSE(USE_CSE), .ENABLE_CHECK(ENABLE_CHECK),
                             .ENABLE_RETRY(ENABLE_RETRY)) u_dec (
        .clk(clk), .rst_n(rst_n),
        .in_valid(rd_valid), .in_ready(rd_ready), .in_cw(rd_cw),
        .out_valid(rd_out_valid), .out_data(rd_data), .out_cw(rd_corrected_cw),
        .out_err_pos(rd_err_pos), .out_no_error(rd_no_error),
        .out_data_corrected(rd_data_corrected), .out_parity_corrected(rd_parity_corrected),
        .out_uncorrectable(rd_uncorrectable), .out_fault_detected(rd_fault_detected),
        .out_recovered(rd_recovered), .out_recovery_fail(rd_recovery_fail),
        .out_verified(rd_verified),
        .inj_en(inj_en), .inj_mask(inj_mask), .inj_persistent(inj_persistent),
        .cnt_words(cnt_words), .cnt_faults(cnt_faults), .cnt_recovered(cnt_recovered));
endmodule
