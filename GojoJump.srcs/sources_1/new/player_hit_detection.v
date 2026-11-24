`timescale 1ns / 1ps

module player_hit_detection #(
    parameter integer PLAYER_WIDTH = 16,
    parameter integer PLAYER_HEIGHT = 16,
    parameter integer ENEMY_COUNT = 3,
    parameter integer ENEMY_WIDTH = 12,
    parameter integer ENEMY_HEIGHT = 12,
    parameter integer BULLET_COUNT = ENEMY_COUNT * 4,
    parameter integer BULLET_SIZE = 4,
    parameter ENABLE_PURPLE_COLLISION = 1'b1,
    parameter signed [11:0] PURPLE_DIAMETER = 12'sd128,
    parameter signed [11:0] ATTACK_PAD_X = 12'sd20,
    parameter signed [11:0] ATTACK_PAD_Y = 12'sd20
)(
    input wire [9:0] player_x,
    input wire [9:0] player_y,
    input wire attack_tick,
    input wire purple_hit_tick,
    input wire [9:0] purple_x,
    input wire signed [11:0] purple_y,

    input wire [ENEMY_COUNT*10-1:0] enemy_x_bus,
    input wire [ENEMY_COUNT*11-1:0] enemy_y_bus,
    input wire [ENEMY_COUNT-1:0] enemy_active,

    input wire [BULLET_COUNT*12-1:0] bullet_x_bus,
    input wire [BULLET_COUNT*12-1:0] bullet_y_bus,
    input wire [BULLET_COUNT-1:0] bullet_active,

    output wire hit_player,
    output wire [BULLET_COUNT-1:0] bullet_hit,
    output wire [ENEMY_COUNT-1:0] melee_hit,
    output wire [ENEMY_COUNT-1:0] purple_hit
);
    localparam integer ATTACK_WIDTH = PLAYER_WIDTH + 2 * ATTACK_PAD_X;
    localparam integer ATTACK_HEIGHT = PLAYER_HEIGHT + 2 * ATTACK_PAD_Y;
    localparam signed [11:0] PURPLE_RADIUS = PURPLE_DIAMETER >>> 1;
    localparam integer PURPLE_GAP_WIDTH = $clog2(PURPLE_RADIUS + 1);
    localparam [2*PURPLE_GAP_WIDTH:0] PURPLE_RADIUS_SQUARED = PURPLE_RADIUS * PURPLE_RADIUS;

    wire signed [11:0] player_left = $signed({2'b00, player_x});
    wire signed [11:0] player_top = $signed({2'b00, player_y});
    wire signed [11:0] attack_left = player_left - ATTACK_PAD_X;
    wire signed [11:0] attack_top = player_top - ATTACK_PAD_Y;
    wire signed [11:0] purple_center_x = $signed({2'b00, purple_x});
    wire signed [11:0] purple_center_y = purple_y + PURPLE_RADIUS;
    wire [ENEMY_COUNT-1:0] enemy_hit;

    function overlap;
        input signed [11:0] ax, ay;
        input integer aw, ah;
        input signed [11:0] bx, by;
        input integer bw, bh;
        begin
            overlap = (ax < bx + bw) &&
                      (bx < ax + aw) &&
                      (ay < by + bh) &&
                      (by < ay + ah);
        end
    endfunction

    function [11:0] gap_to_interval;
        input signed [11:0] point, low, high;
        begin
            if (point < low)
                gap_to_interval = low - point;
            else if (point > high)
                gap_to_interval = point - high;
            else
                gap_to_interval = 12'd0;
        end
    endfunction

    genvar enemy_index, bullet_index;
    generate
        for (enemy_index = 0; enemy_index < ENEMY_COUNT; enemy_index = enemy_index + 1) begin : gen_enemy_hit
            wire signed [11:0] x;
            wire signed [11:0] y;

            assign x = $signed({2'b00, enemy_x_bus[enemy_index*10 +: 10]});
            assign y = $signed(enemy_y_bus[enemy_index*11 +: 11]);
            assign enemy_hit[enemy_index] =
                enemy_active[enemy_index] &&
                overlap(player_left, player_top, PLAYER_WIDTH, PLAYER_HEIGHT,
                        x, y, ENEMY_WIDTH, ENEMY_HEIGHT);
            assign melee_hit[enemy_index] =
                attack_tick && enemy_active[enemy_index] &&
                overlap(attack_left, attack_top, ATTACK_WIDTH, ATTACK_HEIGHT,
                        x, y, ENEMY_WIDTH, ENEMY_HEIGHT);
            if (ENABLE_PURPLE_COLLISION) begin : gen_purple_collision
                wire signed [11:0] right_edge = x + ENEMY_WIDTH - 1;
                wire signed [11:0] bottom_edge = y + ENEMY_HEIGHT - 1;
                wire signed [11:0] visible_top = (y < 0) ? 12'sd0 : y;
    
                // Distance from the orb center to the nearest visible point on the enemy.
                wire [11:0] gap_x = gap_to_interval(purple_center_x, x, right_edge);
                wire [11:0] gap_y = gap_to_interval(purple_center_y, visible_top, bottom_edge);
                wire [PURPLE_GAP_WIDTH-1:0] dx = gap_x[PURPLE_GAP_WIDTH-1:0];
                wire [PURPLE_GAP_WIDTH-1:0] dy = gap_y[PURPLE_GAP_WIDTH-1:0];
                wire [2*PURPLE_GAP_WIDTH-1:0] dx_squared = dx * dx;
                wire [2*PURPLE_GAP_WIDTH-1:0] dy_squared = dy * dy;
                wire [2*PURPLE_GAP_WIDTH:0] distance_squared = {1'b0, dx_squared} + {1'b0, dy_squared};

                assign purple_hit[enemy_index] =
                    purple_hit_tick && enemy_active[enemy_index] && (bottom_edge >= 12'sd0) &&
                    (gap_x <= PURPLE_RADIUS) && (gap_y <= PURPLE_RADIUS) &&
                    (distance_squared <= PURPLE_RADIUS_SQUARED);
            end else begin : gen_no_purple_collision
                assign purple_hit[enemy_index] = 1'b0;
            end
        end

        for (bullet_index = 0; bullet_index < BULLET_COUNT; bullet_index = bullet_index + 1) begin : gen_bullet_hit
            wire signed [11:0] x;
            wire signed [11:0] y;

            assign x = $signed(bullet_x_bus[bullet_index*12 +: 12]);
            assign y = $signed(bullet_y_bus[bullet_index*12 +: 12]);
            assign bullet_hit[bullet_index] =
                bullet_active[bullet_index] &&
                overlap(player_left, player_top, PLAYER_WIDTH, PLAYER_HEIGHT,
                        x, y, BULLET_SIZE, BULLET_SIZE);
        end
    endgenerate

    assign hit_player = (|enemy_hit) || (|bullet_hit);
endmodule
