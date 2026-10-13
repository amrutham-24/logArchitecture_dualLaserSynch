`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 13.10.2026 21:35:54
// Design Name: 
// Module Name: tb_power_estimator
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

module tb_power_estimator;

    parameter integer WIN_LOG2 = 4;
    localparam integer N = (1 << WIN_LOG2);

    reg clk = 1'b0;
    reg rst = 1'b1;
    reg signed [15:0] s_data = 16'sd0;
    reg s_valid = 1'b0;

    wire power_valid;
    wire [31:0] mean_square;

    integer errors = 0;
    integer i;

    power_estimator #(
        .SAMPLE_W(16),
        .WIN_LOG2(WIN_LOG2)
    ) dut (
        .clk(clk),
        .rst(rst),
        .s_data(s_data),
        .s_valid(s_valid),
        .power_valid(power_valid),
        .mean_square(mean_square)
    );

    always #5 clk = ~clk;

    // Send N valid samples, then check the completed window.
    task send_window;
        input integer sample_value;
        input [31:0] expected;
        begin
            for (i = 0; i < N; i = i + 1) begin
                @(negedge clk);
                s_data  = sample_value;
                s_valid = 1'b1;
            end

            // The final sample is consumed at the next rising edge.
            @(posedge clk);
            #1;

            if (power_valid !== 1'b1) begin
                errors = errors + 1;
                $display("FAIL: power_valid not asserted");
            end

            if (mean_square !== expected) begin
                errors = errors + 1;
                $display("FAIL: input=%0d expected=%0d actual=%0d",
                         sample_value, expected, mean_square);
            end
            else begin
                $display("PASS: input=%0d mean_square=%0d",
                         sample_value, mean_square);
            end

            @(negedge clk);
            s_valid = 1'b0;
            s_data  = 16'sd0;
        end
    endtask

    initial begin
        $display("Starting power_estimator tests");

        repeat (3) @(negedge clk);
        rst = 1'b0;

        send_window(100,   32'd10000);
        send_window(0,     32'd0);
        send_window(-100,  32'd10000);
        send_window(200,   32'd40000);
        send_window(32767, 32'd1073676289);
        send_window(-32768, 32'd1073741824);
        
        
        // Test: invalid samples must not complete a window.
        $display("Testing invalid samples...");

        repeat (N + 2) begin
            @(negedge clk);
            s_data  = 16'sd100;
            s_valid = 1'b0;
        end

        @(posedge clk);
        #1;

        if (power_valid !== 1'b0) begin
            errors = errors + 1;
            $display("FAIL: invalid samples caused window completion");
        end
        else begin
            $display("PASS: invalid samples were ignored");
        end

        @(negedge clk);
        s_data = 16'sd0;

        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TESTS FAILED: %0d error(s)", errors);

        $finish;
    end

endmodule
