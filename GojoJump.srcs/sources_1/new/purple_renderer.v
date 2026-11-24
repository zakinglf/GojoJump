`timescale 1ns / 1ps

`timescale 1ns / 1ps

module purple_renderer (
    input  wire               pixel_clk,
    input  wire               rst,
    input  wire        [9:0]  pixel_x,
    input  wire        [9:0]  pixel_y,
    input  wire               purple_active,
    input  wire        [9:0]  purple_x,
    input  wire signed [11:0] purple_y,

    output wire               draw_on,
    output wire        [11:0] rgb
);

    reg [2:0]  sprite_rom    [0:1839];
    reg [11:0] palette_rom   [0:7];

    initial begin
        $readmemh("purple-v4-pixel-40x46.mem", sprite_rom);
        $readmemh("purple-v4-palette-rgb444.mem", palette_rom);
    end

    wire signed [11:0] sprite_left = $signed({2'b00, purple_x}) - 12'sd80;
    wire signed [11:0] sprite_top  = purple_y - 12'sd16;
    wire signed [11:0] local_x     = $signed({2'b00, pixel_x}) - sprite_left;
    wire signed [11:0] local_y     = $signed({2'b00, pixel_y}) - sprite_top;

    wire inside_sprite = purple_active &&
                         (local_x >= 12'sd0) && (local_x < 12'sd160) &&
                         (local_y >= 12'sd0) && (local_y < 12'sd184);

    wire [10:0] sprite_addr = inside_sprite
        ? local_y[7:2] * 11'd40 + local_x[7:2]
        : 11'd0;

    reg [2:0] color_index;
    reg       inside_sprite_d;

    always @(posedge pixel_clk) begin
        color_index     <= sprite_rom[sprite_addr];
        inside_sprite_d <= !rst && inside_sprite;
    end

    assign draw_on = inside_sprite_d && (color_index != 3'd0);
    assign rgb     = palette_rom[color_index];

endmodule
