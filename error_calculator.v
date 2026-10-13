`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 13.10.2026 23:20:43
// Design Name: 
// Module Name: error_calculator
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


`timescale 1ns / 1ps

module error_calculator (
    input  wire               clk,
    input  wire               rst,

    input  wire [16:0]        log_power_q12,
    input  wire               log_valid,

    // Signed Q16.16 log2 bias values
    input  wire signed [31:0] bias_log_q16,
    input  wire signed [31:0] bias_hist_log_q16,

    // Signed Q12 error outputs
    output reg  signed [17:0] dbg_err_q12,
    output reg  signed [17:0] dbg_ep_q12,
    output reg                err_valid
);

    // Simulation convention:
    // P_watts = mean_square / 2^26
    //
    // Target = log2(0.01 * 2^26) in Q12
    //         = 19.3561438 * 4096
    //         ~= 79283
    localparam signed [17:0] TARGET_LOG_Q12 = 18'sd79283;

    wire signed [32:0] bias_delta_q16;
    wire signed [34:0] sensitivity_product;
    wire signed [34:0] compensation_q12;
    wire signed [17:0] measured_log_extended;
    wire signed [17:0] err_comb;
    wire signed [35:0] ep_full;
    wire signed [17:0] ep_comb;
    wire ep_overflow;

    assign bias_delta_q16 =
        $signed({bias_log_q16[31], bias_log_q16}) -
        $signed({bias_hist_log_q16[31], bias_hist_log_q16});

    // seff = 1.5
    // Q16.16 delta * 1.5 converted to Q12
    assign sensitivity_product =
        $signed(bias_delta_q16) * 35'sd3;

    assign compensation_q12 = sensitivity_product >>> 5;

    // log_power_q12 = log2(raw integer mean_square)
    assign measured_log_extended =
        $signed({1'b0, log_power_q12});

    // Equivalent to MATLAB:
    // err = log2(0.01) - log2(P_watts)
    assign err_comb =
        TARGET_LOG_Q12 - measured_log_extended;

    // Predicted error after accounting for pending bias movement
    assign ep_full =
        {{18{err_comb[17]}}, err_comb} -
        {{1{compensation_q12[34]}}, compensation_q12};

    // Saturate to signed 18-bit range
    assign ep_overflow =
        (ep_full > 36'sd131071) ||
        (ep_full < -36'sd131072);

    assign ep_comb =
        ep_overflow ?
            (ep_full[35] ? -18'sd131072 : 18'sd131071) :
            ep_full[17:0];

    always @(posedge clk) begin
        if (rst) begin
            dbg_err_q12 <= 18'sd0;
            dbg_ep_q12  <= 18'sd0;
            err_valid   <= 1'b0;
        end
        else begin
            err_valid <= 1'b0;

            if (log_valid) begin
                dbg_err_q12 <= err_comb;
                dbg_ep_q12  <= ep_comb;
                err_valid   <= 1'b1;
            end
        end
    end

endmodule



