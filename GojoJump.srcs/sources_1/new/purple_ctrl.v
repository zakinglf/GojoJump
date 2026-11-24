`timescale 1ns / 1ps

`timescale 1ns / 1ps

module purple_ctrl #(
    parameter [9:0] PLAYER_WIDTH = 10'd16,
    parameter signed [11:0] PURPLE_HEIGHT = 12'sd128,
    parameter signed [11:0] PURPLE_STEP   = 12'sd8
) (
    input wire pixel_clk,
    input wire rst,
    input wire move_tick,
    input wire purple_launch,
    input wire [9:0] player_x,
    input wire [9:0] player_y,
    input wire [9:0] scroll_dy,

    output reg               purple_active,
    output reg        [9:0]  purple_x,
    output reg signed [11:0] purple_y
);

    wire signed [11:0] player_top_y = $signed({2'b00, player_y});
    wire signed [11:0] scroll_step  = $signed({2'b00, scroll_dy});
    wire signed [11:0] next_y       = purple_y - PURPLE_STEP + scroll_step;
    // The sprite canvas extends 40 pixels below the orb.
    localparam signed [11:0] PURPLE_TAIL_HEIGHT = 12'sd40;

    always @(posedge pixel_clk) begin
        if (rst) begin
            purple_active <= 1'b0;
            purple_x      <= 10'd0;
            purple_y      <= 12'sd0;
        end else if (purple_launch && !purple_active) begin
            purple_active <= 1'b1;
            purple_x      <= player_x + (PLAYER_WIDTH >> 1);
            purple_y      <= player_top_y - PURPLE_HEIGHT;
        end else if (move_tick && purple_active) begin
            if (next_y <= -PURPLE_HEIGHT - PURPLE_TAIL_HEIGHT)
                purple_active <= 1'b0;
            else
                purple_y <= next_y;
        end
    end

endmodule
