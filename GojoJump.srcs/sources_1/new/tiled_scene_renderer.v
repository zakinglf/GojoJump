`timescale 1ns / 1ps

module tiled_scene_renderer #(
    parameter TILE_MAP_FILE = "purple-cutscene-tile-map.mem",
    parameter TILE_PIXELS_FILE = "purple-cutscene-tile-pixels.mem",
    parameter integer TILE_COUNT = 2065
) (
    input wire pixel_clk,
    input wire rst,
    input wire video_on,
    input wire scene_on,
    input wire [9:0] pixel_x,
    input wire [9:0] pixel_y,
    output reg draw_on,
    output wire [11:0] rgb
);
    localparam integer TILE_ID_WIDTH = $clog2(TILE_COUNT);

    (* rom_style = "distributed" *)
    reg [TILE_ID_WIDTH-1:0] tile_map [0:4799];
    (* rom_style = "block" *)
    reg [3:0] tile_pixels [0:TILE_COUNT*16-1];

    initial begin
        $readmemh(TILE_MAP_FILE, tile_map);
        $readmemh(TILE_PIXELS_FILE, tile_pixels);
    end

    // A 4x4 image tile spans 8x8 VGA pixels at 2x scale.
    wire [12:0] map_addr = pixel_y[9:3] * 13'd80 + pixel_x[9:3];
    wire [TILE_ID_WIDTH-1:0] tile_id = tile_map[map_addr];
    wire [TILE_ID_WIDTH+3:0] pixel_addr = {tile_id, pixel_y[2:1], pixel_x[2:1]};
    wire read_on = video_on && scene_on && !rst;

    reg [3:0] gray;
    always @(posedge pixel_clk) begin
        draw_on <= read_on;
        if (read_on)
            gray <= tile_pixels[pixel_addr];
    end

    assign rgb = {3{gray}};
endmodule
