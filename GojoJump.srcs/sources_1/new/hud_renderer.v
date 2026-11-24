`timescale 1ns / 1ps

module hud_renderer(
    input wire [9:0] pixel_x,
    input wire [9:0] pixel_y,
    input wire [19:0] score_digits,
    input wire [2:0] hp,
    input wire [2:0] cursed_energy,
    output wire hud_on,
    output wire [11:0] hud_rgb
    );

    wire [4:0] score_on;
    wire hp_on;
    wire [11:0] hp_rgb;
    wire energy_on;
    wire [11:0] energy_rgb;

    genvar i;
    generate
        for (i = 0; i < 5; i = i + 1) begin: gen_score
            localparam [9:0] DIGIT_X = 16 + i * 16;

            digit_renderer #(.X(DIGIT_X), .Y(10'd16)) u_digit (
                .pixel_x(pixel_x),
                .pixel_y(pixel_y),
                .digit(score_digits[(4-i)*4 +: 4]),
                .draw_on(score_on[i])
            );
        end
    endgenerate

    meter_renderer #(
        .X(10'd108),
        .CELL_COUNT(5),
        .FILLED_RGB(12'hF45),
        .EMPTY_RGB(12'h444)
    ) u_health (
        .pixel_x(pixel_x),
        .pixel_y(pixel_y),
        .value(hp),
        .draw_on(hp_on),
        .rgb(hp_rgb)
    );

    meter_renderer #(
        .X(10'd224),
        .CELL_COUNT(6),
        .FILLED_RGB(12'hA6F),
        .EMPTY_RGB(12'h324)
    ) u_cursed_energy (
        .pixel_x(pixel_x),
        .pixel_y(pixel_y),
        .value(cursed_energy),
        .draw_on(energy_on),
        .rgb(energy_rgb)
    );

    assign hud_on = (|score_on) || hp_on || energy_on;
    assign hud_rgb = (|score_on) ? 12'h0F0 :
                             hp_on ? hp_rgb :
                                     energy_rgb;
endmodule
