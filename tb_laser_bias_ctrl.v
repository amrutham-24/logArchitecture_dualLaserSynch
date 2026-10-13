
`timescale 1ns / 1ps

module tb_laser_bias_ctrl;

    localparam integer SAMPLE_W = 16;
    localparam integer WIN_LOG2 = 4;
    localparam integer WINDOW_SIZE = (1 << WIN_LOG2);
    localparam integer NUM_FEEDBACK_PASSES = 30;

    reg clk;
    reg rst;
    reg signed [SAMPLE_W-1:0] s_data;
    reg s_valid;
    reg [15:0] previous_bias;

    wire [15:0] bias_q11;
    wire bias_valid;
    wire [2:0] status;

    wire [31:0] dbg_mean;
    wire [16:0] dbg_lp_q12;
    wire signed [17:0] dbg_err_q12;
    wire signed [17:0] dbg_ep_q12;
    wire [2:0] dbg_shift;
    wire dbg_flip;
    wire signed [31:0] dbg_l_q16;

    integer valid_count;
    integer feedback_pass;
    integer feedback_sample;
    integer previous_bias;
    integer pass_updates;

    // Status encoding from laser_bias_ctrl.v
    localparam [2:0] STATUS_HOLD  = 3'd0;
    localparam [2:0] STATUS_STEP  = 3'd1;
    localparam [2:0] STATUS_SAT   = 3'd2;
    localparam [2:0] STATUS_NOSIG = 3'd3;
    localparam [2:0] STATUS_RANGE = 3'd4;

    // ---------------------------------------------------------
    // DUT
    // ---------------------------------------------------------

    laser_bias_ctrl #(
        .SAMPLE_W(SAMPLE_W),
        .WIN_LOG2(WIN_LOG2),
        .S_MIN(1),
        .S_MAX(5),
        .S_INIT(1),
        .CALM_COUNT(12),
        .ADAPT(1)
    ) dut (
        .clk(clk),
        .rst(rst),
        .s_data(s_data),
        .s_valid(s_valid),
        .bias_q11(bias_q11),
        .bias_valid(bias_valid),
        .status(status),
        .dbg_mean(dbg_mean),
        .dbg_lp_q12(dbg_lp_q12),
        .dbg_err_q12(dbg_err_q12),
        .dbg_ep_q12(dbg_ep_q12),
        .dbg_shift(dbg_shift),
        .dbg_flip(dbg_flip),
        .dbg_l_q16(dbg_l_q16)
    );

    // 100 MHz clock
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ---------------------------------------------------------
    // Utility tasks
    // ---------------------------------------------------------

    task wait_cycles;
        input integer count;
        integer j;
        begin
            for (j = 0; j < count; j = j + 1)
                @(posedge clk);
        end
    endtask

    task send_constant;
        input signed [15:0] sample;
        input integer count;
        integer j;
        begin
            for (j = 0; j < count; j = j + 1) begin
                @(negedge clk);
                s_data = sample;
                s_valid = 1'b1;
            end

            @(negedge clk);
            s_valid = 1'b0;
            s_data = 0;
        end
    endtask

    // One feedback pass:
    // Freeze the sample amplitude for an entire window.
    //
    // Toy model:
    // sample amplitude ~= 140 * linear bias.
    // bias_q11 represents the linear bias in Q5.11.
    //
    // This is an integration-test model, not a physical
    // laser/photodetector model from MATLAB.

   
task run_feedback_pass;
    input integer pass_number;
    integer j;
    integer sample_snapshot;
    begin
        @(negedge clk);

        sample_snapshot = (bias_q11 * 140) / 2048;

        if (sample_snapshot < 0)
            sample_snapshot = 0;

        if (sample_snapshot > 32767)
            sample_snapshot = 32767;

        $display("");
        $display("FEEDBACK PASS %0d", pass_number);
        $display("  Bias before pass = %0d (Q11)", bias_q11);
        $display("  Sample amplitude = %0d", sample_snapshot);

        for (j = 0; j < WINDOW_SIZE; j = j + 1) begin
            @(negedge clk);
            s_data = sample_snapshot;
            s_valid = 1'b1;
        end

        @(negedge clk);
        s_data = 0;
        s_valid = 1'b0;

        // Allow power, log-power, error and controller
        // valid signals to propagate through the pipeline.
        wait_cycles(10);

        $display("  Mean square = %0d", dbg_mean);
        $display("  Log power   = %0d", dbg_lp_q12);
        $display("  Error       = %0d", dbg_err_q12);
        $display("  EP          = %0d", dbg_ep_q12);
        $display("  Bias log    = %0d", dbg_l_q16);
        $display("  Bias Q11    = %0d", bias_q11);
        $display("  Shift       = %0d", dbg_shift);
        $display("  Status      = %0d", status);

        // Check bias stability from pass 27 onward.
        if (pass_number >= 27) begin
            if (bias_q11 !== previous_bias) begin
                $error("FAIL: Bias changed after expected settling at pass %0d. Previous=%0d Current=%0d",
                       pass_number, previous_bias, bias_q11);
            end
            else begin
                $display("PASS: Bias stable at pass %0d", pass_number);
            end
        end

        // Save the bias for comparison with the next pass.
        previous_bias = bias_q11;
    end
endtask

    // ---------------------------------------------------------
    // Count bias update pulses
    // ---------------------------------------------------------

    always @(posedge clk) begin
        if (rst)
            valid_count <= 0;
        else if (bias_valid)
            valid_count <= valid_count + 1;
    end

    // ---------------------------------------------------------
    // Cycle-by-cycle diagnostics
    // ---------------------------------------------------------

    always @(posedge clk) begin
        if (!rst) begin
            if (dut.err_valid) begin
                $display(
                    "ERR: t=%0t err=%0d ep=%0d bias=%0d",
                    $time,
                    dbg_err_q12,
                    dbg_ep_q12,
                    dut.bias_log_current_q16
                );
            end

            if (dut.ctrl_bias_valid) begin
                $display(
                    "UPDATE: t=%0t old=%0d next=%0d ep=%0d shift=%0d",
                    $time,
                    dut.bias_log_current_q16,
                    dut.ctrl_bias_next_q16,
                    dbg_ep_q12,
                    dbg_shift
                );
            end
        end
    end

    // ---------------------------------------------------------
    // Main test sequence
    // ---------------------------------------------------------

    initial begin
        rst = 1'b1;
        s_data = 0;
        s_valid = 1'b0;
        valid_count = 0;
        previous_bias = 0;

        feedback_pass = 0;
        feedback_sample = 0;
        previous_bias = bias_q11;
        pass_updates = 0;

        $dumpfile("tb_laser_bias_ctrl.vcd");
        $dumpvars(0, tb_laser_bias_ctrl);

        $display("------------------------------------------");
        $display("Starting laser_bias_ctrl testbench");
        $display("------------------------------------------");

        // Test 1: reset
        wait_cycles(4);
        @(negedge clk);
        rst = 1'b0;

        wait_cycles(2);

        if (bias_q11 != 0)
            $display("PASS: reset and initial bias");
        else
            $display("FAIL: bias output is zero after reset");

        // Test 2: zero input
        $display("");
        $display("TEST 2: zero input");

        send_constant(16'sd0, WINDOW_SIZE);
        wait_cycles(10);

        if (status == STATUS_NOSIG)
            $display("PASS: zero-power status detected");
        else
            $display("WARNING: zero-power status=%0d", status);

        // Test 3: constant positive input
        $display("");
        $display("TEST 3: constant input 1000");

        send_constant(16'sd1000, WINDOW_SIZE);
        wait_cycles(10);

        $display("  Mean square = %0d", dbg_mean);
        $display("  Log power   = %0d", dbg_lp_q12);
        $display("  Error       = %0d", dbg_err_q12);
        $display("  EP          = %0d", dbg_ep_q12);
        $display("  Bias Q11    = %0d", bias_q11);
        $display("  Bias log    = %0d", dbg_l_q16);
        $display("  Shift       = %0d", dbg_shift);
        $display("  Status      = %0d", status);

        if (dbg_mean == 32'd1000000)
            $display("PASS: mean square for 1000");
        else
            $display("FAIL: expected 1000000, got %0d", dbg_mean);

        // Test 4: higher input
        $display("");
        $display("TEST 4: constant input 2000");

        send_constant(16'sd2000, WINDOW_SIZE);
        wait_cycles(10);

        $display("  Mean square = %0d", dbg_mean);
        $display("  Error       = %0d", dbg_err_q12);
        $display("  EP          = %0d", dbg_ep_q12);
        $display("  Bias Q11    = %0d", bias_q11);
        $display("  Status      = %0d", status);

        if (dbg_mean == 32'd4000000)
            $display("PASS: mean square for 2000");
        else
            $display("FAIL: expected 4000000, got %0d", dbg_mean);

        // Test 5: negative signed samples
        $display("");
        $display("TEST 5: negative input -500");

        send_constant(-16'sd500, WINDOW_SIZE);
        wait_cycles(10);

        $display("  Mean square = %0d", dbg_mean);

        if (dbg_mean == 32'd250000)
            $display("PASS: signed samples squared correctly");
        else
            $display("FAIL: expected 250000, got %0d", dbg_mean);

        // Test 6: invalid cycles are ignored
        $display("");
        $display("TEST 6: invalid cycles");

        @(negedge clk);
        s_valid = 1'b0;
        s_data = 16'sd3000;

        wait_cycles(8);

        send_constant(16'sd3000, WINDOW_SIZE);
        wait_cycles(10);

        $display("  Mean square = %0d", dbg_mean);

        if (dbg_mean == 32'd9000000)
            $display("PASS: valid samples accumulated correctly");
        else
            $display("FAIL: expected 9000000, got %0d", dbg_mean);

        // Test 7: log bias bounds
        $display("");
        $display("TEST 7: bias limits");

        if ((dbg_l_q16 >= 32'sd152170) &&
            (dbg_l_q16 <= 32'sd315055))
            $display("PASS: log bias within limits");
        else
            $display("FAIL: log bias outside limits: %0d", dbg_l_q16);

        // Test 8: repeat measurements with bias-dependent feedback
        //
        // Fixed-sample tests above are diagnostic only. This section
        // allows the input amplitude to respond to the current bias.
        //
        // The toy feedback model is intentionally explicit. It must
        // not be mistaken for the external MATLAB plant model.

        $display("");
        $display("------------------------------------------");
        $display("TEST 8: bias-dependent feedback");
        $display("------------------------------------------");

        previous_bias = bias_q11;
        pass_updates = valid_count;

        for (feedback_pass = 1;
             feedback_pass <= NUM_FEEDBACK_PASSES;
             feedback_pass = feedback_pass + 1) begin

            run_feedback_pass(feedback_pass);

            if (bias_q11 != previous_bias) begin
                $display("  PASS: bias changed during feedback run");
            end
            else begin
                $display("  NOTE: bias unchanged during this pass");
            end

            previous_bias = bias_q11;
        end

        // Final summary
        $display("");
        $display("------------------------------------------");
        $display("FINAL SUMMARY");
        $display("------------------------------------------");
        $display("Bias update count = %0d", valid_count);
        $display("Final bias Q11    = %0d", bias_q11);
        $display("Final bias log    = %0d", dbg_l_q16);
        $display("Final error       = %0d", dbg_err_q12);
        $display("Final EP          = %0d", dbg_ep_q12);
        $display("Final status      = %0d", status);

        if (valid_count > 0)
            $display("PASS: controller generated update pulses");
        else
            $display("FAIL: no bias update pulses observed");

        if ((dbg_l_q16 >= 32'sd152170) &&
            (dbg_l_q16 <= 32'sd315055))
            $display("PASS: final bias within limits");
        else
            $display("FAIL: final bias outside limits");

        $display("------------------------------------------");
        $display("Testbench completed");
        $display("------------------------------------------");

        wait_cycles(5);
        $finish;
    end

    // Global timeout
    initial begin
        #500000;
        $display("TIMEOUT: simulation did not finish");
        $finish;
    end

endmodule
