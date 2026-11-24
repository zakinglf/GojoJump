`timescale 1ns / 1ps

module platform_renderer #(
    parameter integer PLATFORM_HEIGHT = 6
)(
    input wire [9:0] pixel_x,
    input wire [9:0] pixel_y,

    input wire [9:0] platform_x,
    input wire [9:0] platform_y,
    input wire [9:0] platform_width,
    input wire platform_active,
    input wire platform_reward_ready,

    output wire draw_on,
    output wire [11:0] rgb
    );

    assign draw_on = (pixel_x >= platform_x) &&
                     (pixel_x < platform_x + platform_width) &&
                     (pixel_y >= platform_y) &&
                     (pixel_y < platform_y + PLATFORM_HEIGHT) &&
                     platform_active;

    assign rgb = platform_reward_ready ? 12'hA6F : 12'h888;

endmodule
