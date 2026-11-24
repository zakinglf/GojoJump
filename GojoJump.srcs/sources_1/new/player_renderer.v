`timescale 1ns / 1ps

module player_renderer #(
    parameter integer PLAYER_WIDTH = 16,
    parameter integer PLAYER_HEIGHT = 16
)(
    input wire pixel_clk,
    input wire [9:0] pixel_x,
    input wire [9:0] pixel_y,
    input wire [9:0] player_x,
    input wire [9:0] player_y,

    output wire draw_on,
    output wire [11:0] rgb
);
    localparam integer SPRITE_WIDTH = 16;
    localparam integer SPRITE_HEIGHT = 16;
    localparam integer SPRITE_PIXELS = SPRITE_WIDTH * SPRITE_HEIGHT;

    (* rom_style = "block" *) reg [12:0] sprite_rom [0:SPRITE_PIXELS-1];
    initial $readmemh("player-gojo-16x16-trial.mem", sprite_rom, 0, SPRITE_PIXELS - 1);

    reg [12:0] sprite_pixel;
    reg inside_sprite_d;

    wire [9:0] local_x = pixel_x - player_x;
    wire [9:0] local_y = pixel_y - player_y;
    wire inside_sprite = (pixel_x >= player_x) && (pixel_y >= player_y) &&
                         (local_x < SPRITE_WIDTH) && (local_x < PLAYER_WIDTH) &&
                         (local_y < SPRITE_HEIGHT) && (local_y < PLAYER_HEIGHT);
    wire [7:0] sprite_addr = inside_sprite
        ? {local_y[3:0], local_x[3:0]} : 8'd0;
    
    always @(posedge pixel_clk) begin
        sprite_pixel    <= sprite_rom[sprite_addr];
        inside_sprite_d <= inside_sprite;
    end

    assign draw_on = inside_sprite_d && sprite_pixel[12];
    assign rgb = sprite_pixel[11:0];

endmodule
