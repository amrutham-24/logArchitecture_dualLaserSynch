`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 13.10.2026 22:22:08
// Design Name: 
// Module Name: log_power_estimator
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

module log_power_estimator (
    input  wire        clk,
    input  wire        rst,

    input  wire [31:0] mean_square,
    input  wire        power_valid,

    output reg  [16:0] log_power_q12,
    output reg         log_valid
);

    // Calculates log2(x) in unsigned Q5.12 format.
    // Range supported: x = 1 through 2^32-1.
    function [16:0] log2_q12;
        input [31:0] x;

        integer k;
        integer i;

        reg [31:0] normalized;
        reg [63:0] product;
        reg [32:0] y;
        reg [11:0] fraction;

        begin
            k          = 0;
            normalized = 0;
            product    = 0;
            y          = 0;
            fraction   = 0;

            if (x == 0) begin
                log2_q12 = 17'd0;
            end
            else begin
                // Find the position of the leading one.
                for (i = 0; i < 32; i = i + 1) begin
                    if (x[i])
                        k = i;
                end

                // Normalize x into the range [1, 2).
                normalized = x << (31 - k);
                y = {1'b0, normalized};

                // Generate 12 fractional bits of log2.
                for (i = 0; i < 12; i = i + 1) begin
                    //product = y * y;
                    product = {31'b0, y} * {31'b0, y};
                    y = product >> 31;

                    if (y[32]) begin
                        y = y >> 1;
                        fraction = (fraction << 1) | 12'd1;
                    end
                    else begin
                        fraction = fraction << 1;
                    end
                end

                // Q5.12: integer log2 part followed by 12 fraction bits.
                log2_q12 = (k << 12) | fraction;
            end
        end
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            log_power_q12 <= 17'd0;
            log_valid     <= 1'b0;
        end
        else begin
            log_valid <= 1'b0;

            if (power_valid) begin
                log_power_q12 <= log2_q12(mean_square);
                log_valid     <= 1'b1;
            end
        end
    end

endmodule
