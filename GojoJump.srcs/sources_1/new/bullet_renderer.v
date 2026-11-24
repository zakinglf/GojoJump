`timescale 1ns / 1ps

module bullet_renderer #(
    parameter integer BULLET_SIZE = 4
)(
    input wire [9:0] pixel_x,
    input wire [9:0] pixel_y,
    input wire signed [11:0] bullet_x,
    input wire signed [11:0] bullet_y,
    input wire bullet_active,
    output wire draw_on
);
    wire signed [11:0] screen_x;
    wire signed [11:0] screen_y;

    assign screen_x = $signed({2'b00, pixel_x});
    assign screen_y = $signed({2'b00, pixel_y});

    assign draw_on = bullet_active &&
                     (screen_x >= bullet_x) &&
                     (screen_x < bullet_x + BULLET_SIZE) &&
                     (screen_y >= bullet_y) &&
                     (screen_y < bullet_y + BULLET_SIZE);
endmodule
