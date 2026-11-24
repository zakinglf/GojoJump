`timescale 1ns / 1ps

module player_ctrl #(
    parameter integer PLATFORM_COUNT = 10,
    parameter integer PLAYER_WIDTH = 16,
    parameter integer PLAYER_HEIGHT = 16,
    parameter integer START_X = 100,
    parameter integer START_Y = 200,
    parameter integer MOVE_STEP = 1,
    parameter signed [15:0] GRAVITY_FP = 16'sd4,
    parameter signed [15:0] JUMP_VELOCITY_FP = -16'sd72,
    parameter integer SCROLL_LINE_Y = 320,
    parameter integer DASH_STEP = 6,
    parameter integer DASH_FRAME = 5,
    parameter integer DASH_COOLDOWN = 18,
    parameter integer PLATFORM_INDEX_WIDTH = (PLATFORM_COUNT > 1) ? $clog2(PLATFORM_COUNT) : 1
) (
    input wire pixel_clk,
    input wire rst,
    input wire move_prepare,
    input wire move_tick,
    input wire pause_game,
    input wire move_left,
    input wire move_right,
    input wire jump_pressed,
    input wire dash_pressed,
    input wire black_flash_hit,

    input wire [PLATFORM_COUNT * 10 - 1:0] platform_x_bus,
    input wire [PLATFORM_COUNT * 10 - 1:0] platform_y_bus,
    input wire [PLATFORM_COUNT * 10 - 1:0] platform_width_bus,
    input wire [PLATFORM_COUNT - 1:0] platform_active,

    output reg [9:0] player_x,
    output wire [9:0] player_y,
    output wire [9:0] scroll_dy,
    output wire fell_off_screen,
    output wire on_ground_before_move,
    output reg landed_on_platform,
    output reg [PLATFORM_INDEX_WIDTH-1:0] landed_platform_index
);

    // Fixed-point values: 16 units represent one pixel.
    localparam integer X_MAX = 640 - PLAYER_WIDTH;
    localparam signed [15:0] START_Y_FP = START_Y * 16;
    localparam signed [15:0] PLAYER_HEIGHT_FP = PLAYER_HEIGHT * 16;
    localparam signed [15:0] SCROLL_LINE_FP = SCROLL_LINE_Y * 16;
    localparam signed [15:0] SCREEN_BOTTOM_FP = 480 * 16;
    localparam [1:0] COYOTE_TICKS = 2'd2;
    localparam [1:0] DASH_COYOTE_TICKS = 2'd1;
    localparam [2:0] JUMP_BUFFER_TICKS = 3'd5;

    reg signed [15:0] y_fp;
    reg signed [15:0] vy_fp;
    wire signed [15:0] next_y_fp;
    wire signed [15:0] next_vy_fp;
    wire signed [15:0] feet_fp;
    wire signed [15:0] next_feet_fp;
    wire falling;
    reg [9:0] next_player_x;
    wire landed;
    wire [9:0] landing_y;
    wire [PLATFORM_INDEX_WIDTH-1:0] landing_platform_index;
    wire signed [15:0] landing_top_fp;
    wire supported;
    wire on_ground;
    wire jump_pending;
    wire signed [15:0] scroll_gap_fp;
    wire signed [15:0] scroll_offset_fp;
    reg [1:0] jump_coyote_left;
    reg [2:0] jump_buffer_left;
    wire jump_now;
    reg air_jump;
    wire air_jump_now;
    reg dash_pending;
    wire dash_now;
    wire air_dash_now;
    reg air_dash_available;
    reg signed [3:0] dash_frame_left;
    reg [4:0] dash_cooldown_left;
    reg [1:0] dash_coyote_left;
    wire supported_before_move;
    wire dash_can_start;
    wire ground_dash_eligible;
    wire dash_in_progress;
    wire step_left;
    wire step_right;
    wire [9:0] x_step;
    wire hold_y;
    reg dash_refresh_pending;
    wire dash_refresh_now;

    wire [9:0] next_scroll_dy;
    reg [9:0] prepared_x;
    reg [9:0] prepared_scroll_dy;
    reg prepared_hold_y;
    reg prepared_dash_start;
    reg prepared_air_dash;
    reg prepared_dash_right;
    reg prepared_on_ground_before_move;
    reg prepared_jump_request;
    reg prepared_jump_pressed;

    assign dash_refresh_now = !dash_in_progress && (black_flash_hit || dash_refresh_pending);

    assign fell_off_screen = (y_fp >= SCREEN_BOTTOM_FP);

    assign player_y = y_fp[13:4];

    // Predict vertical motion for the next movement tick.
    assign next_y_fp = y_fp + vy_fp;
    assign next_vy_fp = vy_fp + GRAVITY_FP;

    // Calculate the current and predicted positions of the player's feet.
    assign feet_fp = y_fp + PLAYER_HEIGHT_FP;
    assign next_feet_fp = next_y_fp + PLAYER_HEIGHT_FP;
    assign falling = !prepared_hold_y && (vy_fp > 16'sd0);

    // Standing requires platform support and zero vertical velocity.
    assign on_ground = !prepared_hold_y && supported && (vy_fp == 16'sd0);

    // Calculate how far the predicted position exceeds the scroll line.
    assign scroll_gap_fp = SCROLL_LINE_FP - next_y_fp;

    // Scroll upward only; round the required distance up to whole pixels.
    assign next_scroll_dy =
        (!rst && !hold_y && (vy_fp < 16'sd0) && (scroll_gap_fp > 16'sd0))
        ? ((scroll_gap_fp + 16'sd15) >>> 4)
        : 10'd0;

    assign scroll_dy = prepared_scroll_dy;

    // Convert the camera movement to fixed-point units.
    assign scroll_offset_fp = $signed({2'b00, scroll_dy, 4'b0000});

    assign landing_top_fp = $signed({2'b00, landing_y, 4'b0000});

    assign jump_pending = (jump_buffer_left != 3'd0);
    assign jump_now = !landed && !prepared_hold_y &&
                      prepared_jump_request &&
                      (on_ground || jump_coyote_left != 2'd0);
    assign air_jump_now = !landed && !jump_now && !prepared_hold_y &&
                          air_jump && prepared_jump_request;

    assign on_ground_before_move = supported_before_move && (vy_fp == 16'sd0);
    assign dash_can_start = (dash_pending || dash_pressed) &&
                            (dash_frame_left == 0) &&
                            (dash_cooldown_left == 0) &&
                            (move_right ^ move_left);
    assign ground_dash_eligible = on_ground_before_move ||
                                  (dash_coyote_left != 2'd0);
    assign dash_now = dash_can_start && ground_dash_eligible;
    assign air_dash_now = dash_can_start &&
                         !ground_dash_eligible &&
                         air_dash_available;

    assign hold_y = air_dash_now || (dash_in_progress && !air_dash_available);

    // Capture movement before checking landing and committing the shared frame.
    always @(posedge pixel_clk) begin
        if (rst) begin
            prepared_x <= START_X;
            prepared_scroll_dy <= 10'd0;
            prepared_hold_y <= 1'b0;
            prepared_dash_start <= 1'b0;
            prepared_air_dash <= 1'b0;
            prepared_dash_right <= 1'b0;
            prepared_on_ground_before_move <= 1'b0;
            prepared_jump_request <= 1'b0;
            prepared_jump_pressed <= 1'b0;
        end else if (move_prepare) begin
            prepared_x <= next_player_x;
            prepared_scroll_dy <= next_scroll_dy;
            prepared_hold_y <= hold_y;
            prepared_dash_start <= dash_now || air_dash_now;
            prepared_air_dash <= air_dash_now;
            prepared_dash_right <= move_right;
            prepared_on_ground_before_move <= on_ground_before_move;
            prepared_jump_request <= jump_pending || jump_pressed;
            prepared_jump_pressed <= jump_pressed;
        end
    end

    always @(posedge pixel_clk) begin
        if (rst || dash_refresh_now) begin
            dash_refresh_pending <= 1'b0;
        end else if (black_flash_hit) begin
            dash_refresh_pending <= 1'b1;
        end
    end

    always @(posedge pixel_clk) begin
        if (rst) begin
            jump_coyote_left <= 2'd0;
        end else if (move_tick) begin
            if (jump_now) begin
                jump_coyote_left <= 2'd0;
            end else if (landed || on_ground) begin
                jump_coyote_left <= COYOTE_TICKS;
            end else if (jump_coyote_left != 2'd0) begin
                jump_coyote_left <= jump_coyote_left - 2'd1;
            end
        end
    end

    // Keep ground dash available for one tick after walking off a platform.
    always @(posedge pixel_clk) begin
        if (rst) begin
            dash_coyote_left <= 2'd0;
        end else if (move_tick) begin
            if (jump_now || prepared_dash_start) begin
                dash_coyote_left <= 2'd0;
            end else if (!dash_in_progress &&
                         (landed || prepared_on_ground_before_move)) begin
                dash_coyote_left <= DASH_COYOTE_TICKS;
            end else if (dash_coyote_left != 2'd0) begin
                dash_coyote_left <= dash_coyote_left - 2'd1;
            end
        end
    end

    assign dash_in_progress = (dash_frame_left != 4'sd0);

    assign step_left = (dash_frame_left < 4'sd0) ||
                       (!dash_in_progress && move_left && !move_right);
    assign step_right = (dash_frame_left > 4'sd0) ||
                        (!dash_in_progress && move_right && !move_left);

    assign x_step = (dash_now || air_dash_now || dash_in_progress)
                    ? DASH_STEP : MOVE_STEP;

    // Predict horizontal movement and clamp partial steps at the screen edges.
    always @(*) begin
        next_player_x = player_x;

        if (step_left) begin
            next_player_x = (player_x >= x_step)
                            ? player_x - x_step : 10'd0;
        end else if (step_right) begin
            next_player_x = (player_x + x_step <= X_MAX)
                            ? player_x + x_step : X_MAX;
        end
    end

    always @(posedge pixel_clk) begin
        if (rst) begin
            dash_frame_left <= 4'sd0;
            dash_cooldown_left <= 5'd0;
        end else if (move_tick) begin
            if (prepared_dash_start) begin
                // The starting tick counts as the first dash frame.
                dash_frame_left <= prepared_dash_right ? (DASH_FRAME - 1)
                                              : -(DASH_FRAME - 1);
            end else if (dash_frame_left > 4'sd0) begin
                dash_frame_left <= dash_frame_left - 4'sd1;
            end else if (dash_frame_left < 4'sd0) begin
                dash_frame_left <= dash_frame_left + 4'sd1;
            end

            // Start cooldown after the final dash frame.
            if ((dash_frame_left == 4'sd1) ||
                (dash_frame_left == -4'sd1) ||
                (prepared_dash_start && (DASH_FRAME == 1))) begin
                dash_cooldown_left <= DASH_COOLDOWN;
            end else if (dash_cooldown_left != 5'd0) begin
                dash_cooldown_left <= dash_cooldown_left - 5'd1;
            end
        end else if (dash_refresh_now) begin
            dash_cooldown_left <= 5'd0;
        end
    end

    always @(posedge pixel_clk) begin
        landed_on_platform <= 1'b0;
        if (rst) begin
            landed_platform_index <= 0;
            player_x <= START_X;
            y_fp <= START_Y_FP;
            vy_fp <= 16'sd0;
            air_jump <= 1'b0;
        end else if (move_tick) begin
            player_x <= prepared_x;
            if (prepared_hold_y) begin
                vy_fp <= 16'sd0;
                // Keep y_fp unchanged during an air dash.
            end else if (landed) begin
                // Save the selected platform for the following hit tick.
                landed_on_platform <= 1'b1;
                landed_platform_index <= landing_platform_index;
                y_fp <= landing_top_fp - PLAYER_HEIGHT_FP;
                vy_fp <= 16'sd0;
                air_jump <= 1'b0;
            end else if (jump_now) begin
                vy_fp <= JUMP_VELOCITY_FP;
                air_jump <= 1'b1;
            end else if (on_ground) begin
                vy_fp <= 16'd0;
                air_jump <= 1'b0;
            end else if (air_jump_now) begin
                y_fp <= next_y_fp + scroll_offset_fp;
                vy_fp <= JUMP_VELOCITY_FP;
                air_jump <= 1'b0;
            end else begin
                // Continue airborne motion under gravity.
                y_fp <= next_y_fp + scroll_offset_fp;
                vy_fp <= next_vy_fp;
            end
        end else if (black_flash_hit) begin
            air_jump <= 1'b1;
        end
    end

    // Keep an early jump request through the landing tick.
    always @(posedge pixel_clk) begin
        if (rst || pause_game) begin
            jump_buffer_left <= 3'd0;
        end else if (jump_pressed) begin
            jump_buffer_left <= JUMP_BUFFER_TICKS;
        end else if (move_tick) begin
            if (jump_now || air_jump_now)
                jump_buffer_left <= 3'd0;
            else if (prepared_jump_pressed)
                jump_buffer_left <= JUMP_BUFFER_TICKS;
            else if (!landed && jump_buffer_left != 3'd0)
                jump_buffer_left <= jump_buffer_left - 3'd1;
        end
    end

    always @(posedge pixel_clk) begin
        if (rst || pause_game || move_prepare) begin
            dash_pending <= 1'b0;
        end else if (dash_pressed && !dash_in_progress &&
                     (dash_cooldown_left == 5'd0) &&
                     !(move_tick && prepared_dash_start)) begin
            dash_pending <= 1'b1;
        end
    end

    always @(posedge pixel_clk) begin
        if (rst) begin
            air_dash_available <= 1'b1;
        end else begin
            if (!pause_game && move_tick) begin
                if (prepared_air_dash)
                    air_dash_available <= 1'b0;
                else if (!dash_in_progress && (landed || prepared_on_ground_before_move))
                    air_dash_available <= 1'b1;
            end

            if (dash_refresh_now)
                air_dash_available <= 1'b1;
        end
    end

    platform_collision #(
        .PLATFORM_COUNT(PLATFORM_COUNT),
        .PLAYER_WIDTH(PLAYER_WIDTH),
        .PLATFORM_INDEX_WIDTH(PLATFORM_INDEX_WIDTH)
    ) u_platform_collision (
        .next_player_x(prepared_x),
        .feet_fp(feet_fp),
        .next_feet_fp(next_feet_fp),
        .falling(falling),
        .platform_x_bus(platform_x_bus),
        .platform_y_bus(platform_y_bus),
        .platform_width_bus(platform_width_bus),
        .platform_active(platform_active),
        .landed(landed),
        .landing_y(landing_y),
        .landing_platform_index(landing_platform_index),
        .supported(supported)
    );

    platform_collision #(
        .PLATFORM_COUNT(PLATFORM_COUNT),
        .PLAYER_WIDTH(PLAYER_WIDTH)
    ) u_support_before_move (
        .next_player_x(player_x),
        .feet_fp(feet_fp),
        .next_feet_fp(feet_fp),
        .falling(1'b0),
        .platform_x_bus(platform_x_bus),
        .platform_y_bus(platform_y_bus),
        .platform_width_bus(platform_width_bus),
        .platform_active(platform_active),
        .landed(),
        .landing_y(),
        .landing_platform_index(),
        .supported(supported_before_move)
    );

endmodule
