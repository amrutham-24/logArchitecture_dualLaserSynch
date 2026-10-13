`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 13.10.2026 23:43:53
// Design Name: 
// Module Name: adaptive_bias_controller
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

module adaptive_bias_controller #(
    parameter integer S_MIN = 1,
    parameter integer S_MAX = 5,
    parameter integer S_INIT = 1,
    parameter integer CALM_COUNT = 12,
    parameter integer ADAPT = 1
)(
    input  wire                    clk,
    input  wire                    rst,

    // Signed Q12 logarithmic errors from error_calculator
    input  wire signed [17:0]      err_q12,
    input  wire signed [17:0]      ep_q12,
    input  wire                    err_valid,

    // Current log2(bias), signed Q16.16
    input  wire signed [31:0]      bias_log_q16,

    // Next log2(bias), signed Q16.16
    output reg signed [31:0]       bias_log_next_q16,
    output reg                     bias_valid,

    // Debug state
    output reg [2:0]               gain_s,
    output reg [4:0]               calm_count
);

    // Fixed-point constants derived from the MATLAB model.
    // Error inputs are in log2 units, Q12.
    localparam signed [18:0] DB_Q12        = 19'sd163;
    localparam signed [18:0] ERR_GUARD_Q12 = 19'sd40820;

    // log2(1.25), log2(5), and log2(28), in Q16.16.
    localparam signed [31:0] MAX_STEP_Q16 = 32'sd21098;
    localparam signed [31:0] BIAS_MIN_Q16 = 32'sd152170;
    localparam signed [31:0] BIAS_MAX_Q16 = 32'sd315055;

    reg prev_sign;
    reg prev_sign_valid;

    wire signed [18:0] err_extended;
    wire signed [18:0] ep_extended;
    wire signed [18:0] abs_err;
    wire signed [18:0] abs_ep;

    assign err_extended = {err_q12[17], err_q12};
    assign ep_extended  = {ep_q12[17], ep_q12};

    assign abs_err = err_extended[18]
                   ? -err_extended : err_extended;

    assign abs_ep = ep_extended[18]
                  ? -ep_extended : ep_extended;

    // MATLAB reference conditions:
// ok  = valid && abs(err_dB) < 30 dB
//     where err_dB = err_log2 * 3.0103
//
// upd = ok && abs(ep_log2) > db / 3.0103
// RTL: err and ep are signed Q12 log2 values.
// DB_Q12 and ERR_GUARD_Q12 are the corresponding Q12 thresholds.
    wire ok;
    wire upd;
    wire flip;

    assign ok  = err_valid && (abs_err < ERR_GUARD_Q12);
    assign upd = ok && (abs_ep > DB_Q12);

    // A sign flip is ignored until a previous eligible update
    // has established the previous error sign.
    assign flip = upd && (ADAPT != 0) &&
                  prev_sign_valid &&
                  (ep_q12[17] != prev_sign);

    // MATLAB updates s before computing the current dL.
    wire [5:0] calm_incremented;
    reg  [2:0] shift_for_update;

    assign calm_incremented = {1'b0, calm_count} + 6'd1;

    always @* begin
        shift_for_update = gain_s;

        if (flip) begin
            if (gain_s < S_MAX)
                shift_for_update = gain_s + 1'b1;
        end
        else if (upd && (ADAPT != 0) &&
                 (calm_incremented >= CALM_COUNT) &&
                 (gain_s > S_MIN)) begin
            shift_for_update = gain_s - 1'b1;
        end
    end

    // Convert ep from Q12 to Q16.16, then divide by 2^s.
    wire signed [31:0] ep_q16;
    wire signed [31:0] dL_unclipped;
    wire signed [31:0] dL_clipped;

    assign ep_q16 =
        {{14{ep_q12[17]}}, ep_q12} <<< 4;

    assign dL_unclipped = ep_q16 >>> shift_for_update;

    assign dL_clipped =
        (dL_unclipped > MAX_STEP_Q16)  ? MAX_STEP_Q16 :
        (dL_unclipped < -MAX_STEP_Q16) ? -MAX_STEP_Q16 :
                                         dL_unclipped;

    // Add the step in logarithmic bias space.
    wire signed [32:0] bias_sum;

    assign bias_sum =
        {bias_log_q16[31], bias_log_q16} +
        {dL_clipped[31], dL_clipped};

    wire signed [32:0] bias_min_extended;
    wire signed [32:0] bias_max_extended;

    assign bias_min_extended =
        {BIAS_MIN_Q16[31], BIAS_MIN_Q16};

    assign bias_max_extended =
        {BIAS_MAX_Q16[31], BIAS_MAX_Q16};

    always @(posedge clk) begin
        if (rst) begin
            bias_log_next_q16 <= BIAS_MIN_Q16;
            bias_valid        <= 1'b0;
            gain_s            <= S_INIT;
            calm_count        <= 5'd0;
            prev_sign         <= 1'b0;
            prev_sign_valid   <= 1'b0;
        end
        else begin
            // Default: no update pulse.
            bias_valid <= 1'b0;

            // Hold the externally supplied current bias if no
            // bias adjustment is made.
            if (!upd)
                bias_log_next_q16 <= bias_log_q16;

            if (err_valid) begin
                if (flip) begin
                    // Sign reversal: increase shift and clear calm count.
                    if (gain_s < S_MAX)
                        gain_s <= gain_s + 1'b1;

                    calm_count <= 5'd0;
                end
                else if (upd) begin
                    // MATLAB first increments q, then checks q >= calm.
                    if ((ADAPT != 0) &&
                        (calm_incremented >= CALM_COUNT) &&
                        (gain_s > S_MIN)) begin

                        gain_s     <= gain_s - 1'b1;
                        calm_count <= 5'd0;
                    end
                    else if (calm_count < 5'd31) begin
                        calm_count <= calm_count + 1'b1;
                    end
                end
                else if (ok) begin
                    // Valid measurement inside deadband:
                    // MATLAB increments q even though no update occurs.
                    if (calm_count < 5'd31)
                        calm_count <= calm_count + 1'b1;
                end

                // MATLAB: if upd, sp = sign(ep).
                if (upd) begin
                    prev_sign       <= ep_q12[17];
                    prev_sign_valid <= 1'b1;
                end

                if (upd) begin
                    // Clamp the next log-bias to log2(5)..log2(28).
                    if (bias_sum < bias_min_extended)
                        bias_log_next_q16 <= BIAS_MIN_Q16;
                    else if (bias_sum > bias_max_extended)
                        bias_log_next_q16 <= BIAS_MAX_Q16;
                    else
                        bias_log_next_q16 <= bias_sum[31:0];

                    bias_valid <= 1'b1;
                end
            end
        end
    end

endmodule
