`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 14.10.2026 01:32:53
// Design Name: 
// Module Name: laser_bias_ctrl
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

module laser_bias_ctrl #(
    parameter integer SAMPLE_W = 16,
    parameter integer WIN_LOG2 = 12,
    parameter integer S_MIN = 1,
    parameter integer S_MAX = 5,
    parameter integer S_INIT = 1,
    parameter integer CALM_COUNT = 12,
    parameter integer ADAPT = 1
)(
    input  wire                    clk,
    input  wire                    rst,

    input  wire signed [SAMPLE_W-1:0] s_data,
    input  wire                    s_valid,

    // Linear bias, unsigned Q5.11
    output wire [15:0]              bias_q11,
    output reg                     bias_valid,

    // Status:
    // 0 = hold, 1 = step, 2 = saturated,
    // 3 = no signal, 4 = error outside guard
    output reg [2:0]               status,

    // Debug outputs
    output wire [31:0]             dbg_mean,
    output wire [16:0]             dbg_lp_q12,
    output wire signed [17:0]      dbg_err_q12,
    output wire signed [17:0]      dbg_ep_q12,
    output wire [2:0]              dbg_shift,
    output reg                     dbg_flip,
    output wire signed [31:0]      dbg_l_q16
);

    localparam [2:0] STATUS_HOLD = 3'd0;
    localparam [2:0] STATUS_STEP = 3'd1;
    localparam [2:0] STATUS_SAT  = 3'd2;
    localparam [2:0] STATUS_NOSIG = 3'd3;
    localparam [2:0] STATUS_RANGE = 3'd4;

    localparam signed [31:0] BIAS_MIN_Q16 = 32'sd152170; // log2(5), Q16.16
    localparam signed [31:0] BIAS_MAX_Q16 = 32'sd315055; // log2(28), Q16.16

// Default initial bias = 5. Override to match MATLAB's generator bias.
    parameter signed [31:0] BIAS_INIT_Q16 = 32'sd152170;
    // ---------------------------------------------------------
    // 1. Power estimator
    // ---------------------------------------------------------

    wire power_valid;

    power_estimator #(
        .SAMPLE_W(SAMPLE_W),
        .WIN_LOG2(WIN_LOG2)
    ) u_power_estimator (
        .clk(clk),
        .rst(rst),
        .s_data(s_data),
        .s_valid(s_valid),
        .power_valid(power_valid),
        .mean_square(dbg_mean)
    );

    // ---------------------------------------------------------
    // 2. Log-power estimator
    // ---------------------------------------------------------

    wire log_valid_raw;
    wire [16:0] log_power_raw;

    log_power_estimator u_log_power_estimator (
        .clk(clk),
        .rst(rst),
        .mean_square(dbg_mean),
        .power_valid(power_valid),
        .log_power_q12(log_power_raw),
        .log_valid(log_valid_raw)
    );

    // Zero power is not a valid logarithmic measurement.
    wire log_valid_safe;

    assign log_valid_safe =
        log_valid_raw && (dbg_mean != 32'd0);

    assign dbg_lp_q12 = log_power_raw;

    // ---------------------------------------------------------
    // 3. Current bias and one-pass history
    // ---------------------------------------------------------

    reg signed [31:0] bias_log_current_q16;
    reg signed [31:0] bias_log_history_q16;

    // The controller initializes its output to BIAS_MIN_Q16.
    // The top-level bias state must use the same initial value.
    always @(posedge clk) begin
        if (rst) begin
    bias_log_current_q16 <= BIAS_INIT_Q16;
    bias_log_history_q16 <= BIAS_INIT_Q16;
    bias_valid            <= 1'b0;
    end
        else begin
            // Delay the controller's update pulse so it aligns
            // with the updated top-level bias state.
            bias_valid <= ctrl_bias_valid;

            if (ctrl_bias_valid) begin
                bias_log_history_q16 <= bias_log_current_q16;
                bias_log_current_q16 <= ctrl_bias_next_q16;
            end
        end
    end

    assign dbg_l_q16 = bias_log_current_q16;

    // ---------------------------------------------------------
    // 4. Error calculation and delay compensation
    // ---------------------------------------------------------

    wire err_valid;

    error_calculator u_error_calculator (
        .clk(clk),
        .rst(rst),
        .log_power_q12(log_power_raw),
        .log_valid(log_valid_safe),
        .bias_log_q16(bias_log_current_q16),
        .bias_hist_log_q16(bias_log_history_q16),
        .dbg_err_q12(dbg_err_q12),
        .dbg_ep_q12(dbg_ep_q12),
        .err_valid(err_valid)
    );

    // ---------------------------------------------------------
    // 5. Adaptive bias controller
    // ---------------------------------------------------------

    wire signed [31:0] ctrl_bias_next_q16;
    wire ctrl_bias_valid;
    wire [4:0] calm_count_unused;

    adaptive_bias_controller #(
        .S_MIN(S_MIN),
        .S_MAX(S_MAX),
        .S_INIT(S_INIT),
        .CALM_COUNT(CALM_COUNT),
        .ADAPT(ADAPT)
    ) u_adaptive_bias_controller (
        .clk(clk),
        .rst(rst),
        .err_q12(dbg_err_q12),
        .ep_q12(dbg_ep_q12),
        .err_valid(err_valid),
        .bias_log_q16(bias_log_current_q16),
        .bias_log_next_q16(ctrl_bias_next_q16),
        .bias_valid(ctrl_bias_valid),
        .gain_s(dbg_shift),
        .calm_count(calm_count_unused)
    );

    // ---------------------------------------------------------
    // 6. Debug sign-flip detection
    // ---------------------------------------------------------

    reg prev_ep_sign;
    reg prev_ep_sign_valid;

    wire signed [18:0] err_ext;
    wire signed [18:0] ep_ext;
    wire signed [18:0] abs_err;
    wire signed [18:0] abs_ep;

    assign err_ext = {dbg_err_q12[17], dbg_err_q12};
    assign ep_ext  = {dbg_ep_q12[17], dbg_ep_q12};

    assign abs_err = err_ext[18] ? -err_ext : err_ext;
    assign abs_ep  = ep_ext[18]  ? -ep_ext  : ep_ext;

    wire debug_update_eligible;

    assign debug_update_eligible =
        err_valid &&
        (abs_err < 19'sd40820) &&
        (abs_ep > 19'sd163);

    always @(posedge clk) begin
        if (rst) begin
            prev_ep_sign       <= 1'b0;
            prev_ep_sign_valid <= 1'b0;
            dbg_flip           <= 1'b0;
        end
        else begin
            dbg_flip <= 1'b0;

            if (debug_update_eligible) begin
                if ((ADAPT != 0) &&
                    prev_ep_sign_valid &&
                    (dbg_ep_q12[17] != prev_ep_sign))
                    dbg_flip <= 1'b1;

                prev_ep_sign       <= dbg_ep_q12[17];
                prev_ep_sign_valid <= 1'b1;
            end
        end
    end

    // ---------------------------------------------------------
    // 7. Convert log2 bias Q16.16 to linear bias Q5.11
    //    using a 32-segment antilog LUT.
    // ---------------------------------------------------------

    function [12:0] exp2_fraction_lut;
        input [4:0] index;
        begin
            case (index)
                0:  exp2_fraction_lut = 13'd2048;
                1:  exp2_fraction_lut = 13'd2093;
                2:  exp2_fraction_lut = 13'd2139;
                3:  exp2_fraction_lut = 13'd2186;
                4:  exp2_fraction_lut = 13'd2233;
                5:  exp2_fraction_lut = 13'd2282;
                6:  exp2_fraction_lut = 13'd2332;
                7:  exp2_fraction_lut = 13'd2383;
                8:  exp2_fraction_lut = 13'd2435;
                9:  exp2_fraction_lut = 13'd2489;
                10: exp2_fraction_lut = 13'd2543;
                11: exp2_fraction_lut = 13'd2599;
                12: exp2_fraction_lut = 13'd2656;
                13: exp2_fraction_lut = 13'd2714;
                14: exp2_fraction_lut = 13'd2774;
                15: exp2_fraction_lut = 13'd2834;
                16: exp2_fraction_lut = 13'd2896;
                17: exp2_fraction_lut = 13'd2960;
                18: exp2_fraction_lut = 13'd3025;
                19: exp2_fraction_lut = 13'd3091;
                20: exp2_fraction_lut = 13'd3158;
                21: exp2_fraction_lut = 13'd3228;
                22: exp2_fraction_lut = 13'd3298;
                23: exp2_fraction_lut = 13'd3371;
                24: exp2_fraction_lut = 13'd3444;
                25: exp2_fraction_lut = 13'd3520;
                26: exp2_fraction_lut = 13'd3597;
                27: exp2_fraction_lut = 13'd3676;
                28: exp2_fraction_lut = 13'd3756;
                29: exp2_fraction_lut = 13'd3838;
                30: exp2_fraction_lut = 13'd3922;
                31: exp2_fraction_lut = 13'd4008;
                default: exp2_fraction_lut = 13'd2048;
            endcase
        end
    endfunction

    function [15:0] log_bias_to_q11;
        input signed [31:0] log_value;

        integer integer_part;
        reg [4:0] index;
        reg [10:0] remainder;
        reg [12:0] lut_a;
        reg [12:0] lut_b;
        reg [25:0] interp_product;
        reg [15:0] fractional_value;

        begin
            integer_part = $signed(log_value) >>> 16;
            index = log_value[15:11];
            remainder = log_value[10:0];

            lut_a = exp2_fraction_lut(index);
            lut_b = exp2_fraction_lut(index + 5'd1);

            // Linear interpolation in Q5.11.
            interp_product =
                lut_a * (13'd2048 - {2'b00, remainder}) +
                lut_b * remainder;

            fractional_value = interp_product >> 11;

            if (integer_part >= 0) begin
                if (integer_part >= 16)
                    log_bias_to_q11 = 16'hffff;
                else if (({16'd0, fractional_value} << integer_part) > 32'd65535)
                    log_bias_to_q11 = 16'hffff;
                else
                    log_bias_to_q11 = fractional_value << integer_part;
            end
            else begin
                log_bias_to_q11 = fractional_value >> (-integer_part);
            end
        end
    endfunction

    assign bias_q11 = log_bias_to_q11(bias_log_current_q16);

    // ---------------------------------------------------------
    // 8. Status reporting
    // ---------------------------------------------------------

    always @(posedge clk) begin
    if (rst) begin
        status <= STATUS_HOLD;
    end
    else begin
        if (power_valid && (dbg_mean == 32'd0)) begin
            status <= STATUS_NOSIG;
        end
        else if (err_valid) begin
            if (abs_err >= 19'sd40820) begin
                status <= STATUS_RANGE;
            end
            else if (abs_ep <= 19'sd163) begin
                status <= STATUS_HOLD;
            end
            else begin
                status <= STATUS_STEP;
            end
        end

        // Match MATLAB's directional saturation condition.
        if (ctrl_bias_valid && (dbg_ep_q12 != 18'sd0)) begin
            if ((ctrl_bias_next_q16 == BIAS_MIN_Q16 &&
                 dbg_ep_q12[17]) ||
                (ctrl_bias_next_q16 == BIAS_MAX_Q16 &&
                 !dbg_ep_q12[17])) begin
                status <= STATUS_SAT;
            end
        end
    end
end

endmodule

