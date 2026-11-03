// =============================================================================
// rs_ssec_decoder_base.v  -  paper baseline decoder (reproduction of Fig. 4)
//
//   r(x) -> syndrome S1,S2 -> 17-way comparison (L) -> magnitude -> c(x)
//
// The combinational path (syndrome + core) sits between an input and an output
// register so its delay is the reported "path delay", as in the paper's
// non-pipelined comparison. NPOS = 17, USE_CSE = 0 are the paper's settings.
// =============================================================================
`timescale 1ns / 1ps
module rs_ssec_decoder_base #(
    parameter NPOS    = 17,
    parameter USE_CSE = 0
)(
    input  wire         clk,
    input  wire         rst_n,
    input  wire         in_valid,
    input  wire [303:0] in_cw,
    output reg          out_valid,
    output reg  [271:0] out_data,
    output reg  [303:0] out_cw,
    output reg  [4:0]   out_err_pos,
    output reg          out_no_error,
    output reg          out_corrected,      // data or parity symbol corrected
    output reg          out_uncorrectable
);
    reg         v_r;
    reg [303:0] cw_r;
    always @(posedge clk) begin
        if (!rst_n) begin v_r <= 1'b0; cw_r <= 304'd0; end
        else begin v_r <= in_valid; if (in_valid) cw_r <= in_cw; end
    end

    wire [15:0]  s1, s2;
    wire [303:0] c_cw;
    wire [18:0]  loc;
    wire [15:0]  mag;
    wire [4:0]   pos;
    wire         ne, dc, pc, ue;

    rs_syndrome u_syn (.cw(cw_r), .s1(s1), .s2(s2));
    rs_ssec_core #(.NPOS(NPOS), .USE_CSE(USE_CSE)) u_core (
        .r_cw(cw_r), .s1(s1), .s2(s2), .c_cw(c_cw), .loc(loc), .err_mag(mag),
        .err_pos(pos), .no_error(ne), .data_corrected(dc), .parity_corrected(pc),
        .uncorrectable(ue));

    always @(posedge clk) begin
        if (!rst_n) begin
            out_valid <= 1'b0; out_data <= 272'd0; out_cw <= 304'd0; out_err_pos <= 5'd31;
            out_no_error <= 1'b0; out_corrected <= 1'b0; out_uncorrectable <= 1'b0;
        end else begin
            out_valid <= v_r;
            if (v_r) begin
                out_cw            <= c_cw;
                out_data          <= c_cw[271:0];
                out_err_pos       <= pos;
                out_no_error      <= ne;
                out_corrected     <= dc | pc;
                out_uncorrectable <= ue;
            end
        end
    end
endmodule
