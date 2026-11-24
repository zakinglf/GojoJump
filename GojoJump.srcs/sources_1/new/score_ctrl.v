`timescale 1ns / 1ps

module score_ctrl (
    input wire pixel_clk,
    input wire rst,
    input wire move_tick,
    input wire [9:0] scroll_dy,
    input wire [15:0] kill_bonus,
    output reg [15:0] score,
    output reg [19:0] score_digits
);

    wire [9:0] scroll_gain = move_tick ? scroll_dy : 10'd0;
    wire score_update = (scroll_gain != 10'd0) || (kill_bonus != 16'd0);
    wire [17:0] next_score;
    wire [15:0] updated_score;
    assign next_score = {2'b00, score} + {8'd0, scroll_gain} + {2'b00, kill_bonus};
    assign updated_score = (|next_score[17:16]) ? 16'hFFFF : next_score[15:0];

    always @(posedge pixel_clk) begin
        if (rst) begin
            score <= 16'd0;
        end else if (score_update) begin
            score <= updated_score;
        end
    end

    // Convert one binary bit per pixel clock using shift-and-add-3.
    reg [15:0] binary_bits;
    reg [4:0] bits_left;
    reg [19:0] working_digits;
    reg [19:0] adjusted_digits;
    wire [19:0] shifted_digits;
    integer i;

    always @* begin
        adjusted_digits = working_digits;
        for (i = 0; i < 5; i = i + 1) begin
            if (working_digits[i*4 +: 4] >= 4'd5)
                adjusted_digits[i*4 +: 4] = working_digits[i*4 +: 4] + 4'd3;
        end
    end

    assign shifted_digits = {adjusted_digits[18:0], binary_bits[15]};

    always @(posedge pixel_clk) begin
        if (rst) begin
            binary_bits <= 16'd0;
            bits_left <= 5'd0;
            working_digits <= 20'd0;
            score_digits <= 20'd0;
        end else if (score_update) begin
            binary_bits <= updated_score;
            bits_left <= 5'd16;
            working_digits <= 20'd0;
        end else if (bits_left != 5'd0) begin
            binary_bits <= {binary_bits[14:0], 1'b0};
            bits_left <= bits_left - 5'd1;
            working_digits <= shifted_digits;
            // Publish all five digits together at the end of the conversion.
            if (bits_left == 5'd1)
                score_digits <= shifted_digits;
        end
    end
endmodule
