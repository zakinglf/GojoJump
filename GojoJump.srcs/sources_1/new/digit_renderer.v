`timescale 1ns / 1ps

module digit_renderer #(
    parameter [9:0] X = 10'd16,
    parameter [9:0] Y = 10'd16
)(
    input wire [9:0] pixel_x,
    input wire [9:0] pixel_y,
    input wire [3:0] digit,
    output wire draw_on
    );

    reg [14:0] glyph;
    wire [9:0] dx = pixel_x - X;
    wire [9:0] dy = pixel_y - Y;
    wire [1:0] col = dx[3:2];
    wire [2:0] row = dy[4:2];
    wire [3:0] cell_index = 3*row + col;

    always @* begin
        case (digit)
            4'd0: glyph = 15'b111_101_101_101_111;
            4'd1: glyph = 15'b010_110_010_010_111;
            4'd2: glyph = 15'b111_001_111_100_111;
            4'd3: glyph = 15'b111_001_111_001_111;
            4'd4: glyph = 15'b101_101_111_001_001;
            4'd5: glyph = 15'b111_100_111_001_111;
            4'd6: glyph = 15'b111_100_111_101_111;
            4'd7: glyph = 15'b111_001_001_001_001;
            4'd8: glyph = 15'b111_101_111_101_111;
            4'd9: glyph = 15'b111_101_111_001_111;
            default: glyph = 15'd0;
        endcase
    end

    assign draw_on = (pixel_x >= X) && (pixel_y >= Y)
                     && (dx < 10'd12) && (dy < 10'd20)
                     && glyph[14 - cell_index];
endmodule
