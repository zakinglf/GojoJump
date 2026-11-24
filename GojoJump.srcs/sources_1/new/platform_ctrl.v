`timescale 1ns / 1ps

module platform_ctrl #(
    parameter integer PLATFORM_COUNT = 10,
    parameter integer INITIAL_BOTTOM_Y = 440,
    parameter integer INITIAL_Y_GAP = 30,
    parameter integer INITIAL_WIDTH = 64,
    parameter integer INITIAL_HEIGHT = 4,
    parameter integer INITIAL_X_GAP = 40,
    parameter integer INITIAL_X = 280,
    parameter integer Y_CANVAS = 480,
    parameter integer X_CANVAS = 640,
    parameter integer SLOT_INDEX_WIDTH = (PLATFORM_COUNT > 1) ? $clog2(PLATFORM_COUNT) : 1
)(
    input wire pixel_clk,
    input wire rst,
    input wire move_prepare,
    input wire move_tick,
    input wire pause_game,
    input wire [9:0] scroll_dy,
    input wire platform_reward_claimed,
    input wire [SLOT_INDEX_WIDTH-1:0] platform_reward_index,

    output wire [PLATFORM_COUNT*10-1:0] platform_x_bus,
    output wire [PLATFORM_COUNT*10-1:0] platform_y_bus,
    output wire [PLATFORM_COUNT*10-1:0] platform_width_bus,
    output wire [PLATFORM_COUNT-1:0] platform_active,
    output reg [PLATFORM_COUNT-1:0] platform_reward_ready,
    output reg layout_ready
);
    localparam integer X_MAX = X_CANVAS - INITIAL_WIDTH;
    localparam integer Y_MAX = Y_CANVAS - INITIAL_HEIGHT;
    localparam integer OPENING_TOP_Y = 50;
    localparam integer PAD_X = 20;
    localparam integer PAD_Y = 24;
    localparam [2:0] PICK = 3'd0;
    localparam [2:0] PREPARE = 3'd1;
    localparam [2:0] SCAN = 3'd2;
    localparam [2:0] DECIDE = 3'd3;
    localparam [2:0] WAIT_FRAME = 3'd4;
    localparam [2:0] GENERATION_FAILED = 3'd5;
    localparam [2:0] BRANCH_PICK= 3'd6;

    integer i;
    integer slot;
    integer y_after_scroll;
    integer candidate_x;
    integer alternate_x;
    integer candidate_y;

    reg [SLOT_INDEX_WIDTH-1:0] front [0:2];
    reg [1:0] route_id [PLATFORM_COUNT-1:0];

    // Store the position, width, and status of each platform.
    reg [9:0] platform_x [0:PLATFORM_COUNT-1];
    reg [9:0] platform_y [0:PLATFORM_COUNT-1];
    reg [9:0] platform_width [0:PLATFORM_COUNT-1];
    reg [PLATFORM_COUNT-1:0] active;
    reg [7:0] rng;
    reg [7:0] reward_rng;
    reg [7:0] first_rng;
    wire [7:0] next_rng;
    reg free_valid;
    reg [SLOT_INDEX_WIDTH-1:0] free_slot;
    reg [2:0] state;
    reg [2:0] next_state;
    reg [1:0] selected_route;
    reg [1:0] route_to_extent;
    reg [SLOT_INDEX_WIDTH-1:0] target_slot;
    reg preferred_ok;
    reg alternate_ok;
    reg [SLOT_INDEX_WIDTH-1:0] scan_slot;
    reg blocks_preferred;
    reg blocks_alternate;
    reg [2:0] route_enabled;
    reg route_found;
    reg [2:0] reusable_route;
    reg [SLOT_INDEX_WIDTH-1:0] source_slot;

    wire scroll_now;
    wire need_platform;
    wire [2:0] other_enabled;
    wire retire_route;
    wire making_branch;


    assign scroll_now = layout_ready && move_tick && (scroll_dy != 10'd0);
    assign need_platform = route_found && (platform_y[front[selected_route]] > OPENING_TOP_Y);
    assign next_rng = {rng[6:0], rng[7]^rng[5]^rng[4]^rng[3]};
    assign other_enabled = route_enabled & ~(3'b001 << route_to_extent);
    assign retire_route = layout_ready && !making_branch
                          && !(preferred_ok || alternate_ok) 
                          && (next_rng == first_rng) && (|other_enabled);
    assign making_branch = !(route_enabled[route_to_extent]);


    always @* begin : find_free_slot
        free_valid = 1'b0;
        free_slot = 0;
        for (slot = 0; slot < PLATFORM_COUNT; slot = slot + 1) begin
            if(!free_valid && !active[slot]) begin
                free_valid = 1'b1;
                free_slot = slot;
            end
        end
    end


    always @* begin : select_route
        integer r;

        selected_route = 2'd0;
        route_found = 1'd0;
        for (r = 0; r < 3; r = r + 1) begin
            if(route_enabled[r]) begin
                if(!route_found || (platform_y[front[selected_route]] < platform_y[front[r]])) begin
                    selected_route = r;
                    route_found = 1'b1;
                end
            end
        end
    end

    always @* begin : calculate_candidate
        integer source_x;
        integer source_y;
        integer height_gap;
        integer edge_gap;
        integer step_x;

        source_x = platform_x[source_slot];
        source_y = platform_y[source_slot];

        // Preserve a candidate that cannot be blocked by lower platforms.
        if (rng == 8'h80) begin
            height_gap = 28;
            edge_gap   = 20;
        end else begin
            height_gap = 32 + rng[3:0];  // 32 to 47 pixels
            edge_gap   = 40 + rng[7:2];  // 24 to 87 pixels
        end
        step_x = INITIAL_WIDTH + edge_gap;
        if(rng[4]) begin
            step_x = -step_x;
        end    
        candidate_x = source_x + step_x;
        candidate_y = source_y - height_gap;
        alternate_x = source_x - step_x;
    end

    always @* begin: check_scan_slot
        integer old_x;
        integer old_y;
        integer old_width;

        old_x = platform_x[scan_slot];
        old_y = platform_y[scan_slot];
        old_width = platform_width[scan_slot];

        blocks_alternate = 1'b0;
        blocks_preferred = 1'b0;

        if((active[scan_slot]) 
          && (route_id[scan_slot] != 2'd3) 
          && (route_id[scan_slot] != route_to_extent) 
          && (candidate_y < old_y + INITIAL_HEIGHT + PAD_Y) 
          && (candidate_y + INITIAL_HEIGHT > old_y - PAD_Y))begin
            if(preferred_ok && (candidate_x < old_x + old_width + PAD_X) && (candidate_x + old_width > old_x - PAD_X )) begin
                blocks_preferred = 1'b1;
            end
            if((alternate_ok && alternate_x < old_x + old_width + PAD_X) && (alternate_x + old_width > old_x - PAD_X)) begin
                blocks_alternate = 1'b1;
            end
        end
    end

    always @* begin : select_next_state
        next_state = state;
        if(scroll_now) begin
            next_state = PICK;
        end else begin
            case(state)
                PICK: begin
                    if(!need_platform) begin
                        next_state = WAIT_FRAME;
                    end else if(free_valid) begin
                        next_state = PREPARE;
                    end else begin
                        next_state = layout_ready ? WAIT_FRAME : GENERATION_FAILED;
                    end
                end 
                PREPARE: begin
                    next_state = SCAN;
                end
                SCAN: begin
                    if((scan_slot == PLATFORM_COUNT - 1)
                       || ((!preferred_ok || blocks_preferred) && (!alternate_ok || blocks_alternate))) begin
                        next_state = DECIDE;
                    end
                end
                DECIDE: begin
                    if(preferred_ok || alternate_ok) begin
                        if(!making_branch && |reusable_route) begin
                            next_state = BRANCH_PICK;
                        end else begin
                            next_state = PICK;
                        end
                    end else if (next_rng != first_rng) begin
                        next_state = PREPARE;
                    end else if (making_branch || retire_route) begin
                        next_state = PICK;
                    end else begin
                        next_state = GENERATION_FAILED;
                    end
                end
                BRANCH_PICK: begin
                    if(free_valid) begin
                        next_state = PREPARE;
                    end else begin
                        next_state = PICK;
                    end
                end
            endcase
        end
    end

    always @(posedge pixel_clk) begin : update_platforms
        if (rst) begin
            layout_ready <= 1'b0;
            front[0] <= 1;
            front[1] <= 2;
            front[2] <= 3;
            route_enabled <= 3'b111;
            rng <= 8'hA1;
            reward_rng <= 8'hD3;
            platform_reward_ready <= 0;
            reusable_route <= 3'b000;
            state <= PICK;
            for (i = 0; i < PLATFORM_COUNT; i = i + 1) begin
                active[i] <= (i < 4);
                platform_width[i] <= INITIAL_WIDTH;

                case(i)
                    0: begin
                        platform_x[i] <= INITIAL_X;
                        platform_y[i] <= INITIAL_BOTTOM_Y;
                        route_id[i] <= 2'd3;
                    end
                    1: begin
                        platform_x[i] <= INITIAL_X - 60;
                        platform_y[i] <= INITIAL_BOTTOM_Y - 28;
                        route_id[i] <= 2'd0;
                    end
                    2: begin
                        platform_x[i] <= INITIAL_X;
                        platform_y[i] <= INITIAL_BOTTOM_Y -24;
                        route_id[i] <= 2'd1;
                    end
                    3: begin
                        platform_x[i] <= INITIAL_X + 60;
                        platform_y[i] <= INITIAL_BOTTOM_Y - 32;
                        route_id[i] <= 2'd2;
                    end
                    default: begin
                        platform_x[i] <= 0;
                        platform_y[i] <= 0;
                        route_id[i] <= 2'd3;
                    end
                endcase
            end
        end else if (!pause_game && !move_prepare) begin
            // Keep platform coordinates fixed until collision is evaluated.
            state <= next_state;
            if (platform_reward_claimed) begin
                platform_reward_ready[platform_reward_index] <= 1'b0;
            end
            if(scroll_now) begin
                for(i = 0; i < PLATFORM_COUNT; i = i + 1) begin
                    if(active[i]) begin
                        y_after_scroll = platform_y[i] + scroll_dy;
                        if(y_after_scroll >= Y_CANVAS) begin
                            active[i] <= 1'b0;
                            platform_reward_ready[i] <= 1'b0;
                        end else begin
                            platform_y[i] <= y_after_scroll;
                        end
                    end
                end
            end else begin
                case(state)
                    PICK: begin
                        if(!need_platform) begin
                            layout_ready <= 1'd1;
                        end else if(free_valid) begin
                            route_to_extent <= selected_route;
                            source_slot <= front[selected_route];
                            target_slot <= free_slot;
                            first_rng <= rng;
                            reusable_route <= ~route_enabled;
                        end
                    end
                    PREPARE: begin
                        preferred_ok = (candidate_x >= 0) && (candidate_x <= X_MAX) && (candidate_y >= 0) && (candidate_y <= Y_MAX);
                        alternate_ok = (alternate_x >= 0) && (alternate_x <= X_MAX) && (candidate_y >= 0) && (candidate_y <= Y_MAX);
                        scan_slot <= 0;
                    end 
                    SCAN: begin
                        if(blocks_alternate) begin
                            alternate_ok <= 1'b0;
                        end
                        if(blocks_preferred) begin
                            preferred_ok <= 1'b0;
                        end
                        if(scan_slot < PLATFORM_COUNT - 1) begin
                            scan_slot <= scan_slot + 1;
                        end
                        if(active[scan_slot] && route_id[scan_slot] < 2'd3) begin
                            reusable_route[route_id[scan_slot]] <= 1'b0;
                        end
                    end
                    DECIDE: begin
                        rng <= next_rng;
                        if(preferred_ok || alternate_ok) begin
                            platform_x[target_slot] <= preferred_ok ? candidate_x[9:0] : alternate_x[9:0];
                            platform_y[target_slot] <= candidate_y;
                            platform_width[target_slot] <= INITIAL_WIDTH;
                            active[target_slot] <= 1'b1;
                            // Roll once per accepted platform, independently of layout retries.
                            platform_reward_ready[target_slot] <= (reward_rng[3:0] == 4'b0110);
                            // Include zero in the reward sequence for 16 hits per 256 placements.
                            reward_rng <= {reward_rng[6:0],
                                           reward_rng[7] ^ reward_rng[5] ^ reward_rng[4] ^
                                           reward_rng[3] ^ (reward_rng[6:0] == 7'd0)};
                            route_id[target_slot] <= route_to_extent;
                            front[route_to_extent] <= target_slot;
                            route_enabled[route_to_extent] <= 1'b1;
                        end else if (retire_route) begin
                            route_enabled[route_to_extent] <= 1'b0;
                        end
                    end
                    BRANCH_PICK: begin
                        if(free_valid) begin
                            if(reusable_route[0]) begin
                                route_to_extent <= 2'd0;
                            end else if (reusable_route[1]) begin
                                route_to_extent <= 2'd1;
                            end else begin
                                route_to_extent <= 2'd2;
                            end
                            target_slot <= free_slot;
                            first_rng <= rng;
                        end
                    end
                endcase
            end
        end
    end

    // Pack each platform into a 10-bit slice of the output buses.
    genvar g;
    generate
        for (g = 0; g < PLATFORM_COUNT; g = g + 1) begin : gen_platform_bus
            assign platform_x_bus[g*10 +: 10] = platform_x[g];
            assign platform_y_bus[g*10 +: 10] = platform_y[g];
            assign platform_width_bus[g*10 +: 10] = platform_width[g];
        end
    endgenerate

    assign platform_active = active;
endmodule
