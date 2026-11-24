`timescale 1ns / 1ps

module meter_renderer #(
    parameter [9:0] X = 10'd0,
    parameter [9:0] Y = 10'd20,
    parameter integer CELL_COUNT = 5,
    parameter [11:0] FILLED_RGB = 12'hFFF,
    parameter [11:0] EMPTY_RGB = 12'h444
)(
    input  wire [9:0] pixel_x,
    input  wire [9:0] pixel_y,
    input  wire [$clog2(CELL_COUNT + 1)-1:0] value,
    output wire draw_on,
    output wire [11:0] rgb
);
    wire row_on = (pixel_y >= Y) && (pixel_y < Y + 12);
    wire [CELL_COUNT-1:0] cell_on;
    wire [CELL_COUNT-1:0] filled_on;

    genvar cell_index;
    generate
        for (cell_index = 0; cell_index < CELL_COUNT; cell_index = cell_index + 1) begin : gen_cell
            localparam integer CELL_LEFT = X + cell_index * 20;
            localparam integer REQUIRED_VALUE = cell_index + 1;

            assign cell_on[cell_index] = row_on &&
                                         (pixel_x >= CELL_LEFT) &&
                                         (pixel_x < CELL_LEFT + 14);
            assign filled_on[cell_index] = cell_on[cell_index] && (value >= REQUIRED_VALUE);
        end
    endgenerate

    assign draw_on = |cell_on;
    assign rgb = (|filled_on) ? FILLED_RGB : EMPTY_RGB;
endmodule
