`timescale 1ns / 1ps

module renderer #(
    parameter integer PLATFORM_COUNT = 10,
    parameter integer PLAYER_WIDTH = 16,
    parameter integer PLAYER_HEIGHT = 16,
    parameter integer PLATFORM_HEIGHT = 6,
    parameter integer ENEMY_HEIGHT = 12,
    parameter integer ENEMY_WIDTH = 12,
    parameter integer ENEMY_COUNT = 3,
    parameter integer BULLET_COUNT = ENEMY_COUNT * 4,
    parameter integer BULLET_SIZE = 4
)(
    input wire pixel_clk,
    input wire rst,
    input wire [9:0] pixel_x,
    input wire [9:0] pixel_y,
    input wire video_on,

    input wire [9:0] player_x,
    input wire [9:0] player_y,

    input wire               purple_active,
    input wire        [9:0]  purple_x,
    input wire signed [11:0] purple_y,

    input wire [PLATFORM_COUNT*10-1:0] platform_x_bus,
    input wire [PLATFORM_COUNT*10-1:0] platform_y_bus,
    input wire [PLATFORM_COUNT*10-1:0] platform_width_bus,
    input wire [PLATFORM_COUNT-1:0] platform_active,
    input wire [PLATFORM_COUNT-1:0] platform_reward_ready,
    
    input wire [ENEMY_COUNT*10-1:0] enemy_x_bus,
    input wire [ENEMY_COUNT*11-1:0] enemy_y_bus,
    input wire [ENEMY_COUNT-1:0] enemy_active,

    input wire [BULLET_COUNT*12-1:0] bullet_x_bus,
    input wire [BULLET_COUNT*12-1:0] bullet_y_bus,
    input wire [BULLET_COUNT-1:0] bullet_active,

    input wire game_over,
    input wire heal_scene_on,
    input wire domain_scene_on,
    input wire purple_scene_on,
    input wire challenger_scene_on,
    input wire [19:0] score_digits,
    input wire [2:0] hp,
    input wire [2:0] cursed_energy,

    output wire [3:0] red,
    output wire [3:0] green,
    output wire [3:0] blue,

    input wire [9:0] attack_fx_x,
    input wire [9:0] attack_fx_y,
    input wire [2:0] attack_fx_frames
);

    wire player_on;
    wire [11:0] player_rgb;
    wire purple_on;
    wire [11:0] purple_rgb;
    wire attack_fx_on;
    wire [11:0] attack_fx_rgb;
    wire [11:0] final_rgb;
    wire hud_on;
    wire [11:0] hud_rgb;
    wire [ENEMY_COUNT-1:0] enemy_on;
    wire [ENEMY_COUNT*12-1:0] enemy_rgb_bus;
    wire [BULLET_COUNT-1:0] bullet_on;

    wire [PLATFORM_COUNT-1:0] platform_on;
    wire [PLATFORM_COUNT*12-1:0] platform_rgb_bus;

    wire game_over_draw_on;
    wire [11:0] game_over_rgb;
    wire heal_scene_draw_on;
    wire [11:0] heal_scene_rgb;
    wire domain_scene_draw_on;
    wire [11:0] domain_scene_rgb;
    wire purple_scene_draw_on;
    wire [11:0] purple_scene_rgb;
    wire challenger_scene_draw_on;
    wire [11:0] challenger_scene_rgb;

    reg [11:0] platform_color;
    reg upper_on_d;
    reg [11:0] upper_rgb_d;
    reg [11:0] platform_color_d;
    reg [11:0] enemy_color;
    reg bullet_on_d;
    integer i;
    integer enemy_slot;

    scene_renderer #(
        .MEM_FILE("game-over-320x240-gray4.mem")
    ) u_game_over_scene (
        .pixel_clk(pixel_clk),
        .rst(rst),
        .video_on(video_on),
        .scene_on(game_over),
        .pixel_x(pixel_x),
        .pixel_y(pixel_y),
        .draw_on(game_over_draw_on),
        .rgb(game_over_rgb)
    );

    tiled_scene_renderer #(
        .TILE_MAP_FILE("heal-cutscene-tile-map.mem"),
        .TILE_PIXELS_FILE("heal-cutscene-tile-pixels.mem"),
        .TILE_COUNT(1649)
    ) u_heal_scene (
        .pixel_clk(pixel_clk),
        .rst(rst),
        .video_on(video_on),
        .scene_on(heal_scene_on),
        .pixel_x(pixel_x),
        .pixel_y(pixel_y),
        .draw_on(heal_scene_draw_on),
        .rgb(heal_scene_rgb)
    );

    tiled_scene_renderer #(
        .TILE_MAP_FILE("unlimited-void-tile-map.mem"),
        .TILE_PIXELS_FILE("unlimited-void-tile-pixels.mem"),
        .TILE_COUNT(2604)
    ) u_domain_scene(
        .pixel_clk(pixel_clk),
        .rst(rst),
        .video_on(video_on),
        .scene_on(domain_scene_on),
        .pixel_x(pixel_x),
        .pixel_y(pixel_y),
        .draw_on(domain_scene_draw_on),
        .rgb(domain_scene_rgb)
    );

    tiled_scene_renderer u_purple_scene (
        .pixel_clk(pixel_clk),
        .rst(rst),
        .video_on(video_on),
        .scene_on(purple_scene_on),
        .pixel_x(pixel_x),
        .pixel_y(pixel_y),
        .draw_on(purple_scene_draw_on),
        .rgb(purple_scene_rgb)
    );

    tiled_scene_renderer #(
        .TILE_MAP_FILE("challenger-cutscene-tile-map.mem"),
        .TILE_PIXELS_FILE("challenger-cutscene-tile-pixels.mem"),
        .TILE_COUNT(3050)
    ) u_challenger_scene (
        .pixel_clk(pixel_clk),
        .rst(rst),
        .video_on(video_on),
        .scene_on(challenger_scene_on && !game_over),
        .pixel_x(pixel_x),
        .pixel_y(pixel_y),
        .draw_on(challenger_scene_draw_on),
        .rgb(challenger_scene_rgb)
    );

    player_renderer #(
        .PLAYER_WIDTH(PLAYER_WIDTH),
        .PLAYER_HEIGHT(PLAYER_HEIGHT)
    ) u_player_renderer(
        .pixel_clk(pixel_clk),
        .pixel_x(pixel_x),
        .pixel_y(pixel_y),
        .player_x(player_x),
        .player_y(player_y),
        .draw_on(player_on),
        .rgb(player_rgb)
    );

    purple_renderer u_purple_renderer (
        .pixel_clk(pixel_clk),
        .rst(rst),
        .pixel_x(pixel_x),
        .pixel_y(pixel_y),
        .purple_active(purple_active),
        .purple_x(purple_x),
        .purple_y(purple_y),
        .draw_on(purple_on),
        .rgb(purple_rgb)
    );

    attack_fx_renderer #(
        .PLAYER_WIDTH(PLAYER_WIDTH),
        .PLAYER_HEIGHT(PLAYER_HEIGHT)
    ) u_attack_fx_renderer (
        .pixel_clk(pixel_clk),
        .pixel_x(pixel_x),
        .pixel_y(pixel_y),
        .attack_fx_x(attack_fx_x),
        .attack_fx_y(attack_fx_y),
        .attack_fx_frames(attack_fx_frames),
        .draw_on(attack_fx_on),
        .rgb(attack_fx_rgb)
    );

    genvar platform_index, enemy_index, bullet_index;
    generate
        for (platform_index = 0; platform_index < PLATFORM_COUNT; platform_index = platform_index + 1) begin : gen_platform_draw
            platform_renderer #(
                .PLATFORM_HEIGHT(PLATFORM_HEIGHT)
            ) u_platform_renderer (
                .pixel_x(pixel_x),
                .pixel_y(pixel_y),
                .platform_x(platform_x_bus[platform_index*10 +: 10]),
                .platform_y(platform_y_bus[platform_index*10 +: 10]),
                .platform_width(platform_width_bus[platform_index*10 +: 10]),
                .platform_active(platform_active[platform_index]),
                .platform_reward_ready(platform_reward_ready[platform_index]),
                .draw_on(platform_on[platform_index]),
                .rgb(platform_rgb_bus[platform_index*12 +: 12])
            );
        end

        for (enemy_index = 0; enemy_index < ENEMY_COUNT; enemy_index = enemy_index + 1) begin : gen_enemy_draw
            enemy_renderer #(
                .ENEMY_HEIGHT(ENEMY_HEIGHT),
                .ENEMY_WIDTH(ENEMY_WIDTH)
            ) u_enemy_renderer (
                .pixel_clk(pixel_clk),
                .pixel_x(pixel_x),
                .pixel_y(pixel_y),
                .enemy_x(enemy_x_bus[enemy_index*10 +: 10]),
                .enemy_y($signed(enemy_y_bus[enemy_index*11 +: 11])),
                .enemy_active(enemy_active[enemy_index]),
                .draw_on(enemy_on[enemy_index]),
                .rgb(enemy_rgb_bus[enemy_index*12 +: 12])
            );
        end

        for (bullet_index = 0; bullet_index < BULLET_COUNT; bullet_index = bullet_index + 1) begin : gen_bullet_draw
            bullet_renderer #(
                .BULLET_SIZE(BULLET_SIZE)
            ) u_bullet_renderer (
                .pixel_x(pixel_x),
                .pixel_y(pixel_y),
                .bullet_x($signed(bullet_x_bus[bullet_index*12 +: 12])),
                .bullet_y($signed(bullet_y_bus[bullet_index*12 +: 12])),
                .bullet_active(bullet_active[bullet_index]),
                .draw_on(bullet_on[bullet_index])
            );
        end
    endgenerate

    // Select the color of a platform covering the current pixel.
    always @(*) begin
        platform_color = 12'h000;

        for (i = PLATFORM_COUNT - 1; i >= 0; i = i - 1) begin
            if (platform_on[i]) begin
                platform_color = platform_rgb_bus[i*12 +: 12];
            end
        end
    end

    // Prefer the lowest slot index when opaque enemy pixels overlap.
    always @(*) begin
        enemy_color = 12'h000;
        for (enemy_slot = ENEMY_COUNT - 1; enemy_slot >= 0; enemy_slot = enemy_slot - 1) begin
            if (enemy_on[enemy_slot])
                enemy_color = enemy_rgb_bus[enemy_slot*12 +: 12];
        end
    end

    hud_renderer u_hud (
        .pixel_x(pixel_x),
        .pixel_y(pixel_y),
        .score_digits(score_digits),
        .hp(hp),
        .cursed_energy(cursed_energy),
        .hud_on(hud_on),
        .hud_rgb(hud_rgb)
    );

    // Align the other layers with the synchronous image reads.
    always @(posedge pixel_clk) begin
        if (rst) begin
            upper_on_d  <= 1'b1;
            upper_rgb_d <= 12'h000;
            platform_color_d <= 12'h000;
            bullet_on_d <= 1'b0;
        end else begin
            upper_on_d  <= !video_on || hud_on;
            upper_rgb_d <= !video_on ? 12'h000 : hud_rgb;
            bullet_on_d <= |bullet_on;
            platform_color_d <= platform_color;
        end
    end
    assign final_rgb = challenger_scene_draw_on ? challenger_scene_rgb :
                       upper_on_d         ? upper_rgb_d    :
                       game_over_draw_on  ? game_over_rgb  :
                       domain_scene_draw_on ? domain_scene_rgb :
                       purple_scene_draw_on ? purple_scene_rgb :
                       heal_scene_draw_on ? heal_scene_rgb :
                       player_on          ? player_rgb     :
                       purple_on          ? purple_rgb     :
                       bullet_on_d        ? 12'hFF0        :
                       attack_fx_on       ? attack_fx_rgb  :
                       (|enemy_on)        ? enemy_color    :
                       platform_color_d;

    assign red   = final_rgb[11:8];
    assign green = final_rgb[7:4];
    assign blue  = final_rgb[3:0];

endmodule
