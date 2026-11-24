`timescale 1ns / 1ps

module enemy_ctrl #(
    parameter integer ENEMY_COUNT = 3,
    parameter integer Y_CANVAS = 480,
    parameter integer X_CANVAS = 640,
    parameter integer BIRTHPLACE_Y = -24,
    parameter integer ENEMY_WIDTH = 12,
    parameter integer ENEMY_HEIGHT = 12,
    parameter [15:0] START_SCORE = 16'd800
)(
    input wire pixel_clk,
    input wire rst,
    input wire move_tick,
    input wire pause_game,
    input wire [15:0] score,
    input wire [9:0] scroll_dy,
    input wire [ENEMY_COUNT-1:0] kill_enemy,

    output wire [ENEMY_COUNT*10-1:0] enemy_x_bus,
    output wire [ENEMY_COUNT*11-1:0] enemy_y_bus,
    output reg [ENEMY_COUNT-1:0] enemy_active
);

    localparam integer SLOT_INDEX_WIDTH = $clog2(ENEMY_COUNT);
    localparam integer X_MAX = X_CANVAS - ENEMY_WIDTH;
    localparam integer Y_MAX = Y_CANVAS - ENEMY_HEIGHT;
    localparam integer PAD_X = 180;
    localparam integer PAD_Y = 100;
    localparam [9:0] SPAWN_WAIT_FRAMES = 10'd120;
    localparam [2:0] PICK = 3'd0;
    localparam [2:0] PREPARE = 3'd1;
    localparam [2:0] SCAN = 3'd2;
    localparam [2:0] DECIDE = 3'd3;
    localparam [2:0] WAIT = 3'd4;
    localparam [2:0] FAIL = 3'd5;

    integer i;

    wire scroll_now;
    wire need_enemy;
    wire [15:0] next_rng;

    reg [2:0] next_state;
    reg [2:0] state;
    reg [9:0] enemy_x [ENEMY_COUNT-1:0];
    reg signed [10:0] enemy_y [ENEMY_COUNT-1:0] ;
    reg [15:0] spawn_rng;
    reg [15:0] first_rng;
    reg [9:0] waiting_tick;
    reg free_valid;
    reg [SLOT_INDEX_WIDTH-1:0] free_slot;
    reg [9:0] candidate_x;
    reg generate_ok;
    reg signed [10:0] y_after_scroll;
    reg [SLOT_INDEX_WIDTH-1:0] target_slot;
    reg block;

    assign scroll_now = move_tick && (scroll_dy != 10'd0);
    assign need_enemy = (score >= START_SCORE) && (waiting_tick == SPAWN_WAIT_FRAMES);
    assign next_rng ={spawn_rng[14:0], spawn_rng[15]^spawn_rng[13]^spawn_rng[12]^spawn_rng[10]};

    always @* begin : find_free_slot
        integer slot;
        free_valid = 1'b0;
        free_slot = 0;
        for (slot = 0; slot < ENEMY_COUNT; slot = slot + 1) begin
            if(!free_valid && !enemy_active[slot]) begin
                free_valid = 1'b1;
                free_slot = slot;
            end
        end
    end

    always @* begin : calculate_candidate
        candidate_x = 10'd64 + {1'b0, spawn_rng[8:0]};
    end

    always @* begin : check_scan_slot
        integer scan_slot;
        block = 1'b0;
        for(scan_slot = 0; scan_slot < ENEMY_COUNT; scan_slot = scan_slot + 1) begin
            if (enemy_active[scan_slot] &&
                (candidate_x < enemy_x[scan_slot] + ENEMY_WIDTH + PAD_X) &&
                (enemy_x[scan_slot] < candidate_x + ENEMY_WIDTH + PAD_X) &&
                (BIRTHPLACE_Y < enemy_y[scan_slot] + ENEMY_HEIGHT + PAD_Y) &&
                (enemy_y[scan_slot] < BIRTHPLACE_Y + ENEMY_HEIGHT + PAD_Y)) begin
                block = 1'b1;
            end
        end
    end

    always @* begin: select_next_state
        next_state = state;
        if(scroll_now) begin
            next_state = PICK;
        end else begin
            case(state)
                PICK: begin
                    if(!need_enemy) begin
                        next_state = WAIT;
                    end else if(free_valid) begin
                        next_state = PREPARE;
                    end else begin

                    end
                end
                WAIT: begin
                    if (need_enemy && free_valid) begin
                        next_state = PICK;
                    end
                end
                PREPARE: begin
                    next_state = SCAN;
                end
                SCAN: begin
                    if(generate_ok && !block) begin
                        next_state = PICK;
                    end else if(first_rng != next_rng) begin
                        next_state = PREPARE;
                    end else begin
                        next_state = FAIL;
                    end
                end
            endcase
        end
    end

    always @(posedge pixel_clk) begin
        if(rst) begin
            spawn_rng <= 16'hA1C5;
            enemy_active <= {ENEMY_COUNT{1'b0}};
            state <= PICK;
            waiting_tick <= 10'd0;
        end else if(!pause_game) begin
            state <= next_state;
            if(move_tick && waiting_tick < SPAWN_WAIT_FRAMES) begin
                waiting_tick <= waiting_tick + 10'd1;
            end
            if(scroll_now) begin
                for(i = 0; i < ENEMY_COUNT; i = i + 1) begin
                    if(enemy_active[i]) begin
                        y_after_scroll = enemy_y[i] + scroll_dy;
                        if(y_after_scroll >= Y_CANVAS) begin
                            enemy_active[i] <= 1'b0;
                        end else begin
                            enemy_y[i] <= y_after_scroll;
                        end
                    end
                end
            end else begin
                case(state)
                    PICK: begin
                        if(need_enemy && free_valid) begin
                            target_slot <= free_slot;
                            first_rng <= spawn_rng;
                        end
                    end
                    PREPARE: begin
                        generate_ok <= ((candidate_x >=0) && (candidate_x) <= X_MAX);
                    end
                    SCAN: begin
                        spawn_rng <= next_rng;
                        if(generate_ok && !block) begin
                            enemy_x[target_slot] <= candidate_x;
                            enemy_y[target_slot] <= BIRTHPLACE_Y;
                            enemy_active[target_slot] <= 1'b1;
                            waiting_tick <= 10'd0;
                        end
                    end
                endcase
            end
            for (i = 0; i < ENEMY_COUNT; i = i + 1) begin
                if(kill_enemy[i]) begin
                    enemy_active[i] <= 1'b0;
                end
            end
        end
    end

    genvar g;
    generate
        for(g = 0; g < ENEMY_COUNT; g = g + 1) begin : gen_enemy_bus
            assign enemy_x_bus[g*10 +: 10] = enemy_x[g];
            assign enemy_y_bus[g*11 +: 11] = enemy_y[g];
        end
    endgenerate
endmodule
