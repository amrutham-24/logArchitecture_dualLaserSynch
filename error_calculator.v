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

    // Signed Q5.12 error outputs
    output reg  signed [17:0] dbg_err_q12,
    output reg  signed [17:0] dbg_ep_q12,
    output reg                err_valid
);

    // Target log-power: approximately 23.3561 in Q12
    localparam signed [17:0] TARGET_LOG_Q12 = 18'sd95666;

    wire signed [32:0] bias_delta_q16;
    wire signed [34:0] sensitivity_product;
    wire signed [34:0] compensation_q12;

    wire signed [17:0] measured_log_extended;
    wire signed [17:0] err_comb;

    // Full-width compensated error before saturation
    wire signed [35:0] ep_full;
    wire signed [17:0] ep_comb;
    wire                  ep_overflow;

    // Difference between current and delayed bias
    assign bias_delta_q16 =
        $signed({bias_log_q16[31], bias_log_q16}) -
        $signed({bias_hist_log_q16[31],
                 bias_hist_log_q16});

    // Effective sensitivity = 1.5
    // Bias delta is Q16.16.
    // Multiply by 3 and shift right by 5:
    // (delta * 1.5) converted from Q16.16 to Q12.
    assign sensitivity_product =
        $signed(bias_delta_q16) * 35'sd3;

    assign compensation_q12 =
        sensitivity_product >>> 5;

    // Extend measured log-power to signed arithmetic
    assign measured_log_extended =
        $signed({1'b0, log_power_q12});

    // Positive error means measured power is below target
    assign err_comb =
        TARGET_LOG_Q12 - measured_log_extended;

    // Subtract using full compensation precision
    assign ep_full =
        {{18{err_comb[17]}}, err_comb} -
        {{1{compensation_q12[34]}}, compensation_q12};

    // Detect values outside the signed 18-bit range
    assign ep_overflow =
        (ep_full > 36'sd131071) ||
        (ep_full < -36'sd131072);

    // Saturate rather than wrap on overflow
    assign ep_comb =
        ep_overflow ?
            (ep_full[35] ? -18'sd131072 : 18'sd131071) :
            ep_full[17:0];

    // Register outputs when a valid measurement arrives
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
