`timescale 1ns / 1ps

module input_ctrl (
    input wire clk,
    input wire rst,
    input wire [7:0] rx_data,
    input wire rx_valid,

    output reg move_left,
    output reg move_right,
    output reg jump_pressed,
    output reg dash_pressed,
    output reg attack_pressed,
    output reg domain_pressed,
    output reg purple_pressed,
    output reg heal_down
);

    reg jump_down;
    reg dash_down;
    reg attack_down;
    reg domain_down;
    reg purple_down;

    // Hold the direction bits and detect new action presses.
    always @(posedge clk) begin
        if (rst) begin
            move_left <= 1'b0;
            move_right <= 1'b0;
            jump_down <= 1'b0;
            jump_pressed <= 1'b0;
            dash_down <= 1'b0;
            dash_pressed <= 1'b0;
            attack_down <= 1'b0;
            attack_pressed <= 1'b0;
            heal_down <= 1'b0;
            domain_down <= 1'b0;
            domain_pressed <= 1'b0;
            purple_down <= 1'b0;
            purple_pressed <= 1'b0;
        end else begin
            // Each press pulse lasts one clock cycle.
            jump_pressed <= 1'b0;
            dash_pressed <= 1'b0;
            attack_pressed <= 1'b0;
            domain_pressed <= 1'b0;
            purple_pressed <= 1'b0;

            if (rx_valid) begin
                move_left <= rx_data[0];
                move_right <= rx_data[1];

                jump_down <= rx_data[2];
                jump_pressed <= rx_data[2] && !jump_down;

                dash_down <= rx_data[3];
                dash_pressed <= rx_data[3] && !dash_down;

                attack_down <= rx_data[4];
                attack_pressed <= rx_data[4] && !attack_down;

                heal_down <= rx_data[5];

                domain_down <= rx_data[6];
                domain_pressed <= rx_data[6] && !domain_down;

                purple_down <= rx_data[7];
                purple_pressed <= rx_data[7] && !purple_down;
            end
        end
    end

endmodule
