`timescale 1ns / 1ps

module scene_renderer #(
    parameter MEM_FILE = "game-over-320x240-gray4.mem",
    parameter integer PIXEL_SHIFT = 1
)(
    input wire pixel_clk,
    input wire rst,
    input wire video_on,
    input wire scene_on,
    input wire [9:0] pixel_x,
    input wire [9:0] pixel_y,
    output reg draw_on,
    output wire [11:0] rgb
);
    localparam integer IMAGE_WIDTH = 640 >> PIXEL_SHIFT;
    localparam integer IMAGE_HEIGHT = 480 >> PIXEL_SHIFT;
    localparam integer IMAGE_PIXELS = IMAGE_WIDTH * IMAGE_HEIGHT;
    localparam integer ADDR_WIDTH = $clog2(IMAGE_PIXELS);
    localparam [ADDR_WIDTH-1:0] IMAGE_STRIDE = IMAGE_WIDTH;

    (* rom_style = "block" *) reg [3:0] image_rom [0:IMAGE_PIXELS-1];
    initial $readmemh(MEM_FILE, image_rom);

    wire [9-PIXEL_SHIFT:0] image_x = pixel_x[9:PIXEL_SHIFT];
    wire [9-PIXEL_SHIFT:0] image_y = pixel_y[9:PIXEL_SHIFT];
    wire [ADDR_WIDTH-1:0] image_addr = image_y * IMAGE_STRIDE + image_x;
    wire read_on = video_on && scene_on;

    reg [3:0] gray;
    always @(posedge pixel_clk) begin
        if (rst)
            draw_on <= 1'b0;
        else
            draw_on <= read_on;

        if (read_on)
            gray <= image_rom[image_addr];
    end

    assign rgb = {3{gray}};
endmodule
