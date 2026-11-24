`timescale 1ns / 1ps

module enemy_renderer #(
    parameter integer ENEMY_WIDTH = 12,
    parameter integer ENEMY_HEIGHT = 12
)(
    input wire pixel_clk,
    input wire [9:0] pixel_x,
    input wire [9:0] pixel_y,
    input wire [9:0] enemy_x,
    input wire signed [10:0] enemy_y,
    input wire enemy_active,

    output wire draw_on,
    output wire [11:0] rgb
);
    localparam integer SPRITE_WIDTH = 12;
    localparam integer SPRITE_HEIGHT = 12;
    localparam integer SPRITE_PIXELS = SPRITE_WIDTH * SPRITE_HEIGHT;

    // Each word stores one opacity bit and an RGB444 color.
    (* rom_style = "distributed" *) reg [12:0] sprite_rom [0:SPRITE_PIXELS-1];
    initial $readmemh("jogo-head-12x12.mem", sprite_rom, 0, SPRITE_PIXELS - 1);

    wire [9:0] local_x = pixel_x - enemy_x;
    wire signed [11:0] local_y = $signed({2'b00, pixel_y}) -
                                 $signed({enemy_y[10], enemy_y});
    wire inside_sprite = enemy_active &&
                         (pixel_x >= enemy_x) &&
                         (local_x < ENEMY_WIDTH) && (local_x < SPRITE_WIDTH) &&
                         (local_y >= 0) &&
                         (local_y < ENEMY_HEIGHT) && (local_y < SPRITE_HEIGHT);
    wire [7:0] sprite_addr = inside_sprite
        ? local_y[3:0] * 8'd12 + local_x[3:0]
        : 8'd0;

    reg [12:0] sprite_pixel;
    reg inside_sprite_d;
    always @(posedge pixel_clk) begin
        sprite_pixel <= sprite_rom[sprite_addr];
        inside_sprite_d <= inside_sprite;
    end

    assign draw_on = inside_sprite_d && sprite_pixel[12];
    assign rgb = sprite_pixel[11:0];
endmodule
