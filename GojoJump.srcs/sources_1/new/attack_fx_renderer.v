`timescale 1ns / 1ps

module attack_fx_renderer #(
    parameter integer PLAYER_WIDTH = 16,
    parameter integer PLAYER_HEIGHT = 16
)(
    input wire pixel_clk,
    input wire [9:0] pixel_x,
    input wire [9:0] pixel_y,
    input wire [9:0] attack_fx_x,
    input wire [9:0] attack_fx_y,
    input wire [2:0] attack_fx_frames,
    output wire draw_on,
    output wire [11:0] rgb
);
    localparam integer FX_WIDTH = 40;
    localparam integer FX_HEIGHT = 40;
    localparam integer FX_PIXELS = FX_WIDTH * FX_HEIGHT;
    localparam integer ROM_PIXELS = 4 * FX_PIXELS;
    localparam signed [11:0] FX_PAD_X = (FX_WIDTH - PLAYER_WIDTH) / 2;
    localparam signed [11:0] FX_PAD_Y = (FX_HEIGHT - PLAYER_HEIGHT) / 2;

    (* rom_style = "block" *) reg [12:0] fx_rom [0:ROM_PIXELS-1];
    initial $readmemh("black-flash-4x40x40.mem", fx_rom, 0, ROM_PIXELS - 1);

    wire signed [11:0] fx_left = $signed({2'b00, attack_fx_x}) - FX_PAD_X;
    wire signed [11:0] fx_top = $signed({2'b00, attack_fx_y}) - FX_PAD_Y;
    wire signed [11:0] local_x = $signed({2'b00, pixel_x}) - fx_left;
    wire signed [11:0] local_y = $signed({2'b00, pixel_y}) - fx_top;

    wire inside_fx = (local_x >= 0) && (local_x < FX_WIDTH) &&
                     (local_y >= 0) && (local_y < FX_HEIGHT);
    wire sample_fx = inside_fx &&
                     (attack_fx_frames != 3'd0) && (attack_fx_frames <= 3'd4);

    reg [12:0] frame_base;
    always @(*) begin
        case (attack_fx_frames)
            3'd3:    frame_base = FX_PIXELS;
            3'd2:    frame_base = 2 * FX_PIXELS;
            3'd1:    frame_base = 3 * FX_PIXELS;
            default: frame_base = 13'd0;
        endcase
    end

    wire [12:0] addr = sample_fx
        ? frame_base + local_y[5:0] * FX_WIDTH + local_x[5:0]
        : 13'd0;

    reg [12:0] fx_pixel;
    reg sample_fx_d;
    always @(posedge pixel_clk) begin
        fx_pixel    <= fx_rom[addr];
        sample_fx_d <= sample_fx;
    end

    assign draw_on = sample_fx_d && fx_pixel[12];
    assign rgb = fx_pixel[11:0];
endmodule
