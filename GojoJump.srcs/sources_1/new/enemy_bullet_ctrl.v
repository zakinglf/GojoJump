`timescale 1ns / 1ps

module enemy_bullet_ctrl #(
    parameter integer ENEMY_WIDTH  = 12,
    parameter integer ENEMY_HEIGHT = 12,
    parameter integer BULLET_SIZE  = 4
)(
    input wire pixel_clk,
    input wire rst,
    input wire move_tick,
    input wire hit_tick,
    input wire [9:0] scroll_dy,

    input wire [9:0] enemy_x,
    input wire signed [10:0] enemy_y,
    input wire enemy_active,

    input wire [3:0] bullet_hit,

    output wire [4*12-1:0] bullet_x_bus,
    output wire [4*12-1:0] bullet_y_bus,
    output reg [3:0] bullet_active
);

    localparam [6:0] FIRST_FIRE_DELAY = 7'd30;
    localparam [6:0] FIRE_CD = 7'd60;
    localparam signed [11:0] BULLET_STEP = 12'sd3;
    localparam integer X_CANVAS = 640;
    localparam integer Y_CANVAS = 480;

    reg signed [11:0] bullet_x [0:3];
    reg signed [11:0] bullet_y [0:3];
    reg [6:0] fire_timer;

    wire fire_now;
    wire enemy_fully_visible;
    wire signed [11:0] scroll_step;
    wire signed [11:0] enemy_y_after_scroll;

    assign scroll_step = $signed({2'b00, scroll_dy});
    assign enemy_y_after_scroll = enemy_y + scroll_step;
    assign enemy_fully_visible = (enemy_y_after_scroll >= 12'sd0) &&
                                 (enemy_y_after_scroll + ENEMY_HEIGHT <= Y_CANVAS);

    assign fire_now = move_tick &&
                      enemy_active &&
                      enemy_fully_visible &&
                      (fire_timer == 7'd0) &&
                      (bullet_active == 4'b0000);

    always @(posedge pixel_clk) begin : update_bullets
        integer i;
        reg signed [11:0] next_x;
        reg signed [11:0] next_y;

        if (rst) begin
            bullet_active <= 4'b0000;
            fire_timer <= FIRST_FIRE_DELAY;
        end else if (hit_tick) begin
            for(i = 0; i < 4; i = i + 1) begin
                if(bullet_hit[i]) begin
                    bullet_active[i] <= 1'b0;
                end
            end
        end else if (move_tick) begin
            // Slots run from upper left through lower left, lower right and upper right.
            for (i = 0; i < 4; i = i + 1) begin
                if (bullet_active[i]) begin
                    next_x = bullet_x[i] + ((i < 2) ? -BULLET_STEP : BULLET_STEP);
                    next_y = bullet_y[i] + scroll_step +
                             ((i == 0 || i == 3) ? -BULLET_STEP : BULLET_STEP);

                    if ((next_x + BULLET_SIZE <= 0) || (next_x >= X_CANVAS) ||
                        (next_y + BULLET_SIZE <= 0) || (next_y >= Y_CANVAS)) begin
                        bullet_active[i] <= 1'b0;
                    end else begin
                        bullet_x[i] <= next_x;
                        bullet_y[i] <= next_y;
                    end
                end
            end

            if (!enemy_active || !enemy_fully_visible) begin
                fire_timer <= FIRST_FIRE_DELAY;
            end else if (fire_now) begin
                fire_timer <= FIRE_CD;
                bullet_active <= 4'b1111;
                bullet_x[0] <= enemy_x;
                bullet_y[0] <= enemy_y_after_scroll;
                bullet_x[1] <= enemy_x;
                bullet_y[1] <= enemy_y_after_scroll + ENEMY_HEIGHT - BULLET_SIZE;
                bullet_x[2] <= enemy_x + ENEMY_WIDTH - BULLET_SIZE;
                bullet_y[2] <= enemy_y_after_scroll + ENEMY_HEIGHT - BULLET_SIZE;
                bullet_x[3] <= enemy_x + ENEMY_WIDTH - BULLET_SIZE;
                bullet_y[3] <= enemy_y_after_scroll;
            end else if (fire_timer != 7'd0) begin
                fire_timer <= fire_timer - 7'd1;
            end
        end 
    end

    genvar slot;
    generate
        for (slot = 0; slot < 4; slot = slot + 1) begin : gen_bullet_bus
            assign bullet_x_bus[slot*12 +: 12] = bullet_x[slot];
            assign bullet_y_bus[slot*12 +: 12] = bullet_y[slot];
        end
    endgenerate
endmodule
