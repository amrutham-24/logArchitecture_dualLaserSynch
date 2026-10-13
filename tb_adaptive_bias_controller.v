`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 14.10.2026 00:59:18
// Design Name: 
// Module Name: tb_adaptive_bias_controller
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

module tb_adaptive_bias_controller;

    reg clk;
    reg rst;

    reg signed [17:0] err_q12;
    reg signed [17:0] ep_q12;
    reg err_valid;

    reg signed [31:0] bias_log_q16;

    wire signed [31:0] bias_log_next_q16;
    wire bias_valid;
    wire [2:0] gain_s;
    wire [4:0] calm_count;

    localparam signed [31:0] BIAS_MIN_Q16 = 32'sd152170;
    localparam signed [31:0] BIAS_MAX_Q16 = 32'sd315055;

    integer errors = 0;
    integer tests = 0;

    adaptive_bias_controller dut (
        .clk(clk),
        .rst(rst),
        .err_q12(err_q12),
        .ep_q12(ep_q12),
        .err_valid(err_valid),
        .bias_log_q16(bias_log_q16),
        .bias_log_next_q16(bias_log_next_q16),
        .bias_valid(bias_valid),
        .gain_s(gain_s),
        .calm_count(calm_count)
    );

    always #5 clk = ~clk;

    task tick;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    task check;
        input condition;
        input [8*100-1:0] message;
        begin
            tests = tests + 1;
            if (condition)
                $display("PASS: %0s", message);
            else begin
                $display("FAIL: %0s", message);
                errors = errors + 1;
            end
        end
    endtask

    task apply_inputs;
        input signed [17:0] err;
        input signed [17:0] ep;
        input valid;
        input signed [31:0] bias;
        begin
            @(negedge clk);
            err_q12 = err;
            ep_q12 = ep;
            err_valid = valid;
            bias_log_q16 = bias;
            tick;
        end
    endtask

    integer i;
    integer gain_snapshot;
    integer calm_snapshot;

    initial begin
        clk = 0;
        rst = 1;
        err_q12 = 0;
        ep_q12 = 0;
        err_valid = 0;
        bias_log_q16 = BIAS_MIN_Q16;

        $display("----------------------------------------");
        $display("Starting adaptive_bias_controller tests");
        $display("----------------------------------------");

        // Test 1: Reset initializes controller state.
        tick;
        check(gain_s == 1, "Reset initializes gain_s");
        check(calm_count == 0, "Reset clears calm_count");
        check(bias_log_next_q16 == BIAS_MIN_Q16,
              "Reset initializes output bias to minimum");

        @(negedge clk);
        rst = 0;

        // Test 2: Positive predictive error increases bias.
        apply_inputs(18'sd10000, 18'sd4096, 1'b1, BIAS_MIN_Q16);
        check(bias_valid, "Positive ep triggers bias update");
        check(bias_log_next_q16 > BIAS_MIN_Q16,
              "Positive ep increases log-bias");

        // Test 3: Negative predictive error decreases bias.
        apply_inputs(-18'sd10000, -18'sd4096, 1'b1, BIAS_MAX_Q16);
        check(bias_valid, "Negative ep triggers bias update");
        check(bias_log_next_q16 < BIAS_MAX_Q16,
              "Negative ep decreases log-bias");

        // Test 4: Error inside deadband does not update bias.
        apply_inputs(18'sd100, 18'sd100, 1'b1, BIAS_MIN_Q16);
        check(!bias_valid, "Deadband suppresses update");

        // Test 5: Invalid measurement suppresses update.
        apply_inputs(18'sd10000, 18'sd10000, 1'b0, BIAS_MIN_Q16);
        check(!bias_valid, "Invalid measurement suppresses update");

        // Test 6: Positive update remains within bias bounds.
        apply_inputs(18'sd10000, 18'sd50000, 1'b1, BIAS_MAX_Q16);
        check(bias_log_next_q16 <= BIAS_MAX_Q16,
              "Upper bias limit is enforced");

        // Test 7: Negative update remains within bias bounds.
        apply_inputs(-18'sd10000, -18'sd50000, 1'b1, BIAS_MIN_Q16);
        check(bias_log_next_q16 >= BIAS_MIN_Q16,
              "Lower bias limit is enforced");

        // Test 8: Repeated sign reversals increase gain_s.
        apply_inputs(18'sd10000, 18'sd4096, 1'b1, BIAS_MIN_Q16);
        apply_inputs(18'sd10000, -18'sd4096, 1'b1, BIAS_MIN_Q16);
        check(gain_s >= 2, "Sign reversal increases gain_s");

        // Test 9: Gain shift never exceeds S_MAX.
        for (i = 0; i < 10; i = i + 1) begin
            apply_inputs(18'sd10000, -18'sd4096, 1'b1,
                         BIAS_MIN_Q16);
            apply_inputs(18'sd10000, 18'sd4096, 1'b1,
                         BIAS_MIN_Q16);
        end
        check(gain_s <= 5, "gain_s stays within maximum");

        // Test 10: Calm counter increments during deadband.
        apply_inputs(18'sd100, 18'sd100, 1'b1, BIAS_MIN_Q16);
        check(calm_count > 0, "Calm counter increments in deadband");

        
        // Test 11: Bias output holds when update is disabled.
        // err is valid, but ep is inside the deadband.
        apply_inputs(18'sd10000, 18'sd100, 1'b1, BIAS_MIN_Q16);
        check(!bias_valid, "No update when ep is within deadband");


        // Test 12: Output remains in legal range.
        check(bias_log_next_q16 >= BIAS_MIN_Q16 &&
              bias_log_next_q16 <= BIAS_MAX_Q16,
              "Output bias is within legal bounds");
              
        // =====================================================
        // ADDITIONAL TESTS: Append after Test 12
        // =====================================================

        // Test 13: Deadband boundary - one count below.
        apply_inputs(18'sd10000, 18'sd162, 1'b1, BIAS_MIN_Q16);
        check(!bias_valid,
              "Below deadband threshold suppresses update");

        // Test 14: Exactly at deadband threshold.
        apply_inputs(18'sd10000, 18'sd163, 1'b1, BIAS_MIN_Q16);
        check(!bias_valid,
              "Exact deadband threshold suppresses update");

        // Test 15: One count above deadband.
        apply_inputs(18'sd10000, 18'sd164, 1'b1, BIAS_MIN_Q16);
        check(bias_valid,
              "Above deadband threshold triggers update");

        // Test 16: Error guard - one count below the limit.
        apply_inputs(18'sd40819, 18'sd4096, 1'b1, BIAS_MIN_Q16);
        check(bias_valid,
              "Error just inside guard allows update");

        // Test 17: Error guard - exactly at the limit.
        apply_inputs(18'sd40820, 18'sd4096, 1'b1, BIAS_MIN_Q16);
        check(!bias_valid,
              "Error at guard limit suppresses update");

        // Reset controller for independent stateful tests.
        @(negedge clk);
        rst = 1'b1;
        tick;
        @(negedge clk);
        rst = 1'b0;

        // Test 18: Reach gain_s = 2 using a sign reversal.
        apply_inputs(18'sd10000, 18'sd4096, 1'b1, BIAS_MIN_Q16);
        apply_inputs(18'sd10000, -18'sd4096, 1'b1, BIAS_MIN_Q16);
        check(gain_s == 2,
              "Sign reversal raises gain shift to two");

        // Test 19: Twelve valid quiet passes increment calm_count.
        for (i = 0; i < 12; i = i + 1) begin
            apply_inputs(18'sd10000, 18'sd100, 1'b1, BIAS_MIN_Q16);
        end
        check(calm_count == 12,
              "Calm counter reaches configured threshold");

        // Test 20: A qualifying same-sign update releases one shift.
        // The previous eligible ep was negative.
        apply_inputs(18'sd10000, -18'sd4096, 1'b1, BIAS_MIN_Q16);
        check(bias_valid,
              "Update occurs after calm period");
        check(gain_s == 1,
              "Calm period reduces gain shift by one");
        check(calm_count == 0,
              "Calm counter resets after shift reduction");

        // Reset before testing invalid-input state retention.
        @(negedge clk);
        rst = 1'b1;
        tick;
        @(negedge clk);
        rst = 1'b0;

        // Establish gain_s = 2 and a nonzero calm counter.
        apply_inputs(18'sd10000, 18'sd4096, 1'b1, BIAS_MIN_Q16);
        apply_inputs(18'sd10000, -18'sd4096, 1'b1, BIAS_MIN_Q16);
        apply_inputs(18'sd10000, 18'sd100, 1'b1, BIAS_MIN_Q16);

        gain_snapshot = gain_s;
        calm_snapshot = calm_count;

        // Test 21: Invalid input must not change controller state.
        apply_inputs(18'sd10000, 18'sd4096, 1'b0, BIAS_MIN_Q16);
        check(!bias_valid,
              "Invalid input produces no update pulse");
        check(gain_s == gain_snapshot,
              "Invalid input preserves gain shift");
        check(calm_count == calm_snapshot,
              "Invalid input preserves calm counter");

        // Reset for an independent step-saturation test.
        @(negedge clk);
        rst = 1'b1;
        tick;
        @(negedge clk);
        rst = 1'b0;

        // Test 22: Large positive error clips the update step.
        // gain_s = 1, so 50000 * 16 / 2 exceeds MAX_STEP_Q16.
        apply_inputs(18'sd10000, 18'sd50000, 1'b1, BIAS_MIN_Q16);
        check(bias_valid,
              "Large error triggers bias update");
        check(bias_log_next_q16 == BIAS_MIN_Q16 + 32'sd21098,
              "Positive step clips to maximum allowed step");

        // Test 23: Large negative error clips the update step.
        // Reset to restore gain_s = 1 and clear previous sign.
        @(negedge clk);
        rst = 1'b1;
        tick;
        @(negedge clk);
        rst = 1'b0;

        apply_inputs(-18'sd10000, -18'sd50000, 1'b1, BIAS_MAX_Q16);
        check(bias_valid,
              "Large negative error triggers bias update");
        check(bias_log_next_q16 == BIAS_MAX_Q16 - 32'sd21098,
              "Negative step clips to maximum allowed magnitude");


        $display("----------------------------------------");
        $display("Tests run: %0d", tests);
        $display("Failures : %0d", errors);

        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TESTS FAILED");

        $display("----------------------------------------");
        $finish;
    end

endmodule
