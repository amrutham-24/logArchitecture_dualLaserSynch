
`timescale 1ns / 1ps

module power_estimator #(
    parameter integer SAMPLE_W  = 16,
    parameter integer WIN_LOG2  = 12
)(
    input  wire                       clk,
    input  wire                       rst,

    input  wire signed [SAMPLE_W-1:0] s_data,
    input  wire                       s_valid,

    output reg                        power_valid,
    output reg  [31:0]                mean_square
);

    // Number of samples per window = 2^WIN_LOG2.
    localparam integer N = (1 << WIN_LOG2);

    // Enough bits for the sample square.
    localparam integer SQ_W = 2 * SAMPLE_W;

    // Enough bits to accumulate N maximum-sized squares.
    localparam integer ACC_W = 2 * SAMPLE_W + WIN_LOG2;

    reg [ACC_W-1:0] accumulator;
    reg [WIN_LOG2-1:0] count;

    wire signed [31:0] sample_product;
    wire        [31:0] sample_square;

    assign sample_product = $signed(s_data) * $signed(s_data);
    assign sample_square  = sample_product;

    // Extend the square before adding it to the accumulator.
    wire [ACC_W-1:0] square_extended;
    wire [ACC_W-1:0] sum_next;

    assign square_extended = {{(ACC_W-SQ_W){1'b0}},
                              sample_square};

    assign sum_next = accumulator + square_extended;

    always @(posedge clk) begin
        if (rst) begin
            accumulator <= {ACC_W{1'b0}};
            count       <= {WIN_LOG2{1'b0}};
            mean_square <= 32'd0;
            power_valid <= 1'b0;
        end
        else begin
            power_valid <= 1'b0;

            if (s_valid) begin
                if (count == N-1) begin
                    // Include the final sample in this window.
                    mean_square <= sum_next >> WIN_LOG2;

                    accumulator <= {ACC_W{1'b0}};
                    count       <= {WIN_LOG2{1'b0}};
                    power_valid <= 1'b1;
                end
                else begin
                    accumulator <= sum_next;
                    count       <= count + 1'b1;
                end
            end
        end
    end

endmodule
