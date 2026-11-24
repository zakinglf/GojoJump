`timescale 1ns / 1ps

module top #(
    // Character dimensions and spawn position, in pixels.
    parameter integer PLAYER_WIDTH = 16,
    parameter integer PLAYER_HEIGHT = 16,
    parameter integer PLAYER_START_X = 290,
    parameter integer PLAYER_START_Y = 424,
    parameter integer PLAYER_MOVE_STEP = 2,

    // Vertical physics use 1/16 pixel units per movement tick.
    parameter signed [15:0] GRAVITY_FP = 16'sd4,
    parameter signed [15:0] JUMP_VELOCITY_FP = -16'sd64,
    parameter integer SCROLL_LINE_Y = 320,

    // Platform dimensions and initial layout, in pixels.
    parameter integer PLATFORM_COUNT = 44,
    parameter integer PLATFORM_WIDTH = 36,
    parameter integer PLATFORM_HEIGHT = 4,
    parameter integer PLATFORM_BOTTOM_Y = 440,
    parameter integer PLATFORM_Y_GAP = 28,
    parameter integer PLATFORM_START_X = 280,
    parameter integer PLATFORM_X_GAP = 68,

    parameter integer ENEMY_COUNT = 3,
    parameter integer ENEMY_WIDTH = 12,
    parameter integer ENEMY_HEIGHT = 12
) (
    input wire clk,
    input wire rst,
    input wire rx,

    output reg [3:0] vga_red,
    output reg [3:0] vga_green,
    output reg [3:0] vga_blue,
    output reg vga_hsync,
    output reg vga_vsync
);

    localparam integer PLATFORM_INDEX_WIDTH = (PLATFORM_COUNT > 1) ? $clog2(PLATFORM_COUNT) : 1;
    localparam integer BULLETS_PER_ENEMY = 4;
    localparam integer BULLET_COUNT = ENEMY_COUNT * BULLETS_PER_ENEMY;
    localparam integer BULLET_GROUP_WIDTH = BULLETS_PER_ENEMY * 12;
    localparam integer BULLET_SIZE = 4;
    localparam signed [11:0] ATTACK_PAD_X = 12'sd20;
    localparam signed [11:0] ATTACK_PAD_Y = 12'sd20;
    localparam [5:0] HEAL_HOLD_FRAMES = 6'd60;
    localparam integer KILL_COUNT_WIDTH = $clog2(ENEMY_COUNT + 1);
    localparam [15:0] SCORE_PER_KILL = 16'd50;
    localparam signed [11:0] PURPLE_DIAMETER = 12'sd128;
    localparam [15:0] CHALLENGER_SCORE = 16'd800;
    localparam [6:0] CHALLENGER_SCENE_FRAMES = 7'd60;
    localparam [2:0] SCENE_NONE       = 3'd0;
    localparam [2:0] SCENE_HEAL       = 3'd1;
    localparam [2:0] SCENE_DOMAIN     = 3'd2;
    localparam [2:0] SCENE_PURPLE     = 3'd3;
    localparam [2:0] SCENE_CHALLENGER = 3'd4;


    // Pixel clock and VGA signals.
    reg [1:0] clk_div = 2'b00;
    // Reset the game for four pixel clocks after FPGA configuration.
    (* shreg_extract = "no" *) reg [3:0] power_on_reset = 4'b1111;
    wire game_rst = rst || power_on_reset[3];
    wire pixel_clk;
    wire [9:0] pixel_x;
    wire [9:0] pixel_y;
    wire video_on;
    wire hsync_raw;
    wire vsync_raw;
    wire [11:0] rgb_raw;
    reg [1:0] sync_d;

    // Frame update and collision timing.
    reg vsync_d = 1'b1;
    wire move_prepare;
    reg move_tick;
    wire layout_ready;
    reg hit_tick;
    wire game_over;
    wire fell_off_screen;

    // UART input and movement commands.
    wire [7:0] rx_data;
    wire rx_valid;
    wire move_left;
    wire move_right;
    wire jump_pressed;
    wire dash_pressed;
    wire attack_pressed;
    wire heal_down;

    reg attack_pending;
    reg attack_this_frame;
    wire attack_tick;
    reg [2:0] attack_fx_frames;
    reg [9:0] attack_fx_x, attack_fx_y;

    // Player position, camera scroll, health, and score.
    wire [9:0] player_x;
    wire [9:0] player_y;
    wire [9:0] scroll_dy;
    wire hit_player;
    wire [2:0] hp;
    wire [2:0] cursed_energy;
    wire invincible;
    wire [15:0] score;
    wire [19:0] score_digits;

    wire               purple_cast;
    reg                purple_launch;
    wire               purple_active;
    wire        [9:0]  purple_x;
    wire signed [11:0] purple_y;
    reg                purple_hit_tick;

    // Platform data shared by physics and rendering.
    wire [PLATFORM_COUNT * 10 - 1:0] platform_x_bus;
    wire [PLATFORM_COUNT * 10 - 1:0] platform_y_bus;
    wire [PLATFORM_COUNT * 10 - 1:0] platform_width_bus;
    wire [PLATFORM_COUNT - 1:0] platform_active;
    wire [PLATFORM_COUNT - 1:0] platform_reward_ready;
    wire player_on_ground;
    wire landed_on_platform;
    wire [PLATFORM_INDEX_WIDTH-1:0] landed_platform_index;
    wire platform_reward_request = landed_on_platform && platform_reward_ready[landed_platform_index];
    wire platform_reward_claimed;

    // Enemy and projectile data.
    wire [ENEMY_COUNT * 10 - 1:0] enemy_x_bus;
    wire [ENEMY_COUNT * 11 - 1:0] enemy_y_bus;
    wire [ENEMY_COUNT - 1:0] enemy_active;
    wire [BULLET_COUNT * 12 - 1:0] bullet_x_bus;
    wire [BULLET_COUNT * 12 - 1:0] bullet_y_bus;
    wire [BULLET_COUNT - 1:0] bullet_active;
    wire [BULLET_COUNT - 1:0] bullet_hit;
    wire [ENEMY_COUNT - 1:0] melee_hit;
    wire [ENEMY_COUNT - 1:0] purple_hit;
    wire black_flash_hit;

    reg [5:0] heal_hold_frames;
    wire heal_request = hit_tick && !game_rst && !game_over && heal_down &&
                        (heal_hold_frames == HEAL_HOLD_FRAMES - 6'd1);

    reg [2:0] scene_id;
    reg challenger_played;
    reg [6:0] scene_left;
    wire frame_tick = vsync_d && !vsync_raw;
    wire pause_game = (scene_left != 7'd0);
    wire heal_scene_on = pause_game && (scene_id == SCENE_HEAL);
    wire domain_scene_on = pause_game && (scene_id == SCENE_DOMAIN);
    wire purple_scene_on = pause_game && (scene_id == SCENE_PURPLE);
    wire challenger_scene_on = pause_game && (scene_id == SCENE_CHALLENGER);
    // Wait for the player's committed position to be supported.
    wire challenger_start = !challenger_played && !pause_game &&
                            !move_prepare && !move_tick && player_on_ground &&
                            (score >= CHALLENGER_SCORE);
    wire heal_applied;

    wire domain_pressed;
    reg domain_pending;
    wire spell_input_allowed = !game_rst && !game_over && !pause_game;
    wire domain_request = spell_input_allowed && hit_tick && (domain_pending || domain_pressed);
    wire domain_fire;
    wire purple_pressed;
    reg purple_pending;
    wire purple_input_allowed = spell_input_allowed && !purple_active;
    wire purple_request = purple_input_allowed && hit_tick && (purple_pending || purple_pressed);
    wire [ENEMY_COUNT-1:0] enemy_kill_mask =
        melee_hit | purple_hit | ({ENEMY_COUNT{domain_fire}} & enemy_active);

    reg [KILL_COUNT_WIDTH-1:0] kill_count;
    wire [15:0] kill_bonus = kill_count * SCORE_PER_KILL;


    always @* begin : count_kills
        integer i;
        kill_count = 0;
        for (i = 0; i < ENEMY_COUNT; i = i + 1) begin
            kill_count = kill_count + enemy_kill_mask[i];
        end
    end

    always @(posedge pixel_clk) begin
        if (!spell_input_allowed || hit_tick) begin
            domain_pending <= 1'b0;
        end else if (domain_pressed) begin
            domain_pending <= 1'b1;
        end
    end

    always @(posedge pixel_clk) begin
        if (!purple_input_allowed || hit_tick)
            purple_pending <= 1'b0;
        else if (purple_pressed)
            purple_pending <= 1'b1;

        // Check the orb after its launch coordinates commit, including the first frame.
        purple_hit_tick <= spell_input_allowed && (purple_launch || (hit_tick && purple_active));
    end

    assign black_flash_hit = |melee_hit;

    always @(posedge pixel_clk) begin
        purple_launch <= 1'b0;
        if (game_rst || game_over) begin
            scene_id <= SCENE_NONE;
            scene_left <= 7'd0;
            if (game_rst)
                challenger_played <= 1'b0;
        end else if (domain_fire) begin
            scene_id <= SCENE_DOMAIN;
            scene_left <= 7'd60;
        end else if(purple_cast) begin
            scene_id <= SCENE_PURPLE;
            scene_left <= 7'd60;
        end else if (heal_applied) begin
            scene_id <= SCENE_HEAL;
            scene_left <= 7'd45;
        end else if (challenger_start) begin
            scene_id <= SCENE_CHALLENGER;
            scene_left <= CHALLENGER_SCENE_FRAMES;
            challenger_played <= 1'b1;
        end else if (frame_tick && pause_game) begin
            scene_left <= scene_left - 7'd1;
            if(scene_left == 7'd1) begin
                scene_id <= SCENE_NONE;
                if (scene_id == SCENE_PURPLE) begin
                    purple_launch <= 1'b1;
                end
            end
        end
    end

    always @(posedge pixel_clk) begin
        if (game_rst || game_over || !heal_down) begin
            heal_hold_frames <= 6'd0;
        end else if (hit_tick && heal_hold_frames < HEAL_HOLD_FRAMES) begin
            heal_hold_frames <= heal_hold_frames + 6'd1;
        end
    end

    // Clock division and game update pulses.
    // Initialize the divider and keep the pixel clock running.
    always @(posedge clk) begin
        clk_div <= clk_div + 2'b01;
    end

    assign pixel_clk = clk_div[1];

    always @(posedge pixel_clk) begin
        power_on_reset <= {power_on_reset[2:0], 1'b0};
    end

    // Store the previous value of the vertical sync signal
    always @(posedge pixel_clk) begin
        if (game_rst) begin
            vsync_d <= 1'b1;
        end else begin
            vsync_d <= vsync_raw;
        end
    end

    // Prepare movement at vertical sync and commit it one pixel clock later.
    assign move_prepare = !game_rst && frame_tick && layout_ready &&
                          !game_over && !pause_game;

    always @(posedge pixel_clk) begin
        if (game_rst)
            move_tick <= 1'b0;
        else
            move_tick <= move_prepare;
    end
    assign game_over = !game_rst && (fell_off_screen || (hp == 3'd0));

    // Sample collisions after the frame's positions have been updated.
    always @(posedge pixel_clk) begin
        if (game_rst)
            hit_tick <= 1'b0;
        else
            hit_tick <= move_tick;
    end

    always @(posedge pixel_clk) begin
        if (game_rst || game_over || pause_game) begin
            attack_pending <= 1'b0;
            attack_this_frame <= 1'b0;
        end else begin
            if (move_prepare) begin
                attack_this_frame <= attack_pending || attack_pressed;
                attack_pending <= 1'b0;
            end else begin
                if (hit_tick)
                    attack_this_frame <= 1'b0;
                if (attack_pressed)
                    attack_pending <= 1'b1;
            end
        end
    end

    assign attack_tick = hit_tick && attack_this_frame && !game_over;

    // Keep the attack outline at the position used for hit detection.
    always @(posedge pixel_clk) begin
        if (game_rst || game_over) begin
            attack_fx_frames <= 3'd0;
            attack_fx_x <= 10'd0;
            attack_fx_y <= 10'd0;
        end else if (attack_tick) begin
            attack_fx_frames <= 3'd4;
            attack_fx_x <= player_x;
            attack_fx_y <= player_y;
        end else if (move_tick && attack_fx_frames != 3'd0) begin
            attack_fx_frames <= attack_fx_frames - 3'd1;
        end
    end

    // Keyboard input.
    uart_rx u_uart_rx (
        .clk(pixel_clk),
        .rst(game_rst),
        .rx(rx),
        .rx_data(rx_data),
        .rx_valid(rx_valid)
    );

    input_ctrl u_input_ctrl (
        .clk(pixel_clk),
        .rst(game_rst),
        .rx_data(rx_data),
        .rx_valid(rx_valid),
        .move_left(move_left),
        .move_right(move_right),
        .jump_pressed(jump_pressed),
        .dash_pressed(dash_pressed),
        .attack_pressed(attack_pressed),
        .heal_down(heal_down),
        .domain_pressed(domain_pressed),
        .purple_pressed(purple_pressed)
    );

    // Player movement and platform generation.
    player_ctrl #(
        .PLATFORM_COUNT(PLATFORM_COUNT),
        .PLAYER_WIDTH(PLAYER_WIDTH),
        .PLAYER_HEIGHT(PLAYER_HEIGHT),
        .START_X(PLAYER_START_X),
        .START_Y(PLAYER_START_Y),
        .MOVE_STEP(PLAYER_MOVE_STEP),
        .GRAVITY_FP(GRAVITY_FP),
        .JUMP_VELOCITY_FP(JUMP_VELOCITY_FP),
        .SCROLL_LINE_Y(SCROLL_LINE_Y)
    ) u_player_ctrl (
        .move_prepare(move_prepare),
        .pixel_clk(pixel_clk),
        .rst(game_rst),
        .move_tick(move_tick),
        .pause_game(pause_game),
        .move_left(move_left),
        .move_right(move_right),
        .jump_pressed(jump_pressed),
        .dash_pressed(dash_pressed),
        .black_flash_hit(black_flash_hit),

        .platform_x_bus(platform_x_bus),
        .platform_y_bus(platform_y_bus),
        .platform_width_bus(platform_width_bus),
        .platform_active(platform_active),

        .player_x(player_x),
        .player_y(player_y),
        .scroll_dy(scroll_dy),
        .fell_off_screen(fell_off_screen),
        .on_ground_before_move(player_on_ground),
        .landed_on_platform(landed_on_platform),
        .landed_platform_index(landed_platform_index)
    );

    purple_ctrl #(
        .PLAYER_WIDTH(PLAYER_WIDTH[9:0]),
        .PURPLE_HEIGHT(PURPLE_DIAMETER)
    ) u_purple_ctrl (
        .pixel_clk(pixel_clk),
        .rst(game_rst || game_over),
        .move_tick(move_tick),
        .purple_launch(purple_launch),
        .player_x(player_x),
        .player_y(player_y),
        .scroll_dy(scroll_dy),
        .purple_active(purple_active),
        .purple_x(purple_x),
        .purple_y(purple_y)
    );

    platform_ctrl #(
        .PLATFORM_COUNT(PLATFORM_COUNT),
        .INITIAL_BOTTOM_Y(PLATFORM_BOTTOM_Y),
        .INITIAL_Y_GAP(PLATFORM_Y_GAP),
        .INITIAL_WIDTH(PLATFORM_WIDTH),
        .INITIAL_X(PLATFORM_START_X),
        .INITIAL_X_GAP(PLATFORM_X_GAP)
    ) u_platform_ctrl (
        .move_prepare(move_prepare),
        .pixel_clk(pixel_clk),
        .rst(game_rst),
        .move_tick(move_tick),
        .pause_game(pause_game),
        .scroll_dy(scroll_dy),
        .layout_ready(layout_ready),
        .platform_reward_claimed(platform_reward_claimed),
        .platform_reward_index(landed_platform_index),
        .platform_reward_ready(platform_reward_ready),

        .platform_x_bus(platform_x_bus),
        .platform_y_bus(platform_y_bus),
        .platform_width_bus(platform_width_bus),
        .platform_active(platform_active)
    );

    // Enemy generation and projectiles.
    enemy_ctrl #(
        .ENEMY_COUNT(ENEMY_COUNT),
        .ENEMY_WIDTH(ENEMY_WIDTH),
        .ENEMY_HEIGHT(ENEMY_HEIGHT),
        .START_SCORE(CHALLENGER_SCORE)
    ) u_enemy_ctrl (
        .pixel_clk(pixel_clk),
        .rst(game_rst),
        .move_tick(move_tick),
        .pause_game(pause_game),
        .score(challenger_played ? score : 16'd0),
        .scroll_dy(scroll_dy),
        .enemy_x_bus(enemy_x_bus),
        .enemy_y_bus(enemy_y_bus),
        .enemy_active(enemy_active),
        .kill_enemy(enemy_kill_mask)
    );

    genvar enemy_index;
    generate
        for (enemy_index = 0; enemy_index < ENEMY_COUNT; enemy_index = enemy_index + 1) begin : gen_enemy_bullets
            enemy_bullet_ctrl #(
                .ENEMY_WIDTH(ENEMY_WIDTH),
                .ENEMY_HEIGHT(ENEMY_HEIGHT),
                .BULLET_SIZE(BULLET_SIZE)
            ) u_bullet_ctrl (
                .pixel_clk(pixel_clk),
                .rst(game_rst),
                .move_tick(move_tick),
                .hit_tick(hit_tick && !game_over),
                .scroll_dy(scroll_dy),
                .enemy_x(enemy_x_bus[enemy_index*10 +: 10]),
                .enemy_y($signed(enemy_y_bus[enemy_index*11 +: 11])),
                .enemy_active(enemy_active[enemy_index]),
                .bullet_hit(bullet_hit[enemy_index*BULLETS_PER_ENEMY +: BULLETS_PER_ENEMY]),
                .bullet_x_bus(bullet_x_bus[enemy_index*BULLET_GROUP_WIDTH +: BULLET_GROUP_WIDTH]),
                .bullet_y_bus(bullet_y_bus[enemy_index*BULLET_GROUP_WIDTH +: BULLET_GROUP_WIDTH]),
                .bullet_active(bullet_active[enemy_index*BULLETS_PER_ENEMY +: BULLETS_PER_ENEMY])
            );
        end
    endgenerate

    // Hit detection and health.
    player_hit_detection #(
        .PLAYER_WIDTH(PLAYER_WIDTH),
        .PLAYER_HEIGHT(PLAYER_HEIGHT),
        .ENEMY_COUNT(ENEMY_COUNT),
        .ENEMY_WIDTH(ENEMY_WIDTH),
        .ENEMY_HEIGHT(ENEMY_HEIGHT),
        .BULLET_COUNT(BULLET_COUNT),
        .BULLET_SIZE(BULLET_SIZE),
        .ENABLE_PURPLE_COLLISION(1'b1),
        .PURPLE_DIAMETER(PURPLE_DIAMETER),
        .ATTACK_PAD_X(ATTACK_PAD_X),
        .ATTACK_PAD_Y(ATTACK_PAD_Y)
    ) u_player_hit_detection (
        .player_x(player_x),
        .player_y(player_y),
        .attack_tick(attack_tick),
        .purple_hit_tick(purple_hit_tick && spell_input_allowed && purple_active &&
                        (purple_y > -PURPLE_DIAMETER)),
        .purple_x(purple_x),
        .purple_y(purple_y),
        .enemy_x_bus(enemy_x_bus),
        .enemy_y_bus(enemy_y_bus),
        .enemy_active(enemy_active),
        .bullet_x_bus(bullet_x_bus),
        .bullet_y_bus(bullet_y_bus),
        .bullet_active(bullet_active),
        .hit_player(hit_player),
        .bullet_hit(bullet_hit),
        .melee_hit(melee_hit),
        .purple_hit(purple_hit)
    );

    player_health u_player_health (
        .pixel_clk(pixel_clk),
        .rst(game_rst),
        .hit_tick(hit_tick && !game_over),
        .hit_player(hit_player),
        .hp(hp),
        .platform_reward_request(platform_reward_request),
        .platform_reward_claimed(platform_reward_claimed),
        .heal_request(heal_request),
        .domain_request(domain_request),
        .purple_request(purple_request),
        .cursed_energy(cursed_energy),
        .invincible(invincible),
        .black_flash_hit(black_flash_hit),
        .heal_applied(heal_applied),
        .domain_fire(domain_fire),
        .purple_fire(purple_cast)
    );

    // Score accumulation and display digits.
    score_ctrl u_score_ctrl (
        .pixel_clk(pixel_clk),
        .rst(game_rst),
        .move_tick(move_tick),
        .scroll_dy(scroll_dy),
        .kill_bonus(kill_bonus),
        .score(score),
        .score_digits(score_digits)
    );

    // Video timing and rendering.
    vga_timing u_vga_timing (
        .pixel_clk(pixel_clk),
        .rst(game_rst),
        .pixel_x(pixel_x),
        .pixel_y(pixel_y),
        .video_on(video_on),
        .hsync(hsync_raw),
        .vsync(vsync_raw)
    );

    renderer #(
        .PLATFORM_COUNT(PLATFORM_COUNT),
        .PLAYER_WIDTH(PLAYER_WIDTH),
        .PLAYER_HEIGHT(PLAYER_HEIGHT),
        .PLATFORM_HEIGHT(PLATFORM_HEIGHT),
        .ENEMY_COUNT(ENEMY_COUNT),
        .ENEMY_WIDTH(ENEMY_WIDTH),
        .ENEMY_HEIGHT(ENEMY_HEIGHT),
        .BULLET_COUNT(BULLET_COUNT),
        .BULLET_SIZE(BULLET_SIZE)
    ) u_renderer (
        .pixel_clk(pixel_clk),
        .rst(game_rst),
        .pixel_x(pixel_x),
        .pixel_y(pixel_y),
        .video_on(video_on),
        .game_over(game_over),
        .heal_scene_on(heal_scene_on),
        .domain_scene_on(domain_scene_on),
        .purple_scene_on(purple_scene_on),
        .challenger_scene_on(challenger_scene_on),
        .score_digits(score_digits),
        .hp(hp),
        .cursed_energy(cursed_energy),
        .attack_fx_x(attack_fx_x),
        .attack_fx_y(attack_fx_y),
        .attack_fx_frames(attack_fx_frames),

        .player_x(player_x),
        .player_y(player_y),

        .purple_active(purple_active),
        .purple_x(purple_x),
        .purple_y(purple_y),

        .platform_x_bus(platform_x_bus),
        .platform_y_bus(platform_y_bus),
        .platform_width_bus(platform_width_bus),
        .platform_active(platform_active),
        .platform_reward_ready(platform_reward_ready),

        .enemy_x_bus(enemy_x_bus),
        .enemy_y_bus(enemy_y_bus),
        .enemy_active(enemy_active),

        .bullet_x_bus(bullet_x_bus),
        .bullet_y_bus(bullet_y_bus),
        .bullet_active(bullet_active),

        .red(rgb_raw[11:8]),
        .green(rgb_raw[7:4]),
        .blue(rgb_raw[3:0])
    );

    // Match the renderer latency before registering both signals at the VGA pins.
    always @(posedge pixel_clk) begin
        if (game_rst) begin
            sync_d <= 2'b11;
            {vga_hsync, vga_vsync} <= 2'b11;
            {vga_red, vga_green, vga_blue} <= 12'h000;
        end else begin
            sync_d <= {hsync_raw, vsync_raw};
            {vga_hsync, vga_vsync} <= sync_d;
            {vga_red, vga_green, vga_blue} <= rgb_raw;
        end
    end

endmodule
