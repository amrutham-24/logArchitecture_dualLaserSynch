`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 13.10.2026 22:24:54
// Design Name: 
// Module Name: tb_log_power_estimator
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

module tb_log_power_estimator;

    reg clk = 1'b0;
    reg rst = 1'b1;

    reg [31:0] mean_square = 32'd0;
    reg power_valid = 1'b0;

    wire [16:0] log_power_q12;
    wire log_valid;

    integer errors = 0;
    integer difference;

    log_power_estimator dut (
        .clk(clk),
        .rst(rst),
        .mean_square(mean_square),
        .power_valid(power_valid),
        .log_power_q12(log_power_q12),
        .log_valid(log_valid)
    );

    always #5 clk = ~clk;

    task check_log;
        input [31:0] test_value;
        input integer expected_q12;
        input integer tolerance;
        begin
            // Apply input on falling edge.
            @(negedge clk);
            mean_square = test_value;
            power_valid = 1'b1;

            // DUT samples power_valid on rising edge.
            @(posedge clk);
            #1;

            if (log_valid !== 1'b1) begin
                errors = errors + 1;
                $display(
                    "FAIL: log_valid not asserted for input %0d",
                    test_value
                );
            end
            else begin
                // Use signed integer arithmetic for the difference.
                difference = $signed({1'b0, log_power_q12})
                           - expected_q12;

                if (difference < 0)
                    difference = -difference;

                if (difference > tolerance) begin
                    errors = errors + 1;
                    $display(
                        "FAIL: input=%0d expected_q12=%0d actual_q12=%0d",
                        test_value, expected_q12, log_power_q12
                    );
                end
                else begin
                    $display(
                        "PASS: input=%0d log_q12=%0d expected_q12=%0d",
                        test_value, log_power_q12, expected_q12
                    );
                end
            end

            // Deassert valid before the next test.
            @(negedge clk);
            power_valid = 1'b0;
            mean_square = 32'd0;
        end
    endtask

    initial begin
        $display("---------------------------------------");
        $display("Starting log_power_estimator tests");
        $display("---------------------------------------");

        repeat (3) @(negedge clk);
        rst = 1'b0;

        // Powers of two: expected results are exact.
        check_log(32'd1,          0,      0);
        check_log(32'd2,          4096,   0);
        check_log(32'd4,          8192,   0);
        check_log(32'd1024,       40960,  0);

        // Non-power-of-two: log2(10000) * 4096 ~= 54426.4.
        check_log(32'd10000,      54426,  2);

        // log2(2^30) = 30; matches the ADC sample scaling.
        check_log(32'd1073741824, 122880, 0);
        
        // Edge case: just below 2^20.
        // log2(1048575) is approximately 19.9999986.
        // Q5.12 result is approximately 81919.994,
        // so the integer result may be 81919 or 81920.
        check_log(32'd1048575, 81920, 1);

        // Zero power: RTL returns zero; controller must flag NOSIG.
        check_log(32'd0,          0,      0);
                
       // Boundary tests around 2^10 = 1024
        
        check_log(32'd1023, 40954, 1);  // 2^10 - 1
        check_log(32'd1024, 40960, 0);  // 2^10
        check_log(32'd1025, 40965, 1);  // 2^10 + 1
        // Additional non-power-of-two tests
        // Additional non-power-of-two tests
        check_log(32'd3,          6492,  1);
        check_log(32'd255,       32745,  1);
        check_log(32'd65535,     65536,  1);
        check_log(32'd1000000,   81640,  1);
        
        if (errors == 0)
            $display("ALL LOG-POWER TESTS PASSED");
        else
            $display("LOG-POWER TESTS FAILED: %0d error(s)", errors);

        
        $finish;
    end

endmodule
