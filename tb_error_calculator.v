`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 13.10.2026 23:21:50
// Design Name: 
// Module Name: tb_error_calculator
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

module tb_error_calculator;

    reg clk = 1'b0;
    reg rst = 1'b1;

    reg [16:0] log_power_q12 = 17'd0;
    reg log_valid = 1'b0;

    reg signed [31:0] bias_log_q16 = 32'sd0;
    reg signed [31:0] bias_hist_log_q16 = 32'sd0;

    wire signed [17:0] dbg_err_q12;
    wire signed [17:0] dbg_ep_q12;
    wire err_valid;

    integer errors = 0;

    error_calculator dut (
        .clk(clk),
        .rst(rst),
        .log_power_q12(log_power_q12),
        .log_valid(log_valid),
        .bias_log_q16(bias_log_q16),
        .bias_hist_log_q16(bias_hist_log_q16),
        .dbg_err_q12(dbg_err_q12),
        .dbg_ep_q12(dbg_ep_q12),
        .err_valid(err_valid)
    );

    always #5 clk = ~clk;

    task check_case;
        input [16:0] measured;
        input signed [31:0] current_bias;
        input signed [31:0] history_bias;
        input integer expected_err;
        input integer expected_ep;

        begin
            @(negedge clk);
            log_power_q12 = measured;
            bias_log_q16 = current_bias;
            bias_hist_log_q16 = history_bias;
            log_valid = 1'b1;

            @(posedge clk);
            #1;

            if (err_valid !== 1'b1) begin
                errors = errors + 1;
                $display("FAIL: err_valid not asserted");
            end
            else if (($signed(dbg_err_q12) !== expected_err) ||
                     ($signed(dbg_ep_q12) !== expected_ep)) begin
                errors = errors + 1;
                $display(
                    "FAIL: measured=%0d err=%0d (expected %0d), ep=%0d (expected %0d)",
                    measured,
                    $signed(dbg_err_q12), expected_err,
                    $signed(dbg_ep_q12), expected_ep
                );
            end
            else begin
                $display(
                    "PASS: measured=%0d err=%0d ep=%0d",
                    measured,
                    $signed(dbg_err_q12),
                    $signed(dbg_ep_q12)
                );
            end

            @(negedge clk);
            log_valid = 1'b0;
        end
    endtask

    initial begin
        $display("----------------------------------");
        $display("Starting error_calculator tests");
        $display("----------------------------------");

        repeat (3) @(negedge clk);
        rst = 1'b0;

                // 1. At target power: error should be zero.
        check_case(17'd79283, 0, 0, 0, 0);

        // 2. Measured log-power is zero.
        // Error = 79283 - 0 = 79283.
        check_case(17'd0, 0, 0, 79283, 79283);

        // 3. Measured log-power exceeds target.
        // Error = 79283 - 100000 = -20717.
        check_case(17'd100000, 0, 0, -20717, -20717);

        // 4. Bias delta = +1.0 in Q16.16.
        // Compensation = +6144 in Q12.
        // Predicted error = 0 - 6144.
        check_case(17'd79283, 32'sd65536, 32'sd0,
                   0, -6144);

        // 5. Bias delta = -1.0 in Q16.16.
        // Compensation = -6144 in Q12.
        // Predicted error = 0 + 6144.
        check_case(17'd79283, 32'sd0, 32'sd65536,
                   0, 6144);
                   
        // 6. Equal current and historical biases: no compensation.
        check_case(17'd90000, 32'sd131072, 32'sd131072,
                   -10717, -10717);

       // 7. Invalid cycle: outputs must hold their previous values
begin : invalid_cycle_test
    reg signed [17:0] saved_err;
    reg signed [17:0] saved_ep;

    saved_err = dbg_err_q12;
    saved_ep  = dbg_ep_q12;

    @(posedge clk);
    #1;

    if (err_valid !== 1'b0 ||
        dbg_err_q12 !== saved_err ||
        dbg_ep_q12 !== saved_ep) begin
        errors = errors + 1;
        $display("FAIL: invalid cycle output hold");
    end
    else begin
        $display("PASS: invalid cycle output hold");
    end
end

        // 8. Reset test.
        @(negedge clk);
        rst = 1'b1;

        @(posedge clk);
        #1;

        if (dbg_err_q12 !== 18'sd0 ||
            dbg_ep_q12 !== 18'sd0 ||
            err_valid !== 1'b0) begin
            errors = errors + 1;
            $display("FAIL: reset");
        end
        else begin
            $display("PASS: reset");
        end
                // Ensure DUT is out of reset before additional tests
        @(negedge clk);
        rst = 1'b0;
        log_valid = 1'b0;

        repeat (2) @(negedge clk);
        // 9. Fractional positive bias delta:
// delta = +0.5 in Q16.16.
// Compensation = +0.75 in log2 units = 3072 in Q12.
// At target, error = 0; predicted error = -3072.
check_case(17'd79283, 32'sd32768, 32'sd0,
           0, -3072);

// 10. Fractional negative bias delta:
// delta = -0.5 in Q16.16.
// Compensation = -0.75 in log2 units = -3072 in Q12.
// At target, error = 0; predicted error = +3072.
check_case(17'd79283, 32'sd0, 32'sd32768,
           0, 3072);

// 11. Large positive compensation: saturate negative.
// At target, error = 0; predicted error saturates at -131072.
check_case(17'd79283, 32'sd16777216, 32'sd0,
           0, -131072);

// 12. Large negative compensation: saturate positive.
// At target, error = 0; predicted error saturates at +131071.
check_case(17'd79283, 32'sd0, 32'sd16777216,
           0, 131071);

// 13. Consecutive valid measurements.
// Measured log-power = 90000.
// Error = 79283 - 90000 = -10717.
@(negedge clk);
rst = 1'b0;
log_power_q12 = 17'd90000;
bias_log_q16 = 32'sd0;
bias_hist_log_q16 = 32'sd0;
log_valid = 1'b1;

repeat (2) begin
    @(posedge clk);
    #1;

    if (err_valid !== 1'b1 ||
        $signed(dbg_err_q12) !== -10717 ||
        $signed(dbg_ep_q12) !== -10717) begin
        errors = errors + 1;
        $display("FAIL: consecutive valid measurement");
    end
    else begin
        $display("PASS: consecutive valid measurement");
    end
end

@(negedge clk);
log_valid = 1'b0;

        // 14. Reset after active measurements
        @(negedge clk);
        rst = 1'b1;

        @(posedge clk);
        #1;
        if (dbg_err_q12 !== 18'sd0 ||
            dbg_ep_q12 !== 18'sd0 ||
            err_valid !== 1'b0) begin
            errors = errors + 1;
            $display("FAIL: reset after active measurements");
        end
        else begin
            $display("PASS: reset after active measurements");
        end

        @(negedge clk);
        rst = 1'b0;
        
        // 15. At target power: error should be zero.
check_case(17'd79283, 0, 0, 0, 0);

// 16. Below target: positive error.
check_case(17'd70000, 0, 0, 9283, 9283);

// 17. Above target: negative error.
check_case(17'd100000, 0, 0, -20717, -20717);

// 18. Bias delta = +1.0 in Q16.16.
// Error = 0; predicted error = -6144.
check_case(17'd79283, 32'sd65536, 32'sd0,
           0, -6144);

// 19. Bias delta = -1.0 in Q16.16.
check_case(17'd79283, 32'sd0, 32'sd65536,
           0, 6144);


        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TESTS FAILED: %0d error(s)", errors);

        $finish;
    end

endmodule
